# 다시봄 — AI 나이 변환 파트

> AI 기반 실종자 알림 및 나이 변환 플랫폼 **다시봄**의 AI 몽타주 생성 모듈
> 중부대학교 인공지능전공 졸업작품

실종자의 과거 사진으로부터 **현재 예상 나이의 얼굴을 예측**하고, 정체성을 유지하면서 한국인 인종 특성을 보존하는 나이 변환 파이프라인입니다.

---

## 핵심 성과

| 지표 | 결과 |
|---|---|
| 정체성 보존 (ArcFace) | **0.58** (실제 동일인 나이차 유사도 0.45 상회 · SAM 원논문 기준) |
| 인종 정확도 (FairFace EastAsian) | **90.6% → 93.4%** (RA-GAN 적용) |
| 유효 나이 범위 | 14~40세 |
| 가족 유전 반영 | 조건부 적용 (base 붕괴 시 유효) |

정체성 보존율을 초기 파이프라인 대비 **0.09 → 0.58로 약 6배 향상**시켰습니다.

---

## 파이프라인 구조

```
입력 얼굴
  │
  ├─ [1] 얼굴 검출 · FFHQ 표준 정렬 (scale 2.4)
  │
  ├─ [2] PTI (Pivotal Tuning Inversion) — 얼굴별 decoder 미세조정, 정체성 고정
  │
  ├─ [3] SAM + RA-GAN — latent 나이 변환 + 인종 편향 보정
  │        └─ (선택) 부모 W-blending — 가족 유전 특성 반영
  │
  ├─ [4] CodeFormer — 화질 후처리
  │
  └─ [5] ArcFace — 정체성 유사도 검증
        │
      결과 이미지 + 유사도 점수
```

- **인코더**: pSp — 얼굴을 StyleGAN2 W+ latent로 인코딩
- **decoder**: 사전학습 StyleGAN2-FFHQ 기반 (한국인 파인튜닝 적용)
- **RA-GAN**: RACEpSp + Feature Mixer로 인코딩 단계에서 인종 특성 보정 (backbone frozen, 학습 파라미터 약 5.58M)

---

## 기술 스택

| 분류 | 사용 기술 |
|---|---|
| Framework | PyTorch 2.4.1 |
| 서버 | FastAPI + Uvicorn |
| 얼굴 처리 | OpenCV 4.12.0.88, dlib, MediaPipe, insightface (ArcFace) |
| 생성 모델 | StyleGAN2 기반 SAM, RA-GAN |
| 후처리 | CodeFormer, GFPGAN |
| 언어 | Python 3.12.5 |

---

## 설치 및 실행

> 아래는 `ai/` 디렉터리 기준입니다. (`cd ai`)

### 1. 환경 준비

```bash
conda create -n dasibom_api python=3.12.5
conda activate dasibom_api
pip install -r requirements.txt
```

### 2. 외부 소스 클론 (SAM)

파이프라인은 SAM 소스 모듈(`models.psp` 등)에 의존합니다. `ai/SAM/`에 클론하세요.

```bash
git clone https://github.com/yuval-alaluf/SAM.git ./SAM
```

> 다른 위치에 두려면 환경변수 `SAM_SRC`로 경로를 지정할 수 있습니다.

### 3. 모델 가중치 · 리소스 준비 (별도 다운로드)

> ⚠️ 모델 가중치(.pt)와 데이터셋은 용량·라이선스 문제로 저장소에 포함하지 않습니다.
> 아래 파일을 `ai/weights/`에 넣거나, 환경변수로 경로를 지정하세요.

| 파일 (weights/ 기본 파일명) | 설명 | 비고 |
|---|---|---|
| `sam_ffhq_aging.pt` | SAM 사전학습 가중치 | [SAM 공식 저장소](https://github.com/yuval-alaluf/SAM) |
| `sam_korean_best_model.pt` | 한국인 파인튜닝 모델 | 자체 학습 (AIHub 데이터) |
| `ragan_final_v2.pt` | RA-GAN 인종 보정 가중치 | 자체 학습 (**v2 최종 채택**) |
| `shape_predictor_68_face_landmarks.dat` | dlib 랜드마크 | [dlib 공식](http://dlib.net/files/) |

경로는 `main.py` 상단에서 환경변수로 오버라이드할 수 있습니다:
```bash
export WEIGHTS_DIR=/path/to/weights          # 전체 폴더 지정
# 또는 개별 지정
export SAM_KOREAN_PATH=/path/to/model.pt
export RAGAN_WEIGHTS_PATH=/path/to/ragan.pt
```

### 4. 서버 실행

```bash
uvicorn main:app --host 0.0.0.0 --port 8001
```

모델 로딩(SAM·RA-GAN·CodeFormer) 완료 후 요청을 받습니다.

---

## API

### `POST /api/aging`

얼굴 이미지를 받아 나이 변환 결과를 반환합니다.

**요청 (multipart/form-data)**

| 필드 | 타입 | 필수 | 설명 |
|---|---|---|---|
| `image` | file | ✅ | 입력 얼굴 이미지 |
| `target_age` | int | ✅ | 목표 나이 |
| `source_age` | int | | 원본 나이 (PTI 기준) |
| `ethnicity` | str | | `korean`(기본) / `western` |
| `father_image` / `father_age` | file / int | | 부(父) 유전 반영용 |
| `mother_image` / `mother_age` | file / int | | 모(母) 유전 반영용 |
| `alpha` | float | | 부모 blend 강도 (0.0~0.5, 기본 0.3) |

**응답**: 변환된 이미지(`image/jpeg`) + 헤더

| 헤더 | 설명 |
|---|---|
| `X-Identity-Score` | ArcFace 정체성 유사도 |
| `X-Parent-Score` | 부모 유사도 (blend 시) |
| `X-Calibrated-Target` | 보정된 목표 나이 (+5 오프셋) |
| `X-Age-Warning` | 40세 초과 경고 |
| `X-Blending` / `X-Alpha` | blend 적용 여부 / 강도 |

---

## 주요 설정 (`main.py`)

| 상수 | 값 | 설명 |
|---|---|---|
| `PTI_STEPS` | 150 | decoder 미세조정 스텝 (150=약 14초/ID 0.62, 250=약 24초/0.67) |
| `FFHQ_SCALE` | 2.4 | FFHQ 정렬 스케일 (검출 100% + 정체성 최고) |
| `CODEFORMER_FIDELITY` | 0.7 | 후처리 원본 충실도 |
| `AGE_OFFSET` | 5 | 나이 보정 오프셋 |

---

## 파일 구조

> 팀 통합 저장소의 `ai/` 파트

```
ai/
├── main.py                  # FastAPI 서버 · 나이 변환 파이프라인
├── train_ragan.py           # RA-GAN 인종 보정 모듈 학습 (v2, 최종 채택)
├── requirements.txt
├── .gitignore
│
├── scripts/                 # 규명 실험 · 검증 스크립트
│   ├── anton_gt_verify.py   # 부모 blend GT 대조 검증 (4-way)
│   ├── anton_alpha_sweep.py # alpha 강도별 스윕
│   ├── eye_color_diag.py    # 홍채 색 편향 원인 격리 진단
│   ├── eye_color_fix.py     # 홍채 색 교정 후처리
│   ├── w_blending.py        # 가족 유전 반영 (W-blending)
│   ├── extract_latents.py   # InterFaceGAN: latent 추출
│   ├── compute_direction.py # InterFaceGAN: 인종 방향벡터 산출
│   ├── apply_direction.py   # InterFaceGAN: 방향 적용
│   └── find_channels.py     # StyleSpace 채널 탐색
│
├── weights/                 # (gitignore) 모델 가중치 — 별도 준비
│   └── .gitkeep
│
└── SAM/                     # (gitignore) 외부 SAM 소스 — 클론 필요
    └── .gitkeep
```

외부 의존 코드(`SAM`, `CodeFormer`, `gfpgan`)와 모델 가중치(`weights/`)는 저장소에 포함하지 않으며, 아래 "설치 및 실행"을 따라 준비합니다.

---

## 검증된 실험 결과 및 한계

### 성능 향상 과정
| 단계 | ArcFace 정체성 |
|---|---|
| 초기 파이프라인 | 0.09 |
| + FFHQ 표준 정렬 | 0.26 |
| + PTI | **0.58** |

### 규명된 한계 (성격별 분류)

| 구분 | 한계 | 해결 가능성 |
|---|---|---|
| **정보이론적 근본** | 아동 → 성인 예측 (원본에 성인 골격 정보 없음) | 불가 |
| **데이터** | 40세+ 고령 (60대+ 244장, 0.6%) / 인종 편향 | 가능 (데이터 확보 + 재학습) |
| **구현** | decoder 재학습 시 UpFirDn2d autograd 충돌 | 가능 (autograd 재구현) |

### 주요 발견
- **서양인 편향**은 남성·앳된 얼굴에 집중되며, 성숙 여성·정면 얼굴은 안정적 (통제 실험)
- **부모 blend는 조건부** — 정체성 붕괴 시 보완 효과, 잘 보존된 경우 오히려 방해
- **아동 입력**은 나이-출력 관계가 비선형이라 성인용 나이 보정(+5)이 과증폭됨

---

## 향후 과제

편향의 근본 해결책은 **decoder(StyleGAN2)를 한국인 데이터로 재학습**하는 것입니다. StyleGAN2 전이학습은 검증된 기법(ChildGAN 등)이나, (1) SAM 커스텀 autograd 충돌 (2) 한국인 대규모 데이터·연산 확보가 선결 과제로, 독립적인 후속 연구 규모입니다.

---

## 학습 데이터 출처

- **AI Hub** — 안면 인식 에이징 이미지 데이터 (34,735장) / 가족 관계가 알려진 얼굴 이미지 데이터
- **FFHQ** — Flickr-Faces-HQ Dataset (51,969장)

> 데이터셋은 각 제공처의 라이선스를 따르며 본 저장소에 포함되지 않습니다. AI Hub 데이터는 [aihub.or.kr](https://aihub.or.kr)에서 신청 후 이용하세요.

---

## 참고 문헌

- Alaluf et al., *Only a Matter of Style: Age Transformation Using a Style-Based Regression Model* (SAM), ACM TOG 2021
- Deng et al., *ArcFace: Additive Angular Margin Loss for Deep Face Recognition*, CVPR 2019
