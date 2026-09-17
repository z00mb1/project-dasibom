import sys
import os
import uuid
import copy
import time
import tempfile
import traceback
from typing import Optional

import cv2
import dlib
import numpy as np
import PIL.Image
import torch
import torch.nn as nn
import torch.nn.functional as F
from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.responses import FileResponse
from PIL import Image
from insightface.app import FaceAnalysis

# SAM 소스 경로: 환경변수 SAM_SRC 우선, 없으면 ./SAM (저장소 내 SAM 모듈 위치)
SAM_SRC = os.environ.get('SAM_SRC', os.path.join(os.path.dirname(__file__), 'SAM'))
sys.path.insert(0, SAM_SRC)

from models.psp import pSp
from datasets.augmentations import AgeTransformer
from utils.common import tensor2im
from criteria.lpips.lpips import LPIPS
from argparse import Namespace
import torchvision.transforms as transforms

# CodeFormer
from codeformer.app import inference_app

app = FastAPI(title="다시봄 AI API", version="2.0.0")

# ===== 모델 가중치 경로 =====
# 환경변수로 개별 지정 가능하며, 없으면 ./weights/ 아래 기본 파일명을 사용합니다.
# (가중치 파일은 저장소에 포함되지 않습니다. README의 "모델 준비" 참고)
WEIGHTS_DIR = os.environ.get('WEIGHTS_DIR', os.path.join(os.path.dirname(__file__), 'weights'))

SAM_KOREAN_PATH    = os.environ.get('SAM_KOREAN_PATH',    os.path.join(WEIGHTS_DIR, 'sam_korean_best_model.pt'))
SAM_WESTERN_PATH   = os.environ.get('SAM_WESTERN_PATH',   os.path.join(WEIGHTS_DIR, 'sam_ffhq_aging.pt'))
LANDMARK_PATH      = os.environ.get('LANDMARK_PATH',      os.path.join(WEIGHTS_DIR, 'shape_predictor_68_face_landmarks.dat'))
RAGAN_WEIGHTS_PATH = os.environ.get('RAGAN_WEIGHTS_PATH', os.path.join(WEIGHTS_DIR, 'ragan_final_v2.pt'))

# CodeFormer
CODEFORMER_FIDELITY = 0.7

# PTI 설정
PTI_STEPS = 150          # decoder 미세조정 스텝 (시연 절충: 150=14초/정체성0.62, 250=24초/0.67)
PTI_LR = 3e-4
ENABLE_PTI = True        # PTI 켜기/끄기 스위치

# FFHQ 정렬 설정
FFHQ_SCALE = 2.4         # 검증된 최적값 (검출 100% + ID 최고)

# 나이 보정 설정
# SAM이 나이를 압축 반영하지만, target을 크게 밀면 정체성/성별/인종이 붕괴됨.
# 따라서 강한 역산 대신 약한 고정 오프셋(+AGE_OFFSET)만 적용해 안전하게 나이만 살짝 더 반영.
ENABLE_AGE_CALIBRATION = True
AGE_OFFSET = 5            # 요청 나이 + 5 를 target으로 (정체성 보호, 검증된 최적값)
AGE_CEILING = 40          # 이 이상 요청 시 경고 (데이터 부족, 정확도 낮음)
TARGET_MAX = 60           # 안전 상한 (이 이상은 정체성 붕괴 구간)


def calibrate_target_age(desired_age):
    """요청 나이에 소폭 오프셋만 적용 (정체성 우선).
    반환: (보정 target, 경고 여부)"""
    if not ENABLE_AGE_CALIBRATION:
        return desired_age, desired_age > AGE_CEILING
    calibrated = desired_age + AGE_OFFSET
    calibrated = int(round(max(0, min(TARGET_MAX, calibrated))))
    warning = desired_age > AGE_CEILING
    return calibrated, warning

sam_model_korean = None
sam_model_western = None
face_app = None
landmark_predictor = None
face_detector = None
lpips_fn = None

# decoder 원본 상태 백업 (PTI 후 복구용)
_decoder_backup_korean = None
_decoder_backup_western = None

img_transform = transforms.Compose([
    transforms.Resize((256, 256)),
    transforms.ToTensor(),
    transforms.Normalize([0.5, 0.5, 0.5], [0.5, 0.5, 0.5])
])

l2_loss = nn.MSELoss()


def load_single_sam(model_path, ragan_path=None):
    ckpt = torch.load(model_path, map_location='cpu')
    opts = ckpt['opts']
    opts['checkpoint_path'] = model_path
    opts['device'] = 'cuda'
    opts = Namespace(**opts)
    model = pSp(opts)

    # v2: race_mixers만 로드 (검증된 완전체, FairFace EastAsian 93.4%)
    if ragan_path and os.path.exists(ragan_path):
        print(f"RA-GAN 가중치 로딩: {ragan_path}")
        ragan_ckpt = torch.load(ragan_path, map_location='cpu')
        model.race_mixers.load_state_dict(ragan_ckpt['race_mixers'], strict=True)
        print("RA-GAN race_mixers 로딩 완료! (v2)")
    else:
        print("RA-GAN 가중치 없음 - 랜덤 초기화 상태로 사용")

    model.eval()
    model.cuda()
    return model


def load_models():
    global sam_model_korean, sam_model_western, face_app
    global landmark_predictor, face_detector, lpips_fn
    global _decoder_backup_korean, _decoder_backup_western

    print("모델 로딩 중...")
    face_app = FaceAnalysis(name='buffalo_l', providers=['CUDAExecutionProvider'])
    face_app.prepare(ctx_id=0, det_size=(640, 640))
    face_detector = dlib.get_frontal_face_detector()
    landmark_predictor = dlib.shape_predictor(LANDMARK_PATH)

    print("SAM Korean 모델 로딩 중...")
    sam_model_korean = load_single_sam(SAM_KOREAN_PATH, ragan_path=RAGAN_WEIGHTS_PATH)
    print("SAM Western 모델 로딩 중...")
    sam_model_western = load_single_sam(SAM_WESTERN_PATH)

    # decoder 원본 백업 (PTI 후 복구용)
    _decoder_backup_korean = copy.deepcopy(sam_model_korean.decoder.state_dict())
    _decoder_backup_western = copy.deepcopy(sam_model_western.decoder.state_dict())

    if ENABLE_PTI:
        print("PTI용 LPIPS 로딩 중...")
        lpips_fn = LPIPS(net_type='alex').cuda().eval()

    print("CodeFormer 준비 완료 (inference_app 사용)")
    print(f"설정 - PTI: {ENABLE_PTI} (steps={PTI_STEPS}), FFHQ scale: {FFHQ_SCALE}")
    print("모델 로딩 완료!")


def get_decoder_backup(ethnicity):
    return _decoder_backup_korean if ethnicity == "korean" else _decoder_backup_western


# ===================== FFHQ 표준 정렬 =====================
def get_landmarks(img_rgb):
    dets = face_detector(img_rgb, 1)
    if not dets:
        return None
    sh = landmark_predictor(img_rgb, dets[0])
    return np.array([[sh.part(i).x, sh.part(i).y] for i in range(68)])


def align_ffhq(image_np, scale=FFHQ_SCALE, output_size=256, transform_size=1024):
    """FFHQ 표준 정렬 (SAM 학습 정렬과 일치). image_np는 BGR."""
    rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
    lm = get_landmarks(rgb)
    if lm is None:
        return None
    eye_left = np.mean(lm[36:42], axis=0)
    eye_right = np.mean(lm[42:48], axis=0)
    eye_avg = (eye_left + eye_right) * 0.5
    eye_to_eye = eye_right - eye_left
    mouth_avg = (lm[48] + lm[54]) * 0.5
    eye_to_mouth = mouth_avg - eye_avg

    x = eye_to_eye - np.flipud(eye_to_mouth) * [-1, 1]
    x /= np.hypot(*x)
    x *= max(np.hypot(*eye_to_eye) * scale, np.hypot(*eye_to_mouth) * (scale * 0.9))
    y = np.flipud(x) * [-1, 1]
    c = eye_avg + eye_to_mouth * 0.1
    quad = np.stack([c - x - y, c - x + y, c + x + y, c + x - y])
    qsize = np.hypot(*x) * 2

    ip = PIL.Image.fromarray(rgb)
    shrink = int(np.floor(qsize / output_size * 0.5))
    if shrink > 1:
        rs = (int(np.rint(ip.size[0] / shrink)), int(np.rint(ip.size[1] / shrink)))
        ip = ip.resize(rs, PIL.Image.LANCZOS)
        quad /= shrink
        qsize /= shrink
    border = max(int(np.rint(qsize * 0.1)), 3)
    crop = (int(np.floor(min(quad[:, 0]))), int(np.floor(min(quad[:, 1]))),
            int(np.ceil(max(quad[:, 0]))), int(np.ceil(max(quad[:, 1]))))
    crop = (max(crop[0] - border, 0), max(crop[1] - border, 0),
            min(crop[2] + border, ip.size[0]), min(crop[3] + border, ip.size[1]))
    if crop[2] - crop[0] < ip.size[0] or crop[3] - crop[1] < ip.size[1]:
        ip = ip.crop(crop)
        quad -= crop[0:2]
    ip = ip.transform((transform_size, transform_size), PIL.Image.QUAD,
                      (quad + 0.5).flatten(), PIL.Image.BILINEAR)
    if output_size < transform_size:
        ip = ip.resize((output_size, output_size), PIL.Image.LANCZOS)
    return ip


def crop_and_align_face(image_np):
    """FFHQ 정렬 우선, 실패 시 기존 방식 폴백"""
    aligned = align_ffhq(image_np)
    if aligned is not None:
        return aligned
    # 폴백: 기존 insightface crop
    faces = face_app.get(image_np)
    if not faces:
        raise ValueError("얼굴을 찾을 수 없습니다.")
    face = max(faces, key=lambda f: (f.bbox[2]-f.bbox[0]) * (f.bbox[3]-f.bbox[1]))
    x1, y1, x2, y2 = [int(v) for v in face.bbox]
    w, h = x2-x1, y2-y1
    pad = int(max(w, h) * 0.4)
    x1 = max(0, x1-pad); y1 = max(0, y1-pad)
    x2 = min(image_np.shape[1], x2+pad); y2 = min(image_np.shape[0], y2+pad)
    cropped = cv2.resize(image_np[y1:y2, x1:x2], (256, 256))
    return Image.fromarray(cv2.cvtColor(cropped, cv2.COLOR_BGR2RGB))


# ===================== SAM 인코딩/디코딩 =====================
def get_w_codes(model, img_pil, target_age):
    """이미지 PIL → W 코드 (RA-GAN 포함)"""
    tensor = img_transform(img_pil).unsqueeze(0).cuda()
    age_transformer = AgeTransformer(target_age=target_age)
    with torch.no_grad():
        input_with_age = age_transformer(tensor.squeeze().cpu()).unsqueeze(0).cuda()
        codes = model.encoder(input_with_age)
        if model.opts.start_from_encoded_w_plus:
            encoded_latents = model.pretrained_encoder(input_with_age[:, :-1, :, :])
            encoded_latents = encoded_latents + model.latent_avg
            codes = codes + encoded_latents
        elif model.opts.start_from_latent_avg:
            codes = codes + model.latent_avg
        race_codes = model.race_net(input_with_age)
        codes = model.race_mixers(codes, race_codes)
    return codes


def get_pivot_code(model, img_pil, age):
    """PTI용 pivot latent (원본 나이 기준, RA-GAN 미적용)"""
    tensor = img_transform(img_pil).unsqueeze(0).cuda()
    age_transformer = AgeTransformer(target_age=age)
    with torch.no_grad():
        input_with_age = age_transformer(tensor.squeeze().cpu()).unsqueeze(0).cuda()
        codes = model.encoder(input_with_age)
        if model.opts.start_from_encoded_w_plus:
            encoded_latents = model.pretrained_encoder(input_with_age[:, :-1, :, :])
            encoded_latents = encoded_latents + model.latent_avg
            codes = codes + encoded_latents
        elif model.opts.start_from_latent_avg:
            codes = codes + model.latent_avg
    return codes.detach()


def decode_raw(model, codes):
    imgs, _ = model.decoder([codes], input_is_latent=True,
                            randomize_noise=False, return_latents=True)
    return imgs


def decode_w_codes(model, codes):
    """W 코드 → 256 이미지 텐서 (no_grad)"""
    with torch.no_grad():
        images = decode_raw(model, codes)
        images = model.face_pool(images)
        if images.shape[-1] != 256:
            images = F.interpolate(images, size=(256, 256), mode='bilinear', align_corners=False)
    return images


def run_pti(model, aligned_face, source_age, native_size):
    """decoder를 이 얼굴에 미세조정 (정체성 lock). 호출 전 decoder 백업 복구 필수."""
    pivot = get_pivot_code(model, aligned_face, source_age)
    target_256 = img_transform(aligned_face).unsqueeze(0).cuda()
    target_native = F.interpolate(target_256, size=(native_size, native_size),
                                  mode='bilinear', align_corners=False)
    model.decoder.train()
    for p in model.decoder.parameters():
        p.requires_grad = True
    optimizer = torch.optim.Adam(model.decoder.parameters(), lr=PTI_LR)
    for step in range(PTI_STEPS):
        optimizer.zero_grad()
        gen = decode_raw(model, pivot)
        gen_256 = F.interpolate(gen, size=(256, 256), mode='bilinear', align_corners=False)
        loss = l2_loss(gen, target_native) + lpips_fn(gen_256, target_256).mean()
        loss.backward()
        optimizer.step()
    model.decoder.eval()
    for p in model.decoder.parameters():
        p.requires_grad = False


def apply_codeformer(result_pil):
    try:
        tmp_in = os.path.join(tempfile.gettempdir(), f"cf_in_{uuid.uuid4().hex}.png")
        result_pil.save(tmp_in)
        output = inference_app(
            image=tmp_in, background_enhance=False, face_upsample=True,
            upscale=2, codeformer_fidelity=CODEFORMER_FIDELITY
        )
        try:
            os.remove(tmp_in)
        except Exception:
            pass
        if isinstance(output, np.ndarray):
            return Image.fromarray(output)
        elif isinstance(output, Image.Image):
            return output
        elif isinstance(output, str) and os.path.exists(output):
            return Image.open(output).convert("RGB")
    except Exception as e:
        print(f"CodeFormer 후처리 실패 (원본 사용): {e}")
    return result_pil


def get_arcface_embedding(img_pil):
    try:
        img_np = cv2.cvtColor(np.array(img_pil), cv2.COLOR_RGB2BGR)
        faces = face_app.get(img_np)
        if not faces:
            return None
        face = max(faces, key=lambda f: (f.bbox[2]-f.bbox[0]) * (f.bbox[3]-f.bbox[1]))
        return face.normed_embedding
    except Exception:
        return None


def calc_similarity(emb1, emb2):
    if emb1 is None or emb2 is None:
        return None
    return round(float(np.dot(emb1, emb2)), 4)


def try_get_parent_face(image_bytes):
    if image_bytes is None:
        return None
    try:
        nparr = np.frombuffer(image_bytes, np.uint8)
        img_np = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if img_np is None:
            return None
        return crop_and_align_face(img_np)
    except Exception as e:
        print(f"부모 얼굴 검출 실패 (무시): {e}")
        return None


@app.on_event("startup")
async def startup_event():
    load_models()


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "korean_model": sam_model_korean is not None,
        "western_model": sam_model_western is not None,
        "ragan_weights": os.path.exists(RAGAN_WEIGHTS_PATH),
        "postprocess": "CodeFormer",
        "codeformer_fidelity": CODEFORMER_FIDELITY,
        "pti_enabled": ENABLE_PTI,
        "pti_steps": PTI_STEPS,
        "ffhq_scale": FFHQ_SCALE,
        "age_calibration": ENABLE_AGE_CALIBRATION,
        "age_ceiling": AGE_CEILING,
    }


@app.post("/api/aging")
async def aging(
    image: UploadFile = File(...),
    source_age: int = Form(...),
    target_age: int = Form(...),
    gender: str = Form(...),
    ethnicity: str = Form(default="korean"),
    father_image: Optional[UploadFile] = File(default=None),
    father_age: Optional[int] = Form(default=None),
    mother_image: Optional[UploadFile] = File(default=None),
    mother_age: Optional[int] = Form(default=None),
    alpha: float = Form(default=0.3),
    use_pti: bool = Form(default=True),
):
    if not (0 <= source_age <= 100) or not (0 <= target_age <= 100):
        raise HTTPException(status_code=400, detail="나이는 0~100 사이여야 합니다.")
    if gender not in ["M", "F"]:
        raise HTTPException(status_code=400, detail="gender는 M 또는 F여야 합니다.")
    if ethnicity not in ["korean", "western"]:
        raise HTTPException(status_code=400, detail="ethnicity는 korean 또는 western이어야 합니다.")
    if not (0.0 <= alpha <= 0.5):
        raise HTTPException(status_code=400, detail="alpha는 0.0~0.5 사이여야 합니다.")

    sam_model = sam_model_korean if ethnicity == "korean" else sam_model_western
    do_pti = ENABLE_PTI and use_pti

    try:
        _t = {}
        _s = time.time()
        contents = await image.read()
        nparr = np.frombuffer(contents, np.uint8)
        img_np = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if img_np is None:
            raise HTTPException(status_code=400, detail="이미지를 읽을 수 없습니다.")
        aligned_face = crop_and_align_face(img_np)
        _t['정렬'] = time.time() - _s; _s = time.time()

        father_bytes = await father_image.read() if father_image else None
        mother_bytes = await mother_image.read() if mother_image else None
        father_face = try_get_parent_face(father_bytes)
        mother_face = try_get_parent_face(mother_bytes)

        use_father = father_face is not None and father_age is not None
        use_mother = mother_face is not None and mother_age is not None
        use_blending = use_father or use_mother

        # ===== 나이 보정 =====
        calibrated_target, age_warning = calibrate_target_age(target_age)
        print(f"나이 보정: 요청 {target_age}세 → SAM target {calibrated_target}"
              f"{' [40세+ 정확도 낮음]' if age_warning else ''}")
        _s = time.time()

        # ===== PTI: decoder를 이 얼굴에 미세조정 =====
        if do_pti:
            sam_model.decoder.load_state_dict(get_decoder_backup(ethnicity))
            with torch.no_grad():
                native_size = decode_raw(sam_model, get_pivot_code(sam_model, aligned_face, source_age)).shape[-1]
            run_pti(sam_model, aligned_face, source_age, native_size)
            print(f"PTI 완료 (steps={PTI_STEPS})")
        _t['PTI'] = time.time() - _s; _s = time.time()

        # ===== 나이 변환 (튜닝된 decoder로, 보정된 target 사용) =====
        child_w = get_w_codes(sam_model, aligned_face, calibrated_target)

        if use_blending:
            if use_father and use_mother:
                father_w = get_w_codes(sam_model, father_face, father_age)
                mother_w = get_w_codes(sam_model, mother_face, mother_age)
                alpha_each = alpha / 2
                blended_w = child_w * (1 - alpha) + father_w * alpha_each + mother_w * alpha_each
                print(f"멀티 부모 블렌딩: alpha={alpha}")
            elif use_father:
                father_w = get_w_codes(sam_model, father_face, father_age)
                blended_w = child_w * (1 - alpha) + father_w * alpha
                print(f"단일 부모 블렌딩 (아버지): alpha={alpha}")
            else:
                mother_w = get_w_codes(sam_model, mother_face, mother_age)
                blended_w = child_w * (1 - alpha) + mother_w * alpha
                print(f"단일 부모 블렌딩 (어머니): alpha={alpha}")
            result = decode_w_codes(sam_model, blended_w)
        else:
            result = decode_w_codes(sam_model, child_w)
            print(f"기본 나이 변환 (FFHQ정렬 + {'PTI + ' if do_pti else ''}RA-GAN v2)")

        result_pil = tensor2im(result[0])
        if not isinstance(result_pil, Image.Image):
            result_pil = Image.fromarray(result_pil)
        _t['나이변환'] = time.time() - _s; _s = time.time()

        # CodeFormer 후처리
        result_pil = apply_codeformer(result_pil)
        _t['CodeFormer'] = time.time() - _s; _s = time.time()

        # PTI 후 반드시 decoder 복구 (다음 요청 위해)
        if do_pti:
            sam_model.decoder.load_state_dict(get_decoder_backup(ethnicity))
        _t['decoder복구'] = time.time() - _s; _s = time.time()

        # 점수 계산
        orig_pil = Image.fromarray(cv2.cvtColor(img_np, cv2.COLOR_BGR2RGB))
        orig_emb = get_arcface_embedding(orig_pil)
        result_emb = get_arcface_embedding(result_pil)
        identity_score = calc_similarity(orig_emb, result_emb)

        parent_score = None
        if use_blending:
            if use_father:
                fp = Image.fromarray(cv2.cvtColor(
                    cv2.imdecode(np.frombuffer(father_bytes, np.uint8), cv2.IMREAD_COLOR),
                    cv2.COLOR_BGR2RGB))
                parent_score = calc_similarity(get_arcface_embedding(fp), result_emb)
            elif use_mother:
                mp = Image.fromarray(cv2.cvtColor(
                    cv2.imdecode(np.frombuffer(mother_bytes, np.uint8), cv2.IMREAD_COLOR),
                    cv2.COLOR_BGR2RGB))
                parent_score = calc_similarity(get_arcface_embedding(mp), result_emb)

        tmp_path = os.path.join(tempfile.gettempdir(), f"dasibom_{uuid.uuid4().hex}.jpg")
        result_pil.save(tmp_path, "JPEG", quality=95)
        _t['점수+저장'] = time.time() - _s

        # 단계별 시간 로그
        total = sum(_t.values())
        print("===== 단계별 소요시간 =====")
        for k, v in _t.items():
            print(f"  {k:12s}: {v:6.2f}s")
        print(f"  {'합계':12s}: {total:6.2f}s")
        print("=" * 28)

        headers = {
            "X-Source-Age": str(source_age),
            "X-Target-Age": str(target_age),               # 사용자가 요청한 나이
            "X-Calibrated-Target": str(calibrated_target),  # SAM에 실제 넣은 보정값
            "X-Age-Warning": "true" if age_warning else "false",  # 40세+ 정확도 경고
            "X-Ethnicity": ethnicity,
            "X-Blending": "true" if use_blending else "false",
            "X-Alpha": str(alpha),
            "X-Identity-Score": str(identity_score) if identity_score is not None else "null",
            "X-Parent-Score": str(parent_score) if parent_score is not None else "null",
            "X-Postprocess": "CodeFormer",
            "X-PTI": "true" if do_pti else "false",
            "X-FFHQ-Scale": str(FFHQ_SCALE),
        }

        return FileResponse(tmp_path, media_type="image/jpeg", headers=headers)

    except ValueError as e:
        # PTI 중 에러 나도 decoder 복구
        if do_pti:
            try:
                sam_model.decoder.load_state_dict(get_decoder_backup(ethnicity))
            except Exception:
                pass
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        if do_pti:
            try:
                sam_model.decoder.load_state_dict(get_decoder_backup(ethnicity))
            except Exception:
                pass
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"처리 중 오류: {str(e)}")
