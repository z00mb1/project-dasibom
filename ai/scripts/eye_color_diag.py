"""
eye_color_diag.py — 눈(홍채) 색 변화 원인 격리 진단

목적:
  15세 남성 정면 입력이 25(→보정 target 30)로 변환될 때
  홍채가 갈색 → 회녹색으로 밝아지는 현상이 어느 단계에서 들어오는지 규명한다.

방법:
  파이프라인 단계(RA-GAN 버전 / PTI / CodeFormer)를 조합별로 켜고 끄면서
  동일 입력으로 결과를 생성하고, dlib 68 랜드마크로 양쪽 눈 영역을 잘라
  평균 색(BGR·HSV)을 측정한다.
  원본 눈색과의 거리가 클수록 그 조합이 색을 바꾼 것.

사용:
  1) 아래 CONFIG의 INPUT_IMAGE, SOURCE_AGE, DESIRED_AGE 를 수정
  2) main.py 와 같은 conda 환경(dasibom_api)에서 실행
     python eye_color_diag.py
  3) 콘솔 표 + outputs/eye_diag/ 에 각 조합 결과 PNG + 눈 크롭 저장

주의:
  - main.py 의 함수/전역을 그대로 import 해서 쓴다. main.py 와 같은 폴더에 두고 실행.
  - RA-GAN v2 경로가 다르면 RAGAN_V2_PATH 를 고쳐라.
"""

import os
import copy
import csv
import numpy as np
import cv2
import torch
import torch.nn.functional as F
from PIL import Image

# ================== CONFIG ==================
INPUT_IMAGE = r"C:\Users\ekzmd\F0007_IND_S_15_0_01.JPG"  # 원본 15세
SOURCE_AGE = 15
DESIRED_AGE = 25            # 사용자가 요청하는 나이 (calibrate_target_age가 +5 → 30)

RAGAN_V4_PATH = r"C:\Users\ekzmd\ragan_final_v4.pt"
RAGAN_V2_PATH = r"C:\Users\ekzmd\ragan_final_v2.pt"

OUT_DIR = r"C:\Users\ekzmd\eye_diag"    # 결과 저장 폴더 (없으면 생성)
# 어떤 조합을 돌릴지. (라벨, ragan_path, do_pti, do_codeformer)
#   ragan_path=None  → race_mixers 미로드 (RA-GAN 없음)
COMBOS = [
    ("v4_PTI_CF",   RAGAN_V4_PATH, True,  True),   # 현재 서버 세팅 (문제 재현)
    ("v4_PTI_noCF", RAGAN_V4_PATH, True,  False),  # CodeFormer 격리
    ("v4_noPTI_CF", RAGAN_V4_PATH, False, True),   # PTI 격리
    ("v2_PTI_CF",   RAGAN_V2_PATH, True,  True),   # RA-GAN 버전 격리
    ("v2_PTI_noCF", RAGAN_V2_PATH, True,  False),
    ("noRAGAN_PTI_noCF", None,     True,  False),  # RA-GAN 완전 제거 (순수 SAM+PTI)
]
# ===========================================

# main.py 를 모듈로 불러와 그 함수/전역을 재사용
import main as M


def measure_eye_color(pil_img):
    """dlib 68 랜드마크로 양쪽 눈 영역 평균색 측정. 반환: (BGR tuple, HSV tuple) 또는 None"""
    bgr = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    rects = M.face_detector(gray, 1)
    if len(rects) == 0:
        return None
    rect = max(rects, key=lambda r: r.width() * r.height())
    shape = M.landmark_predictor(gray, rect)
    pts = np.array([[shape.part(i).x, shape.part(i).y] for i in range(68)])
    # 68 랜드마크 기준 눈: 좌 36-41, 우 42-47
    samples = []
    for idxs in [range(36, 42), range(42, 48)]:
        eye = pts[list(idxs)]
        x, y, w, h = cv2.boundingRect(eye.astype(np.int32))
        if w < 3 or h < 3:
            continue
        # 홍채는 눈 영역 중앙에 몰려 있으니 세로를 살짝 좁혀 눈꺼풀/흰자 영향을 줄임
        cy0 = y + int(h * 0.15)
        cy1 = y + int(h * 0.85)
        patch = bgr[cy0:cy1, x:x+w]
        if patch.size == 0:
            continue
        # 어두운 화소(동공·속눈썹)와 아주 밝은 화소(반사광)를 잘라 홍채만 남김
        flat = patch.reshape(-1, 3).astype(np.float32)
        lum = flat.mean(axis=1)
        keep = (lum > np.percentile(lum, 20)) & (lum < np.percentile(lum, 80))
        if keep.sum() > 0:
            samples.append(flat[keep])
    if not samples:
        return None
    allpx = np.concatenate(samples, axis=0)
    mean_bgr = allpx.mean(axis=0)
    hsv = cv2.cvtColor(mean_bgr.reshape(1, 1, 3).astype(np.uint8), cv2.COLOR_BGR2HSV)[0, 0]
    return tuple(round(float(v), 1) for v in mean_bgr), tuple(int(v) for v in hsv)


def run_once(sam_model, aligned_face, ethnicity, target_age, source_age,
             do_pti, do_codeformer):
    """main.py 의 단계들을 조합해 결과 PIL 반환"""
    # 항상 decoder 백업 복구부터 (이전 PTI 잔재 제거)
    sam_model.decoder.load_state_dict(M.get_decoder_backup(ethnicity))

    if do_pti:
        native = sam_model.decoder.size if hasattr(sam_model.decoder, "size") else 1024
        M.run_pti(sam_model, aligned_face, source_age, native)

    child_w = M.get_w_codes(sam_model, aligned_face, target_age)
    result = M.decode_w_codes(sam_model, child_w)
    result_pil = M.tensor2im(result[0])
    if not isinstance(result_pil, Image.Image):
        result_pil = Image.fromarray(result_pil)

    if do_codeformer:
        result_pil = M.apply_codeformer(result_pil)

    if do_pti:
        sam_model.decoder.load_state_dict(M.get_decoder_backup(ethnicity))
    return result_pil


def load_sam_with_ragan(ragan_path):
    """지정한 RA-GAN 경로로 korean SAM 새로 로드 (백업도 이 인스턴스에 맞춰 생성)"""
    model = M.load_single_sam(M.SAM_KOREAN_PATH, ragan_path=ragan_path)
    backup = copy.deepcopy(model.decoder.state_dict())
    return model, backup


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    # main.py 의 모델/랜드마크/얼굴검출기 초기화
    print("모델 로딩 중... (main.load_models)")
    M.load_models()

    # 원본 로드 (한글 경로 안전하게 imdecode)
    raw = cv2.imdecode(np.fromfile(INPUT_IMAGE, dtype=np.uint8), cv2.IMREAD_COLOR)
    if raw is None:
        raise FileNotFoundError(f"입력 이미지를 못 읽음: {INPUT_IMAGE}")

    aligned_face = M.crop_and_align_face(raw)   # FFHQ 정렬된 PIL
    aligned_face.save(os.path.join(OUT_DIR, "00_aligned.png"))

    # 보정 target 계산 (main.py 규칙 그대로)
    calibrated_target, warning = M.calibrate_target_age(DESIRED_AGE)
    print(f"요청 {DESIRED_AGE} → 보정 target {calibrated_target} (warning={warning})")

    # 원본(정렬본) 눈색 = 기준선
    base = measure_eye_color(aligned_face)
    if base is None:
        print("경고: 원본 정렬본에서 눈 검출 실패. 정면/조명 확인 필요.")
        base_bgr, base_hsv = (None, None)
    else:
        base_bgr, base_hsv = base
        print(f"[원본 눈색] BGR={base_bgr}  HSV={base_hsv}")

    rows = []
    # RA-GAN 경로별로 모델을 한 번만 로드해 조합을 돌린다
    by_ragan = {}
    for label, ragan_path, do_pti, do_cf in COMBOS:
        key = str(ragan_path)
        if key not in by_ragan:
            if ragan_path is not None and not os.path.exists(ragan_path):
                print(f"  (건너뜀) RA-GAN 경로 없음: {ragan_path}")
                by_ragan[key] = None
            else:
                print(f"SAM 로드 (RA-GAN={os.path.basename(str(ragan_path)) if ragan_path else 'none'})")
                by_ragan[key] = load_sam_with_ragan(ragan_path)
        loaded = by_ragan[key]
        if loaded is None:
            continue
        model, backup = loaded
        # 이 인스턴스의 백업을 main 전역에 맞춰줌 (run_once 가 get_decoder_backup 사용)
        M._decoder_backup_korean = backup

        print(f"→ 조합 실행: {label}")
        result_pil = run_once(model, aligned_face, "korean",
                              calibrated_target, SOURCE_AGE, do_pti, do_cf)
        result_pil.save(os.path.join(OUT_DIR, f"{label}.png"))

        meas = measure_eye_color(result_pil)
        if meas is None:
            print(f"   눈 검출 실패: {label}")
            rows.append([label, "detect_fail", "", "", ""])
            continue
        bgr, hsv = meas
        # 원본과의 색 거리 (BGR 유클리드, HSV의 V=밝기 차)
        if base_bgr is not None:
            dist = round(float(np.linalg.norm(np.array(bgr) - np.array(base_bgr))), 1)
            dv = hsv[2] - base_hsv[2]   # 밝기 증가량 (+면 밝아짐)
        else:
            dist, dv = "", ""
        rows.append([label, bgr, hsv, dist, dv])
        print(f"   눈색 BGR={bgr} HSV={hsv} | 원본거리={dist} 밝기Δ={dv}")

    # 표 출력 + CSV 저장
    print("\n===== 요약 (원본거리 클수록 = 그 조합이 눈색을 바꿈) =====")
    hdr = ["조합", "눈BGR", "눈HSV", "원본색거리", "밝기Δ(V)"]
    print("{:<18} {:<22} {:<16} {:<10} {:<8}".format(*hdr))
    for r in rows:
        print("{:<18} {:<22} {:<16} {:<10} {:<8}".format(
            str(r[0]), str(r[1]), str(r[2]), str(r[3]), str(r[4])))

    csv_path = os.path.join(OUT_DIR, "eye_diag_summary.csv")
    with open(csv_path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["baseline_원본", base_bgr, base_hsv, 0, 0])
        w.writerow(hdr)
        w.writerows(rows)
    print(f"\n저장 완료: {OUT_DIR}\n  - 각 조합 PNG, 00_aligned.png, eye_diag_summary.csv")
    print("해석 가이드:")
    print("  · v4_PTI_CF 에서만 밝기Δ가 크면 → v4+CF 조합이 원인")
    print("  · noCF 로 바꿔 밝기Δ가 줄면 → CodeFormer 가 눈을 밝힘")
    print("  · v2 로 바꿔 밝기Δ가 줄면 → RA-GAN v4 race_mixers 가 원인")
    print("  · noRAGAN 에서도 밝으면 → SAM decoder(StyleGAN) 자체 편향")


if __name__ == "__main__":
    main()
