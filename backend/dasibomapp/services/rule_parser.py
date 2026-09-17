# services/rule_parser.py

import re


def parse_detail_text(text: str) -> dict:
    """
    실종자 detail 텍스트에서
    규칙 기반으로 확실한 정보만 추출
    """
    result = {
        "parsed_height": None,
        "parsed_weight": None,
        "parsed_glasses": None,
        "parsed_cane": None,
        "parsed_hair_color": None,
    }

    if not text:
        return result

    # ---------- 키(cm) ----------
    height_match = re.search(r'(\d{2,3})\s*cm', text)
    if height_match:
        result["parsed_height"] = int(height_match.group(1))

    # ---------- 몸무게(kg) ----------
    weight_match = re.search(r'(\d{2,3})\s*kg', text)
    if weight_match:
        result["parsed_weight"] = int(weight_match.group(1))

    # ---------- 안경 ----------
    if "안경" in text:
        if any(x in text for x in ["미착용", "안씀", "착용 안", "없음"]):
            result["parsed_glasses"] = False
        else:
            result["parsed_glasses"] = True

    # ---------- 지팡이 ----------
    if "지팡이" in text or "보행보조기" in text:
        if any(x in text for x in ["사용X", "미사용", "사용 안"]):
            result["parsed_cane"] = False
        else:
            result["parsed_cane"] = True

    # ---------- 머리색 ----------
    if "검정" in text:
        result["parsed_hair_color"] = "검정"
    elif "흰머리" in text or "백발" in text:
        result["parsed_hair_color"] = "백발"
    elif "염색" in text:
        result["parsed_hair_color"] = "염색"

    return result
