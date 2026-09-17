# services/risk_engine.py
"""
실종자 detail 텍스트 기반
- 규칙기반 특징 추출
- 위험도 계산
- 프론트용 카테고리 구조 생성

※ KoBERT는 보조 수단
※ 규칙기반이 1차 판단자
"""

# ==============================
# 0. Status 코드 위험 가중치
# ==============================

STATUS_RISK_WEIGHT = {
    "010": 1,  # 정상아동
    "020": 2,  # 가출인
    "040": 2,  # 무연고
    "060": 3,  # 지적장애
    "061": 3,  # 지적장애(미성년)
    "062": 3,  # 지적장애(성인)
    "070": 4,  # 치매
    "080": 1,  # 기타
}

STATUS_LABEL_MAP = {
    "010": "정상아동",
    "020": "가출인",
    "040": "시설보호 무연고자",
    "060": "지적장애인",
    "061": "지적장애인(18세 미만)",
    "062": "지적장애인(18세 이상)",
    "070": "치매질환자",
    "080": "기타",
}

# ==============================
# 1. 키워드 사전
# ==============================

# --- 건강 · 장애 ---
HEALTH_KEYWORDS = {
    "치매": ("dementia", 3),
    "알츠하이머": ("dementia", 3),
    "기억상실": ("dementia", 2),
    "기억력 저하": ("dementia", 2),

    "정신분열": ("schizophrenia", 3),
    "조현병": ("schizophrenia", 3),
    "망상": ("schizophrenia", 2),

    "우울증": ("depression", 2),
    "정신과": ("depression", 2),
    "병원치료 중": ("depression", 1),

    "지적장애": ("intellectual_disability", 3),
    "지적장애인": ("intellectual_disability", 3),
    "발달장애": ("developmental_disability", 3),
}

# --- 성격 · 행동 ---
BEHAVIOR_KEYWORDS = {
    "절룩": ("mobility_issue", 2),
    "보행": ("mobility_issue", 2),
    "걷기 불편": ("mobility_issue", 2),
    "종종걸음": ("mobility_issue", 1),
    "걸음걸이 느림": ("mobility_issue", 1),

    "배회": ("wandering", 3),
    "길을 헤맴": ("wandering", 3),
    "방향감각": ("wandering", 2),

    "노숙": ("homeless_risk", 3),
    "노숙자": ("homeless_risk", 3),
    "거주 불명": ("homeless_risk", 2),

    "의사소통 불가": ("communication_issue", 3),
    "말이 안 통함": ("communication_issue", 3),
    "의사소통 어려움": ("communication_issue", 2),
}

# --- 위험 상황 ---
RISK_CONTEXT_KEYWORDS = {
    "휴대폰 미소지": 1,
    "연락 두절": 2,
    "차량 없음": 1,
    "무직": 1,
    "혼자 거주": 1,
    "가출": 2,
    "보호자 없음": 2,
}

# ==============================
# 2. 한글 매핑
# ==============================

DISEASE_MAP = {
    "dementia": "치매",
    "schizophrenia": "조현병",
    "depression": "우울증",
    "intellectual_disability": "지적장애",
    "developmental_disability": "발달장애",
}

BEHAVIOR_MAP = {
    "mobility_issue": "보행 장애",
    "wandering": "배회 위험",
    "homeless_risk": "노숙 위험",
    "communication_issue": "의사소통 어려움",
}

# ==============================
# 3. 규칙기반 특징 추출
# ==============================

def extract_ai_features_from_detail(text: str):
    """
    detail 원문에서
    - 질병 코드
    - 행동 코드
    - 위험 점수
    추출
    """
    diseases = set()
    behaviors = set()
    score = 0
    reasons = []

    if not text:
        return [], [], 0, []

    # 건강
    for keyword, (code, weight) in HEALTH_KEYWORDS.items():
        if keyword in text:
            diseases.add(code)
            score += weight
            reasons.append(DISEASE_MAP.get(code, keyword))

    # 행동
    for keyword, (code, weight) in BEHAVIOR_KEYWORDS.items():
        if keyword in text:
            behaviors.add(code)
            score += weight
            reasons.append(BEHAVIOR_MAP.get(code, keyword))

    # 위험 상황
    for keyword, weight in RISK_CONTEXT_KEYWORDS.items():
        if keyword in text:
            score += weight
            reasons.append(keyword)

    return list(diseases), list(behaviors), score, reasons


# ==============================
# 4. 위험도 계산 (핵심)
# ==============================

def calculate_risk(person):
    """
    MissingPerson 객체 기준
    - 규칙 기반 + status 코드
    - 위험도 + 점수 + 이유 문장 반환
    """

    score = 0
    reasons = []

    # 1️⃣ detail 기반 규칙 추출
    diseases, behaviors, rule_score, rule_reasons = extract_ai_features_from_detail(
        person.detail or ""
    )

    score += rule_score
    reasons.extend(rule_reasons)

    # DB에 반영 (중복 제거)
    person.ai_diseases = list(set(diseases))
    person.ai_behaviors = list(set(behaviors))

    # 2️⃣ 고령 가중치
    if person.current_age and person.current_age >= 65:
        score += 2
        reasons.append("고령")

    # 3️⃣ status 코드 가중치
    if person.status in STATUS_RISK_WEIGHT:
        score += STATUS_RISK_WEIGHT[person.status]
        reasons.append(STATUS_LABEL_MAP.get(person.status, f"상태코드 {person.status}"))

    # 4️⃣ 위험도 결정
    if score >= 7:
        risk = "high"
    elif score >= 4:
        risk = "medium"
    else:
        risk = "low"

    reason_text = " + ".join(dict.fromkeys(reasons))  # 순서 유지 중복 제거

    return risk, score, reason_text


# ==============================
# 5. 프론트용 카테고리 생성
# ==============================

def categorize_missing_person(person):
    """
    프론트에서 바로 쓰는 분류 구조
    """
    categories = {
        "신체 특징": [],
        "성격·행동 특성": [],
        "건강·장애 정보": [],
        "착의·외형 정보": [],
        "기타 참고 사항": [],
    }

    # 신체
    if person.parsed_height:
        categories["신체 특징"].append(f"키 약 {person.parsed_height}cm")
    if person.parsed_weight:
        categories["신체 특징"].append(f"체중 약 {person.parsed_weight}kg")
    if person.parsed_cane:
        categories["신체 특징"].append("지팡이 사용")

    # 건강
    for d in person.ai_diseases or []:
        if d in DISEASE_MAP:
            categories["건강·장애 정보"].append(DISEASE_MAP[d])

    if person.current_age and person.current_age >= 65:
        categories["건강·장애 정보"].append("고령")

    # 행동
    for b in person.ai_behaviors or []:
        if b in BEHAVIOR_MAP:
            categories["성격·행동 특성"].append(BEHAVIOR_MAP[b])

    # 착의
    if person.parsed_glasses is True:
        categories["착의·외형 정보"].append("안경 착용")
    elif person.parsed_glasses is False:
        categories["착의·외형 정보"].append("안경 미착용")

    if person.parsed_hair_color:
        categories["착의·외형 정보"].append(f"{person.parsed_hair_color}색 머리")

    # 기타
    if person.detail:
        categories["기타 참고 사항"].append(person.detail)

    return categories
