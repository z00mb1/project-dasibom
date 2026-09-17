import torch
from kobert_transformers import get_tokenizer
from transformers import BertModel

# ---- KoBERT 로드 (정석) ----
TOKENIZER = get_tokenizer()
MODEL = BertModel.from_pretrained("skt/kobert-base-v1")
MODEL.eval()


# ---- 키워드 기반 보조 라벨 (Hybrid 구조) ----
DISEASE_KEYWORDS = {
    "치매": "dementia",
    "조현병": "schizophrenia",
    "정신분열": "schizophrenia",
    "우울증": "depression",
}

BEHAVIOR_KEYWORDS = {
    "보행": "mobility_issue",
    "절룩": "mobility_issue",
    "배회": "wandering",
    "노숙": "homeless_risk",
    "의사소통 가능": "can_communicate",
}


def kobert_analyze(text: str) -> dict:
    if not text:
        return {}

    # --- 1. 토큰화 ---
    inputs = TOKENIZER(
        text,
        return_tensors="pt",
        truncation=True,
        max_length=128,
        padding="max_length",
    )

    # --- 2. 임베딩 추출 ---
    with torch.no_grad():
        outputs = MODEL(**inputs)
        cls_embedding = outputs.last_hidden_state[:, 0, :]  # [CLS]

    # --- 3. 키워드 기반 분류 ---
    diseases = set()
    behaviors = set()

    for k, v in DISEASE_KEYWORDS.items():
        if k in text:
            diseases.add(v)

    for k, v in BEHAVIOR_KEYWORDS.items():
        if k in text:
            behaviors.add(v)

    # --- 4. 위험도 판단 ---
    risk = "low"
    if {"dementia", "schizophrenia"} & diseases:
        risk = "high"
    elif diseases or behaviors:
        risk = "medium"

    return {
        "ai_diseases": list(diseases),
        "ai_behaviors": list(behaviors),
        "ai_risk_level": risk,
        "ai_confidence": 0.85 if diseases or behaviors else 0.4,
    }
