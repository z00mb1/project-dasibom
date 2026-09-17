r"""
anton_gt_verify.py — 부모 blend가 성인 예측 정확도를 높이는가? (GT 대조 검증)

시나리오:
  앤톤 어릴때(약11-12세) → 22세로 나이변환
  ② 부모없이 / ③a 아빠(윤상)만 / ③b 엄마(심혜진)만 / ③c 양친
  각 결과를 '현재 앤톤(GT, 약22세)'과 ArcFace 유사도로 비교.

핵심 판정:
  gt③ > gt②  → 부모 유전정보가 실제 성인 예측을 개선 (기능 입증)
  gt③b > gt③a → "엄마(심혜진) 닮았다"는 세평이 AI로도 확인

설계 노트:
  - 오프셋(+5) 무시: GT가 22세이므로 SAM target을 정확히 22로 고정 (calibrate 안 씀)
  - PTI는 자녀 사진에 1회만 수행하고 그 튜닝 decoder를 4개 조합에 재사용 (시간 절약)
  - main.py 함수/전역 그대로 import (파이프라인 서버와 동일)
  - 결과 이미지는 로컬에만 저장. 발표엔 gt 수치/그래프만 쓸 것(초상권).

사용:
  ai_server 폴더(main.py 옆)에 두고:  python anton_gt_verify.py
  경로/나이만 CONFIG에서 수정.
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
CHILD_IMG  = r"C:\Users\ekzmd\anton\child.png"      # 앤톤 어릴때 (입력)
GT_IMG     = r"C:\Users\ekzmd\anton\gt_adult.png"   # 현재 앤톤 (정답지 GT)
FATHER_IMG = r"C:\Users\ekzmd\anton\father.png"     # 윤상
MOTHER_IMG = r"C:\Users\ekzmd\anton\mother.png"     # 심혜진

SOURCE_AGE  = 12    # 자녀 사진의 대략 나이 (PTI 기준)
TARGET_AGE  = 22    # GT에 맞춘 목표 나이 (오프셋 무시, 정확히 22)
FATHER_AGE  = 57    # 윤상 사진의 대략 나이
MOTHER_AGE  = 50    # 심혜진 사진의 대략 나이
ALPHA       = 0.3   # blend 강도 (양친이면 0.15씩 분배됨)

ETHNICITY   = "korean"
OUT_DIR     = r"C:\Users\ekzmd\anton\out"
# ===========================================


def load_face(path):
    """한글경로 안전 로드 → FFHQ 정렬된 PIL 반환"""
    raw = cv2.imdecode(np.fromfile(path, dtype=np.uint8), cv2.IMREAD_COLOR)
    if raw is None:
        raise FileNotFoundError(f"못 읽음: {path}")
    return M.crop_and_align_face(raw), raw


def arcface_of_pil(pil):
    return M.get_arcface_embedding(pil)


def decode_and_post(sam_model, w):
    """w코드 → decode → PIL → CodeFormer 까지 (서버와 동일 순서)"""
    result = M.decode_w_codes(sam_model, w)
    pil = M.tensor2im(result[0])
    if not isinstance(pil, Image.Image):
        pil = Image.fromarray(pil)
    pil = M.apply_codeformer(pil)
    return pil


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("모델 로딩...")
    M.load_models()

    # ---- 입력/부모/GT 정렬 ----
    child_face, _ = load_face(CHILD_IMG)
    father_face, _ = load_face(FATHER_IMG)
    mother_face, _ = load_face(MOTHER_IMG)
    child_face.save(os.path.join(OUT_DIR, "aligned_child.png"))

    # GT는 나이변환 안 함. 그대로 ArcFace 임베딩만.
    gt_pil = Image.open(GT_IMG).convert("RGB")
    gt_emb = arcface_of_pil(gt_pil)
    if gt_emb is None:
        raise RuntimeError("GT에서 얼굴 임베딩 실패. GT 사진 정면/화질 확인.")

    # ---- korean SAM 로드 (서버와 동일 경로/RA-GAN) ----
    sam = M.load_single_sam(M.SAM_KOREAN_PATH, ragan_path=M.RAGAN_WEIGHTS_PATH)
    M._decoder_backup_korean = copy.deepcopy(sam.decoder.state_dict())

    # ---- 자녀에 PTI 1회 (서버와 동일 방식) ----
    sam.decoder.load_state_dict(M.get_decoder_backup(ETHNICITY))
    with torch.no_grad():
        native_size = M.decode_raw(
            sam, M.get_pivot_code(sam, child_face, SOURCE_AGE)
        ).shape[-1]
    M.run_pti(sam, child_face, SOURCE_AGE, native_size)
    print(f"PTI 완료 (steps={M.PTI_STEPS})")

    # ---- 튜닝된 decoder로 w코드들 계산 (target 정확히 22) ----
    child_w  = M.get_w_codes(sam, child_face,  TARGET_AGE)
    father_w = M.get_w_codes(sam, father_face, FATHER_AGE)
    mother_w = M.get_w_codes(sam, mother_face, MOTHER_AGE)

    a = ALPHA
    combos = {
        "2_noparent":   child_w,
        "3a_father":    child_w * (1 - a) + father_w * a,
        "3b_mother":    child_w * (1 - a) + mother_w * a,
        "3c_both":      child_w * (1 - a) + father_w * (a/2) + mother_w * (a/2),
    }

    rows = []
    print("\n===== GT 대조 결과 (현재 앤톤과의 ArcFace 유사도) =====")
    print(f"{'조합':<14}{'GT유사도':<10}")
    print("-" * 26)
    for label, w in combos.items():
        pil = decode_and_post(sam, w)
        pil.save(os.path.join(OUT_DIR, f"{label}.png"))
        emb = arcface_of_pil(pil)
        if emb is None:
            gt_sim = None
            print(f"{label:<14}검출실패")
        else:
            gt_sim = round(float(M.calc_similarity(emb, gt_emb)), 4)
            print(f"{label:<14}{gt_sim:<10}")
        rows.append([label, gt_sim])

    # decoder 원복
    sam.decoder.load_state_dict(M.get_decoder_backup(ETHNICITY))

    # ---- 해석 ----
    d = {r[0]: r[1] for r in rows}
    print("\n===== 해석 =====")
    if d.get("2_noparent") is not None:
        base = d["2_noparent"]
        for k in ["3a_father", "3b_mother", "3c_both"]:
            if d.get(k) is not None:
                diff = round(d[k] - base, 4)
                sign = "↑개선" if diff > 0 else ("↓하락" if diff < 0 else "동일")
                print(f"  {k}: {d[k]}  (부모없이 대비 {diff:+} {sign})")
    if d.get("3a_father") is not None and d.get("3b_mother") is not None:
        if d["3b_mother"] > d["3a_father"]:
            print("  → 엄마 blend가 더 높음: '엄마(심혜진) 닮음' 세평과 일치")
        elif d["3a_father"] > d["3b_mother"]:
            print("  → 아빠 blend가 더 높음")
        else:
            print("  → 부/모 동일")

    # CSV
    csv_path = os.path.join(OUT_DIR, "gt_verify_summary.csv")
    with open(csv_path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["combo", "gt_similarity"])
        w.writerows(rows)
    print(f"\n저장: {OUT_DIR}")
    print("  각 조합 png(로컬 확인용) + gt_verify_summary.csv")
    print("  ※ 발표에는 얼굴 말고 이 수치/그래프만 사용")


if __name__ == "__main__":
    main()
