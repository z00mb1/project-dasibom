# dasibomapp/services/kobert/infer.py

import torch
from pathlib import Path
from transformers import BertTokenizer

from .model import KoBERTClassifier

# -------------------------------------------------
# 1️⃣ 경로 설정
# -------------------------------------------------
BASE_DIR = Path(__file__).resolve().parents[2]     # dasibomapp/
MODEL_PATH = BASE_DIR.parent / "models" / "kobert_cls.pt"

# -------------------------------------------------
# 2️⃣ 상수 정의
# -------------------------------------------------
LABELS = ["health", "behavior", "risk_context"]

# -------------------------------------------------
# 3️⃣ 모델 / 토크나이저 로드 (1회)
# -------------------------------------------------
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

tokenizer = BertTokenizer.from_pretrained("monologg/kobert")

model = KoBERTClassifier()
model.load_state_dict(
    torch.load(MODEL_PATH, map_location=device)
)
model.to(device)
model.eval()

print("✅ KoBERT inference model loaded from:", MODEL_PATH)

# -------------------------------------------------
# 4️⃣ 추론 함수 (이것만 외부에서 사용)
# -------------------------------------------------
@torch.no_grad()
def classify_detail(text: str, threshold: float = 0.5):
    """
    detail 텍스트 → 의미 분류

    return:
    {
        "labels": {
            "health": bool,
            "behavior": bool,
            "risk_context": bool
        },
        "confidence": {
            "health": float,
            "behavior": float,
            "risk_context": float
        }
    }
    """
    if not text or not text.strip():
        return {
            "labels": {k: False for k in LABELS},
            "confidence": {k: 0.0 for k in LABELS},
        }

    enc = tokenizer(
        text,
        return_tensors="pt",
        truncation=True,
        padding=True,
        max_length=256
    )

    input_ids = enc["input_ids"].to(device)
    attention_mask = enc["attention_mask"].to(device)

    logits = model(input_ids, attention_mask)
    probs = torch.sigmoid(logits).squeeze(0).tolist()

    labels = {
        label: (prob >= threshold)
        for label, prob in zip(LABELS, probs)
    }

    confidence = {
        label: float(prob)
        for label, prob in zip(LABELS, probs)
    }

    return {
        "labels": labels,
        "confidence": confidence
    }
