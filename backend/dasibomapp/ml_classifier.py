# dasibomapp/ml_classifier.py
"""
etc_spfeatr 텍스트 → 4개 카테고리 분류기
  신체특징 / 착의외형 / 건강장애 / 기타참고
"""
import pickle
import logging
from pathlib import Path

import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification

logger = logging.getLogger(__name__)

MODEL_DIR = Path(__file__).parent / "ml_models" / "etc_classifier"

_tokenizer = None
_model = None
_label_encoder = None


def _load():
    global _tokenizer, _model, _label_encoder

    if _model is not None:
        return

    logger.info(f"[EtcClassifier] 모델 로드 중: {MODEL_DIR}")

    _tokenizer = AutoTokenizer.from_pretrained(str(MODEL_DIR))
    _model = AutoModelForSequenceClassification.from_pretrained(str(MODEL_DIR))
    _model.eval()

    # 🔥 json 우선 로드, 없으면 pkl fallback
    json_path = MODEL_DIR / "label_encoder.json"
    pkl_path  = MODEL_DIR / "label_encoder.pkl"

    if json_path.exists():
        import json
        import numpy as np
        from sklearn.preprocessing import LabelEncoder

        with open(json_path, "r", encoding="utf-8") as f:
            label_data = json.load(f)

        _label_encoder = LabelEncoder()
        _label_encoder.classes_ = np.array(label_data["classes"])
        logger.info(f"[EtcClassifier] label_encoder.json 로드 완료: {label_data['classes']}")

    elif pkl_path.exists():
        import pickle
        with open(pkl_path, "rb") as f:
            _label_encoder = pickle.load(f)
        logger.info("[EtcClassifier] label_encoder.pkl 로드 완료")

    else:
        raise FileNotFoundError(f"label_encoder 파일 없음: {MODEL_DIR}")

    logger.info("[EtcClassifier] 전체 로드 완료")

def classify_etc(text: str) -> tuple[str, float]:
    """
    단일 텍스트 분류
    Returns: (카테고리명, confidence 0~1)
    """
    _load()

    if not text or not text.strip():
        return "기타참고", 0.0

    inputs = _tokenizer(
        text,
        return_tensors="pt",
        truncation=True,
        padding="max_length",
        max_length=128,
    )

    with torch.no_grad():
        logits = _model(**inputs).logits

    probs = torch.softmax(logits, dim=-1)[0]
    pred_id = int(probs.argmax())
    confidence = float(probs[pred_id])
    category = _label_encoder.inverse_transform([pred_id])[0]

    return category, confidence


def classify_batch(texts: list[str], batch_size: int = 32) -> list[tuple[str, float]]:
    """
    배치 분류 (대량 처리용)
    Returns: [(카테고리명, confidence), ...]
    """
    _load()

    results = []

    for i in range(0, len(texts), batch_size):
        batch = texts[i : i + batch_size]

        inputs = _tokenizer(
            batch,
            return_tensors="pt",
            truncation=True,
            padding=True,
            max_length=128,
        )

        with torch.no_grad():
            logits = _model(**inputs).logits

        probs = torch.softmax(logits, dim=-1)
        pred_ids = probs.argmax(dim=-1).tolist()
        confidences = probs.max(dim=-1).values.tolist()

        categories = _label_encoder.inverse_transform(pred_ids)

        results.extend(zip(categories, confidences))

    return results