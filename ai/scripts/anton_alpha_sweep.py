r"""
anton_alpha_sweep.py — alpha(부모 반영 강도) 스윕

목적:
  앤톤 어릴때 → 22세 변환 시, 양친 blend의 alpha를 여러 값으로 훑어
  "한국인 느낌"이 어느 지점에서 살아나는지 육안 + GT유사도로 판단.
  (base 서양인화를 부모 특성으로 얼마나 되돌릴 수 있나)

설계:
  - target 정확히 22 (오프셋 무시)
  - 양친 blend 고정, alpha만 변화 (각 부모는 alpha/2씩)
  - PTI 1회만 수행, w코드 재사용 → alpha만 바꿔 빠르게 여러 장
  - 각 결과를 현재 앤톤(GT)과 ArcFace 유사도로 측정
  - 결과 이미지 로컬 저장(육안 확인), 콘솔엔 수치. 발표엔 수치/그래프만.

사용:
  ai_server 폴더에서:  python anton_alpha_sweep.py
"""

import os
import copy
import csv
import numpy as np
import cv2
from PIL import Image
import torch

import main as M

# ================== CONFIG ==================
CHILD_IMG  = r"C:\Users\ekzmd\anton\child.png"
GT_IMG     = r"C:\Users\ekzmd\anton\gt_adult.png"
FATHER_IMG = r"C:\Users\ekzmd\anton\father.png"
MOTHER_IMG = r"C:\Users\ekzmd\anton\mother.png"

SOURCE_AGE  = 10
TARGET_AGE  = 25
FATHER_AGE  = 51
MOTHER_AGE  = 50

ALPHAS = [0.0, 0.3, 0.4, 0.5, 0.6, 0.7]   # 0.0 = 부모없이(기준)

ETHNICITY   = "korean"
OUT_DIR     = r"C:\Users\ekzmd\anton\alpha_sweep"
# ===========================================


def load_aligned(path):
    raw = cv2.imdecode(np.fromfile(path, dtype=np.uint8), cv2.IMREAD_COLOR)
    if raw is None:
        raise FileNotFoundError(f"못 읽음: {path}")
    return M.crop_and_align_face(raw)


def decode_and_post(sam, w):
    result = M.decode_w_codes(sam, w)
    pil = M.tensor2im(result[0])
    if not isinstance(pil, Image.Image):
        pil = Image.fromarray(pil)
    return M.apply_codeformer(pil)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("모델 로딩...")
    M.load_models()

    child_face  = load_aligned(CHILD_IMG)
    father_face = load_aligned(FATHER_IMG)
    mother_face = load_aligned(MOTHER_IMG)

    gt_emb = M.get_arcface_embedding(Image.open(GT_IMG).convert("RGB"))
    if gt_emb is None:
        raise RuntimeError("GT 얼굴 임베딩 실패")

    sam = M.load_single_sam(M.SAM_KOREAN_PATH, ragan_path=M.RAGAN_WEIGHTS_PATH)
    M._decoder_backup_korean = copy.deepcopy(sam.decoder.state_dict())

    # PTI 1회
    sam.decoder.load_state_dict(M.get_decoder_backup(ETHNICITY))
    with torch.no_grad():
        native = M.decode_raw(sam, M.get_pivot_code(sam, child_face, SOURCE_AGE)).shape[-1]
    M.run_pti(sam, child_face, SOURCE_AGE, native)
    print(f"PTI 완료 (steps={M.PTI_STEPS})")

    # w코드 (target 22 고정)
    child_w  = M.get_w_codes(sam, child_face,  TARGET_AGE)
    father_w = M.get_w_codes(sam, father_face, FATHER_AGE)
    mother_w = M.get_w_codes(sam, mother_face, MOTHER_AGE)

    rows = []
    print("\n===== alpha 스윕 (양친 blend, GT유사도) =====")
    print(f"{'alpha':<8}{'GT유사도':<10}")
    print("-" * 20)
    for a in ALPHAS:
        if a == 0.0:
            w = child_w
        else:
            w = child_w * (1 - a) + father_w * (a/2) + mother_w * (a/2)
        pil = decode_and_post(sam, w)
        pil.save(os.path.join(OUT_DIR, f"alpha_{a:.1f}.png"))
        emb = M.get_arcface_embedding(pil)
        gt_sim = round(float(M.calc_similarity(emb, gt_emb)), 4) if emb is not None else None
        rows.append([a, gt_sim])
        print(f"{a:<8}{gt_sim if gt_sim is not None else '검출실패':<10}")

    sam.decoder.load_state_dict(M.get_decoder_backup(ETHNICITY))

    # 최고 GT유사도 alpha
    valid = [(a, s) for a, s in rows if s is not None]
    if valid:
        best = max(valid, key=lambda x: x[1])
        print(f"\nGT유사도 최고: alpha={best[0]} ({best[1]})")
    print("주의: 숫자 최고 != 육안 최고일 수 있음. alpha_*.png 직접 비교해서")
    print("      '한국인 느낌' 사는 지점을 눈으로도 골라라.")

    with open(os.path.join(OUT_DIR, "alpha_sweep.csv"), "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["alpha", "gt_similarity"])
        w.writerows(rows)
    print(f"\n저장: {OUT_DIR}")


if __name__ == "__main__":
    main()
