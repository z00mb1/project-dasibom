# -*- coding: utf-8 -*-
"""
W Space Blending - 가족 유전 특성 반영 나이 변환
부모 사진 + 자녀 사진 → 부모 특성 반영된 나이 변환 결과
"""
import sys
import os
import json
import cv2
import dlib
import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image
from argparse import Namespace
import torchvision.transforms as transforms
from insightface.app import FaceAnalysis
from collections import defaultdict

sys.path.insert(0, r'C:\Users\ekzmd\Desktop\dasibom-project\plan_c\SAM')

from models.psp import pSp
from datasets.augmentations import AgeTransformer
from utils.common import tensor2im

# ===================== 경로 설정 =====================
SAM_MODEL_PATH = r'C:\Users\ekzmd\sam_korean_best_model.pt'
LANDMARK_PATH = r'C:\Users\ekzmd\Desktop\dasibom-project\plan_c\SAM\shape_predictor_68_face_landmarks.dat'
INDIVIDUALS_DIR = r'C:\Users\ekzmd\Desktop\dasibom-project\data\family_dataset\individuals'
FAMILY_JSON_DIR = r'C:\Users\ekzmd\Desktop\dasibom-project\data\family_dataset\family_json'
OUTPUT_DIR = r'C:\Users\ekzmd\Desktop\dasibom-project\data\family_dataset\blending_results'
RAGAN_WEIGHTS_PATH = r'C:\Users\ekzmd\ragan_final_v2.pt'

os.makedirs(OUTPUT_DIR, exist_ok=True)

# ===================== 모델 로딩 =====================
print("모델 로딩 중...")
face_app = FaceAnalysis(name='buffalo_l', providers=['CUDAExecutionProvider'])
face_app.prepare(ctx_id=0, det_size=(640, 640))
face_detector = dlib.get_frontal_face_detector()
landmark_predictor = dlib.shape_predictor(LANDMARK_PATH)

ckpt = torch.load(SAM_MODEL_PATH, map_location='cpu')
opts = ckpt['opts']
opts['checkpoint_path'] = SAM_MODEL_PATH
opts['device'] = 'cuda'
opts = Namespace(**opts)
model = pSp(opts)

# RA-GAN 가중치 로딩 (있으면)
if os.path.exists(RAGAN_WEIGHTS_PATH):
    ragan_ckpt = torch.load(RAGAN_WEIGHTS_PATH, map_location='cpu')
    model.race_mixers.load_state_dict(ragan_ckpt['race_mixers'], strict=True)
    print("RA-GAN 가중치 로딩 완료")

model.eval()
model.cuda()
print("모델 로딩 완료!")

# ===================== 전처리 함수 =====================
transform = transforms.Compose([
    transforms.Resize((256, 256)),
    transforms.ToTensor(),
    transforms.Normalize([0.5, 0.5, 0.5], [0.5, 0.5, 0.5])
])

def crop_and_align_face(image_np):
    faces = face_app.get(image_np)
    if not faces:
        return None
    face = max(faces, key=lambda f: (f.bbox[2]-f.bbox[0]) * (f.bbox[3]-f.bbox[1]))
    x1, y1, x2, y2 = [int(v) for v in face.bbox]
    w, h = x2-x1, y2-y1
    pad = int(max(w, h) * 0.4)
    x1 = max(0, x1-pad)
    y1 = max(0, y1-pad)
    x2 = min(image_np.shape[1], x2+pad)
    y2 = min(image_np.shape[0], y2+pad)
    cropped = image_np[y1:y2, x1:x2]
    cropped = cv2.resize(cropped, (256, 256))
    rgb = cv2.cvtColor(cropped, cv2.COLOR_BGR2RGB)
    dets = face_detector(rgb, 1)
    if not dets:
        return Image.fromarray(rgb)
    shape = landmark_predictor(rgb, dets[0])
    landmarks = np.array([[shape.part(i).x, shape.part(i).y] for i in range(68)])
    left_eye = landmarks[36:42].mean(axis=0)
    right_eye = landmarks[42:48].mean(axis=0)
    angle = np.degrees(np.arctan2(right_eye[1]-left_eye[1], right_eye[0]-left_eye[0]))
    center = tuple(map(int, ((left_eye+right_eye)/2)))
    M_rot = cv2.getRotationMatrix2D(center, angle, 1.0)
    aligned = cv2.warpAffine(rgb, M_rot, (256, 256))
    return Image.fromarray(aligned)

def img_to_tensor(img_path):
    img_np = cv2.imdecode(np.fromfile(img_path, dtype=np.uint8), cv2.IMREAD_COLOR)
    if img_np is None:
        return None
    aligned = crop_and_align_face(img_np)
    if aligned is None:
        return None
    return transform(aligned).unsqueeze(0).cuda()

def get_w_codes(tensor):
    """이미지 텐서 → W+ 공간 코드 추출"""
    with torch.no_grad():
        codes = model.encoder(tensor)
        if model.opts.start_from_encoded_w_plus:
            encoded_latents = model.pretrained_encoder(tensor[:, :-1, :, :])
            encoded_latents = encoded_latents + model.latent_avg
            codes = codes + encoded_latents
        elif model.opts.start_from_latent_avg:
            codes = codes + model.latent_avg
    return codes

def decode_w_codes(codes):
    """W+ 코드 → 이미지"""
    with torch.no_grad():
        images, _ = model.decoder(
            [codes],
            input_is_latent=True,
            randomize_noise=False,
            return_latents=True
        )
        images = model.face_pool(images)
    return images

# ===================== 가족 쌍 구성 =====================
def build_family_pairs():
    """JSON에서 부모-자녀 쌍 구성"""
    pairs = []
    family_members = defaultdict(list)

    # JSON 파싱
    for jf in os.listdir(FAMILY_JSON_DIR):
        if not jf.endswith('.json'):
            continue
        with open(os.path.join(FAMILY_JSON_DIR, jf), encoding='utf-8') as f:
            data = json.load(f)

        fid = data['family_id']
        for m in data['member']:
            pid = m['personal_id']
            age = int(m['age'])
            family_members[fid].append({'personal_id': pid, 'age': age})

    # 부모/자녀 구분 및 쌍 구성
    parent_ids = {'M', 'F', 'GF', 'GM'}  # 부모/조부모 ID
    child_ids = {'D', 'S'}               # 자녀 ID

    for fid, members in family_members.items():
        unique_members = {}
        for m in members:
            pid = m['personal_id']
            if pid not in unique_members:
                unique_members[pid] = m['age']

        parents = [(pid, age) for pid, age in unique_members.items() 
                   if pid in parent_ids and (
                       (pid in {'M', 'F'} and 25 <= age <= 65) or      # 부모
                       (pid in {'GM', 'GF'} and 55 <= age <= 85)        # 조부모
                   )]
        children = [(pid, age) for pid, age in unique_members.items() if pid in child_ids and age >= 10]

        for parent_pid, parent_age in parents:
            for child_pid, child_age in children:
                # 부모 사진 찾기 (첫 번째 정면)
                parent_img = find_image(fid, parent_pid, parent_age)
                child_img = find_image(fid, child_pid, child_age)

                if parent_img and child_img:
                    pairs.append({
                        'family_id': fid,
                        'parent_id': parent_pid,
                        'parent_age': parent_age,
                        'parent_img': parent_img,
                        'child_id': child_pid,
                        'child_age': child_age,
                        'child_img': child_img,
                    })

    print(f"총 {len(pairs)}쌍 구성 완료")
    return pairs

# ===================== 이미지 파일 캐시 =====================
# os.listdir 반복 호출 방지
_img_cache = None

def get_img_cache():
    global _img_cache
    if _img_cache is None:
        _img_cache = set(os.listdir(INDIVIDUALS_DIR))
    return _img_cache

def find_image(family_id, personal_id, age):
    """family_id + personal_id + age로 정면 이미지 찾기"""
    prefix = f"{family_id}_IND_{personal_id}_{age}_0_"
    cache = get_img_cache()
    for fname in cache:
        if fname.startswith(prefix):
            return os.path.join(INDIVIDUALS_DIR, fname)
    return None

# ===================== W Blending =====================
def blend_and_age(child_img_path, parent_img_path, target_age, parent_age, alpha=0.3, output_path=None):
    """
    W space blending으로 부모 특성 반영 나이 변환
    alpha: 부모 특성 반영 비율 (0.0~1.0, 기본 0.3)
    parent_age: 부모 현재 나이 (W 코드 추출 시 현재 나이로 인코딩)
    """
    # 이미지 → 텐서
    child_tensor = img_to_tensor(child_img_path)
    parent_tensor = img_to_tensor(parent_img_path)

    if child_tensor is None or parent_tensor is None:
        return None

    # 자녀: target_age 토큰 / 부모: 현재 나이 토큰
    child_with_age = AgeTransformer(target_age=target_age)(child_tensor.squeeze().cpu()).unsqueeze(0).cuda()
    parent_with_age = AgeTransformer(target_age=parent_age)(parent_tensor.squeeze().cpu()).unsqueeze(0).cuda()

    # W 코드 추출
    child_w = get_w_codes(child_with_age)
    parent_w = get_w_codes(parent_with_age)

    # W space blending
    blended_w = child_w * (1 - alpha) + parent_w * alpha

    # 이미지 생성
    output = decode_w_codes(blended_w)

    # 크기 조정
    if output.shape[-1] != 256:
        output = F.interpolate(output, size=(256, 256), mode='bilinear', align_corners=False)

    result_pil = tensor2im(output[0])
    if not isinstance(result_pil, Image.Image):
        result_pil = Image.fromarray(result_pil)

    if output_path:
        result_pil.save(output_path)

    return result_pil

# ===================== 테스트 실행 =====================
if __name__ == '__main__':
    print("\n가족 쌍 구성 중...")
    pairs = build_family_pairs()

    if not pairs:
        print("ERROR: 매칭된 쌍이 없습니다.")
        exit(1)

    # 알파 값 비교 테스트 (첫 5쌍)
    alphas = [0.0, 0.2, 0.3, 0.5]
    test_pairs = pairs[:5]

    print(f"\n{len(test_pairs)}쌍 테스트 시작...")

    for i, pair in enumerate(test_pairs):
        fid = pair['family_id']
        print(f"\n[{i+1}/{len(test_pairs)}] {fid} | 부모: {pair['parent_id']}({pair['parent_age']}세) | 자녀: {pair['child_id']}({pair['child_age']}세)")

        pair_dir = os.path.join(OUTPUT_DIR, f"{fid}_{pair['child_id']}")
        os.makedirs(pair_dir, exist_ok=True)

        # 원본 자녀 저장
        child_np = cv2.imdecode(np.fromfile(pair['child_img'], dtype=np.uint8), cv2.IMREAD_COLOR)
        if child_np is not None:
            aligned = crop_and_align_face(child_np)
            if aligned:
                aligned.save(os.path.join(pair_dir, 'child_original.jpg'))

        # 알파별 결과
        for alpha in alphas:
            out_path = os.path.join(pair_dir, f'alpha_{int(alpha*10):02d}_age{pair["child_age"]}to70.jpg')
            result = blend_and_age(
                pair['child_img'],
                pair['parent_img'],
                target_age=70,
                parent_age=pair['parent_age'],
                alpha=alpha,
                output_path=out_path
            )
            if result:
                print(f"  alpha={alpha} → {out_path}")

    print(f"\n완료! 결과: {OUTPUT_DIR}")