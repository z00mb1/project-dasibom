r"""
eye_color_fix.py — 홍채 색 교정 후처리 (B-1: 색조/채도 이전, 명암 유지)

문제:
  SAM decoder(StyleGAN FFHQ 편향) 때문에 한국인 홍채(갈색)가
  결과에서 밝은 회녹색으로 바뀐다. CodeFormer fidelity로는 안 잡힘(확인 완료).

해결:
  홍채 색은 나이가 들어도 변하지 않는 속성이므로,
  원본(정렬본)의 홍채 평균 색조(H)·채도(S)를 결과 홍채 영역에 이전한다.
  명암(V)은 결과 것을 유지해 입체감·반사광을 보존한다.
  → 없는 정보를 만드는 게 아니라, 생성기가 왜곡한 '변하지 않는 사실'을 되돌리는 교정.

방식:
  - dlib 68 랜드마크로 양쪽 눈(36-41, 42-47) 영역 검출
  - 각 눈에서 홍채 후보 픽셀만 추림(동공·속눈썹=어두움, 흰자·반사광=밝음 제외)
  - 원본 홍채 픽셀의 median H, median S 계산
  - 결과 홍채 영역의 H를 원본 H로, S를 (결과S와 원본S를 blend)로 치환, V는 유지
  - 홍채 원형 마스크에 가우시안 블러 → 경계 자연스럽게

사용:
  ai_server 폴더(main.py 옆)에 두고
  python eye_color_fix.py
  → C:\Users\ekzmd\eye_diag\fix\ 에 before/after 저장

통합:
  결과가 좋으면 main.py 에서 apply_codeformer 뒤에
      result_pil = correct_iris_color(aligned_face, result_pil)
  한 줄 추가하면 됨. (aligned_face = 정렬된 원본 PIL)
"""

import os
import numpy as np
import cv2
from PIL import Image
import main as M

# ================== CONFIG ==================
ALIGNED_SRC = r"C:\Users\ekzmd\eye_diag\00_aligned.png"          # 정렬된 원본(갈색 눈)
RESULT_IMG  = r"C:\Users\ekzmd\eye_diag\fidelity\fidelity_0.7.png"  # 교정할 결과(회녹색 눈)
OUT_DIR     = r"C:\Users\ekzmd\eye_diag\fix"

# 홍채로 간주할 밝기 백분위 구간 (이 범위 픽셀만 홍채로 취급)
LUM_LO, LUM_HI = 25, 80

# 한 번에 뽑을 강도 조합: (라벨, S_BLEND, V_BLEND)
#   S_BLEND: 채도를 원본 쪽으로 당기는 정도 (0=결과유지, 1=원본채도로)
#   V_BLEND: 밝기를 원본 홍채 쪽으로 당기는 정도 (0=결과유지, 1=원본밝기로) → 클수록 눈이 진해짐
COMBOS = [
    ("s07_v00", 0.7, 0.0),   # 현재(채도만 0.7, 밝기 유지) = 기준
    ("s10_v00", 1.0, 0.0),   # 채도 완전 원본, 밝기 유지
    ("s10_v03", 1.0, 0.3),   # 채도 완전 + 밝기 살짝 당김
    ("s10_v05", 1.0, 0.5),   # 채도 완전 + 밝기 절반
    ("s10_v07", 1.0, 0.7),   # 채도 완전 + 밝기 강하게 → 가장 진함
]
# ===========================================


def _eye_regions(bgr):
    """dlib 68 랜드마크로 양쪽 눈 폴리곤 반환. 실패 시 None."""
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    rects = M.face_detector(gray, 1)
    if len(rects) == 0:
        return None
    rect = max(rects, key=lambda r: r.width() * r.height())
    shape = M.landmark_predictor(gray, rect)
    pts = np.array([[shape.part(i).x, shape.part(i).y] for i in range(68)])
    return [pts[list(range(36, 42))], pts[list(range(42, 48))]]


def _iris_mask_and_pixels(bgr, eye_poly):
    """
    눈 폴리곤 영역에서 홍채 후보 픽셀 마스크를 만든다.
    반환: (홍채 bool 마스크 (전체이미지 크기), 홍채 픽셀들의 HSV array)
    """
    h, w = bgr.shape[:2]
    eye_mask = np.zeros((h, w), np.uint8)
    cv2.fillConvexPoly(eye_mask, eye_poly.astype(np.int32), 255)
    # 눈 영역 살짝 수축(눈꺼풀 경계 제외)
    eye_mask = cv2.erode(eye_mask, np.ones((3, 3), np.uint8), iterations=1)

    ys, xs = np.where(eye_mask > 0)
    if len(xs) == 0:
        return None, None
    px = bgr[ys, xs].astype(np.float32)
    lum = px.mean(axis=1)
    lo, hi = np.percentile(lum, LUM_LO), np.percentile(lum, LUM_HI)
    keep = (lum >= lo) & (lum <= hi)
    if keep.sum() < 5:
        keep = np.ones(len(lum), bool)

    iris_mask = np.zeros((h, w), np.uint8)
    iris_mask[ys[keep], xs[keep]] = 255

    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    iris_hsv = hsv[ys[keep], xs[keep]].astype(np.float32)
    return iris_mask, iris_hsv


def correct_iris_color(src_pil, result_pil, s_blend=1.0, v_blend=0.0):
    """
    원본(src)의 홍채 색조/채도(/밝기)를 결과(result)의 홍채에 이전.
    src_pil     : 정렬된 원본 PIL (갈색 눈)
    result_pil  : 나이변환 결과 PIL (회녹색 눈)
    s_blend     : 채도를 원본 쪽으로 당기는 정도 (0~1)
    v_blend     : 밝기를 원본 홍채 쪽으로 당기는 정도 (0~1, 클수록 눈 진해짐)
    반환        : 교정된 PIL
    """
    src_bgr = cv2.cvtColor(np.array(src_pil.convert("RGB")), cv2.COLOR_RGB2BGR)
    res_bgr = cv2.cvtColor(np.array(result_pil.convert("RGB")), cv2.COLOR_RGB2BGR)

    src_eyes = _eye_regions(src_bgr)
    res_eyes = _eye_regions(res_bgr)
    if src_eyes is None or res_eyes is None:
        print("  [교정 스킵] 원본 또는 결과에서 눈 검출 실패")
        return result_pil

    # 원본 양쪽 눈에서 홍채 픽셀 모아 대표 색조/채도(median) 계산
    src_iris_all = []
    for poly in src_eyes:
        _, iris_hsv = _iris_mask_and_pixels(src_bgr, poly)
        if iris_hsv is not None:
            src_iris_all.append(iris_hsv)
    if not src_iris_all:
        print("  [교정 스킵] 원본 홍채 픽셀 없음")
        return result_pil
    src_iris_all = np.concatenate(src_iris_all, axis=0)
    src_H = float(np.median(src_iris_all[:, 0]))
    src_S = float(np.median(src_iris_all[:, 1]))
    src_V = float(np.median(src_iris_all[:, 2]))
    print(f"  원본 홍채 대표색 H={src_H:.1f} S={src_S:.1f} V={src_V:.1f}")

    res_hsv = cv2.cvtColor(res_bgr, cv2.COLOR_BGR2HSV).astype(np.float32)

    # 결과 양쪽 눈 홍채 마스크 합치기
    full_iris = np.zeros(res_bgr.shape[:2], np.uint8)
    for poly in res_eyes:
        m, _ = _iris_mask_and_pixels(res_bgr, poly)
        if m is not None:
            full_iris = cv2.bitwise_or(full_iris, m)

    if full_iris.max() == 0:
        print("  [교정 스킵] 결과 홍채 마스크 비어있음")
        return result_pil

    # 마스크 부드럽게 (경계 자연스럽게)
    soft = cv2.GaussianBlur(full_iris, (7, 7), 0).astype(np.float32) / 255.0
    soft3 = soft[..., None]

    # 교정 HSV 만들기: H는 원본으로 치환, S·V는 blend
    corrected = res_hsv.copy()
    corrected[..., 0] = src_H
    corrected[..., 1] = res_hsv[..., 1] * (1 - s_blend) + src_S * s_blend
    corrected[..., 2] = res_hsv[..., 2] * (1 - v_blend) + src_V * v_blend

    # 마스크 영역만 교정 적용
    out_hsv = res_hsv * (1 - soft3) + corrected * soft3
    out_hsv = np.clip(out_hsv, 0, 255).astype(np.uint8)
    out_bgr = cv2.cvtColor(out_hsv, cv2.COLOR_HSV2BGR)

    out_rgb = cv2.cvtColor(out_bgr, cv2.COLOR_BGR2RGB)
    return Image.fromarray(out_rgb)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("모델(랜드마크) 로딩...")
    M.load_models()

    src = Image.open(ALIGNED_SRC).convert("RGB")
    res = Image.open(RESULT_IMG).convert("RGB")

    # 비교용: 원본 + 교정전
    src.save(os.path.join(OUT_DIR, "00_src_aligned.png"))
    res.save(os.path.join(OUT_DIR, "01_before.png"))

    for label, s_blend, v_blend in COMBOS:
        print(f"\n[{label}] S_BLEND={s_blend} V_BLEND={v_blend}")
        fixed = correct_iris_color(src, res, s_blend=s_blend, v_blend=v_blend)
        fixed.save(os.path.join(OUT_DIR, f"fix_{label}.png"))

    print(f"\n완료. {OUT_DIR}")
    print("  00_src_aligned(원본) / 01_before(교정전) / fix_*.png(강도별) 비교")
    print("  s=채도당김, v=밝기당김. 뒤 숫자 클수록 진함. 자연스러운 거 하나 골라줘.")


if __name__ == "__main__":
    main()
