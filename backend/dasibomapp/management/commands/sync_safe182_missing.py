# dasibomapp/management/commands/sync_safe182_missing.py
"""
Safe182 findChildList API → MissingPerson.etc_spfeatr 동기화 + AI 조각별 분류

사용법:
    python manage.py sync_safe182_missing
    python manage.py sync_safe182_missing --page-size 100
    python manage.py sync_safe182_missing --classify
    python manage.py sync_safe182_missing --classify --classify-batch-size 64
    python manage.py sync_safe182_missing --classify --min-confidence 0.25
"""

import time
import math
import logging
import re
from collections import Counter, defaultdict

import requests

from django.core.management.base import BaseCommand
from django.conf import settings

try:
    import kss
except ImportError:
    kss = None


logger = logging.getLogger(__name__)

API_URL = "https://www.safe182.go.kr/api/lcm/findChildList.do"
DELAY = 1.0


# ------------------------------------------------------------
# 1. 기본 텍스트 정리
# ------------------------------------------------------------
def normalize_feature_text(text):
    """
    원문을 삭제하지 않고, 분류하기 좋게 최소한만 정리한다.

    중요:
    - 행정/담당자/가족 정보는 삭제하지 않는다.
    - Safe182 원문에서 긴 공백은 의미 구분자로 쓰이는 경우가 있으므로 보존한다.
    """
    if not text:
        return ""

    text = str(text)

    # 줄바꿈은 의미 있는 구분자로 유지한다.
    text = text.replace("\r\n", "\n").replace("\r", "\n")

    # 탭은 공백 2칸으로 바꿔서 긴 공백 분리 로직에 걸리게 한다.
    text = text.replace("\t", "  ")

    # 전각 공백도 일반 공백으로 변환한다.
    text = text.replace("\u3000", " ")

    # 줄 양끝 공백만 정리하고, 줄 내부의 긴 공백은 보존한다.
    lines = [line.strip() for line in text.split("\n")]

    return "\n".join(lines).strip()


# ------------------------------------------------------------
# 2. KSS 기반 큰 문장 분리
# ------------------------------------------------------------
def split_by_korean_sentence(text):
    """
    KSS를 사용해 큰 문장 단위로 먼저 분리한다.
    KSS가 없거나 오류가 나면 원문 전체를 하나의 문장으로 반환한다.
    """
    if not text:
        return []

    text = str(text).strip()

    if not text:
        return []

    if kss is None:
        return [text]

    try:
        sentences = kss.split_sentences(text)
        return [s.strip() for s in sentences if s and s.strip()]
    except Exception:
        return [text]


# ------------------------------------------------------------
# 3. 노이즈 조각 제거
# ------------------------------------------------------------
def is_noise_part(part):
    """
    실제 정보가 거의 없는 조각만 제거한다.

    제거 대상:
    - 없음
    - 알수없음
    - 특이사항 없음
    - 특이이상없음
    - 마침표/기호만 있는 값
    - 숫자/기호만 있는 값

    주의:
    - 행정 메모, 담당자, 가족 정보는 제거하지 않는다.
      → 기타참고로 분류해서 보존한다.
    """
    if not part:
        return True

    text = str(part).strip()

    # 앞뒤에 붙은 목록 기호 제거
    text = text.strip(" -\t\r\n()[]{}")

    if len(text) <= 1:
        return True

    # 숫자/기호만 있는 조각: 09, 23, 2012, 5, 26, ., ...
    if re.fullmatch(r"[\d\s./'():*\-]+", text):
        return True

    # 공백 제거 버전도 함께 확인
    compact = re.sub(r"\s+", "", text)

    # 의미 없는 특이사항 없음 표현
    noise_values = {
        "없음",
        "없슴",
        "없다",
        "무",
        "불상",
        "알수없음",
        "알수없슴",
        "알수없다",
        "알수없음.",
        "알수없다.",
        "알수없음",
        "알수없음.",
        "알수없슴.",
        "알수없습니다",
        "알수없습니다.",
        "알수없음",
        "알수없음.",
        "특이사항없음",
        "특이사항없슴",
        "특이사항없다",
        "특이사항없음.",
        "특이사항없슴.",
        "특이이상없음",
        "특이이상없슴",
        "특이이상없다",
        "특이이상없음.",
        "특이이상없슴.",
        "특이한사항없음",
        "특이한사항없다",
        "특별한사항없음",
        "특별한사항없다",
        "특별사항없음",
        "특별사항없다",
        "해당없음",
        "해당사항없음",
        "이상없음",
        "이상없다",
        ".",
    }

    if compact in noise_values:
        return True

    # 문장형 표현까지 제거
    noise_patterns = [
        r"^특이\s*사항\s*없[음슴다]*\.?$",
        r"^특이\s*이상\s*없[음슴다]*\.?$",
        r"^특별한\s*사항\s*없[음슴다]*\.?$",
        r"^특별\s*사항\s*없[음슴다]*\.?$",
        r"^해당\s*사항\s*없[음슴다]*\.?$",
        r"^이상\s*없[음슴다]*\.?$",
        r"^알\s*수\s*없[음슴다]*\.?$",
        r"^없[음슴다]*\.?$",
    ]

    for pattern in noise_patterns:
        if re.fullmatch(pattern, text):
            return True

    return False

# ------------------------------------------------------------
# 4. 룰 기반 카테고리 보정
# ------------------------------------------------------------
def rule_based_category(text):
    """
    AI 결과보다 먼저 적용하는 명확 키워드 기반 보정.

    최종 카테고리:
    - 신체특징
    - 착의외형
    - 건강장애
    - 행동특성
    - 기타참고

    가족 정보 / 관리 메모 / 담당자 정보는 별도 카테고리가 없으므로 기타참고로 보낸다.
    """
    if not text:
        return None

    text = str(text).strip()
    # 가족 관계 표현은 반드시 "부/모 + 공백 + 이름" 형태일 때만 기타참고 처리
    # 예: "모 김용숙", "부 정재욱"
    if re.search(r"^(부|모)\s+[가-힣]{2,4}($|\s|\()", text):
        return "기타참고"
    # 날짜/수정 이력 메모 조각
    # 예: "2012.09.23 신체특징", "2012. 8. 22. 대상자 생년월일"
    if re.search(r"\(?\d{2,4}\.\s*\d{1,2}\.\s*\d{1,2}", text):
        return "기타참고"
    # ----------------------------------------
    # 1순위: 가족/보호자/담당자/행정/신원/수사 메모 → 기타참고
    # ----------------------------------------
    family_or_admin_keywords = [
        "유치원생",
        "초등병설",
        "병설유치원",
        "유치원",
        "초등학교",
        "초등",
        "관리카드",
        "오인기록",
        "대상자 검색중",
        "해제조치",
        "현재까지 미발견",
        "미귀가자 신고",
        "혼자 거주",
        "거주",
        "의상착의에 대해 전혀 모름",
        "착의상태 불상",
        "전혀 모름",
        "알수없음",
        "알 수 없음",
        "특이이상없음",
        "특이사항없음",
        # 가족/보호자 정보
        "부친",
        "모친",
        "아버지",
        "어머니",
        "부모",
        "보호자",
        "막내아들",
        "아들",

        # 신고/의뢰/연락처/주소
        "신고자",
        "신고자가",
        "신고인",
        "의뢰자",
        "연락처",
        "전화번호",
        "없는 전화번호",
        "주소지",
        "주소는",
        "주소를",
        "집전화",
        "현재 부모",
        "현재 재혼",
        "이혼한 상태",

        # 경찰/행정/담당자/수정 이력
        "경찰청",
        "전남청",
        "강진서",
        "서부파출소",
        "대공원파출소",
        "청주상당서",
        "서울청",
        "지방청",
        "여성청소년과",
        "여청수사",
        "여청과",
        "장기실종",
        "실종수사팀",
        "전담수사",
        "수사계획",
        "행정관",
        "경관",
        "경사",
        "경장",
        "경위",
        "팀장",
        "관련근거",
        "인터넷 공개",
        "인터넷 공",
        "공개 수정",
        "수정 강봉희",
        "수정함",
        "기재함",
        "재기재",
        "변경조치",
        "변경",
        "정비계획",
        "기존유지",
        "이관",
        "이첩",
        "이첩사유",
        "재이첩",
        "통화완료",
        "발견시통보요망",
        "관리중",
        "수배",
        "추적결과",
        "실종발생장소",

        # 별칭/신원/상황 메모
        "이명 :",
        "이명:",
        "특수학교",
        "재학",
        "재학중",
        "학교",
        "학년",
        "한강투신",
        "투신의심",
        "투신 의심",
        "투신의심자",
        "투신 의심자",

        # 수사/제보/검사
        "국과수",
        "유전자 검사",
        "유전자 채취",
        "일치자가 없다",
        "통보 받았음",
        "생사 확인",
        "제보",
        "발견치 못함",
        "발생일시후",
        "가족들의 언동",
    ]

    if any(keyword in text for keyword in family_or_admin_keywords):
        return "기타참고"

    # ----------------------------------------
    # 2순위: 건강/장애
    # ----------------------------------------
    health_keywords = [
        "장애",
        "장애우",
        "치매",
        "자폐",
        "자폐증",
        "자페성",
        "정신이상",
        "정신 이상",
        "정신지체",
        "정신질환",
        "질환",
        "복용",
        "약을 먹어야",
        "홍역",
        "걷지 못",
        "걷지못",
        "걷기 어려",
        "보행",
        "보행이상",
        "보행 불편",
        "걸을 수 없",
        "말이 어눌",
        "말이 어눌함",
        "말을 잘 못함",
        "말을 잘 못",
        "말도못",
        "의사전달",
        "허리",
        "허리 약간 굽",
        "허리 굽",
        "굽음",
        "허리가 굽",
        "허리가 많이 굽",
        "시력",
        "시력이",
        "시력이나쁨",
        "눈이 많이 나쁘",
        "실명",
        "마비",
        "뇌신경",
        "지능",
        "걸음이 느림",
        "허리가 많이 굽",
        "대소변",
        "잠을 자지 못",
        "신을 줄 몰라",
        "맨발로 다니",
    ]

    # ----------------------------------------
    # 3순위: 행동 특성
    # ----------------------------------------
    behavior_keywords = [
        "배회",
        "혼자",
        "두리번",
        "불안",
        "반복",
        "울음",
        "도망",
        "따라감",
        "소리",
        "낯선사람",
        "담배를 달라고",
        "달라고 함",
        "잘따라다녔다",
        "따라다녔다",
    ]

    # ----------------------------------------
    # 4순위: 착의/외형
    # ----------------------------------------
    clothing_keywords = [
        "티셔츠",
        "반팔티",
        "긴팔티",
        "흰색티",
        "면티",
        "반팔",
        "긴팔",
        "목티",
        "폴라티",
        "민소매티셔츠",
        "티셔츠",
        "민소매",
        "민소매티셔츠",
        "남방",
        "긴남방",
        "폴라티",
        "스웨터",
        "후드",
        "후드티",
        "반팔",
        "긴팔",

        "바지",
        "쫄바지",
        "청바지",
        "긴바지",
        "반바지",
        "츄리닝",
        "추리닝",
        "치마",
        "원피스",
        "내복",
        "조끼",

        "자켓",
        "청자켓",
        "재킷",
        "점퍼",
        "패딩",
        "코트",

        "운동화",
        "슬리퍼",
        "샌들",
        "구두",
        "랜드로바",
        "신발",
        "고무신",
        "장화",
        "단화",
        "부츠",
        "아티스",
        "아식스",

        "모자",
        "머리띠",
        "가방",
        "목걸이",
        "귀고리",
        "귀걸이",
        "안경",
        "무테안경",
        "착용",
        "상의불상",

        "검정",
        "검은색",
        "흰색",
        "횐색",
        "회색",
        "청색",
        "분홍",
        "미색",
        "밤색",
        "하늘색",
        "주황색",
        "빨간색",
        "카키색",
        "남색",
        "파란색",
        "노란색",
        "자주색",
        "연보라색",
        "까만",

        "줄무늬",
        "무늬",
        "유치원복",
        "교복",
        "체육복",
        "원복",
        "목티",
    ]

    # ----------------------------------------
    # 5순위: 신체 특징
    # ----------------------------------------
    physical_keywords = [
        "흉터",
        "상처",
        "찰과상",
        "점",
        "반점",
        "자국",
        "물린 자국",
        "수술 자국",
        "수술자국",
        "혹제거",
        "검버섯",
        "화상",
        "모기물린",
        "모기물린흉터",

        "가마",
        "쌍가마",
        "앞가마",
        "체형",
        "마른 체형",
        "매우 마른",
        "작은편",
        "키가 작은",
        "키가 작은편",
        "눈",
        "눈썹",
        "속눈썹",
        "코",
        "코밑",
        "귀",
        "입술",
        "입가",
        "입꼬리",
        "입이",
        "입이작",
        "입이 작은",
        "입이 작은편",
        "턱",
        "볼",
        "이마",
        "앞니",
        "치아",
        "수염",

        "머리카락",
        "머리",
        "단발",
        "파마머리",
        "빡빡머리",
        "짧은머리",
        "짧은 머리",
        "커트머리",
        "짧은 커트머리",
        "대머리",
        "흰머리",
        "숱",

        "피부",
        "검은피부",
        "검은 피부",
        "체격",
        "마른편",
        "마름",
        "왜소",
        "키",
        "몸무게",
        "체중",
        "배꼽",
        "참외배꼽",
        "쌍꺼풀",
        "쌍꺼플",
        "쌍커풀",
        "쌍커플",

        "달걀형",
        "둥근",
        "뾰족",
        "뽀족",
        "크고",
        "큼",
        "납작",

        "다리",
        "허벅지",
        "무릎",
        "성기",
        "엉덩이",
        "가슴",
        "주름",
        "배가 많이 나옴",
        "팔",
        "손",
        "발",
        "목",
    ]

    # 건강/행동은 착의보다 먼저 본다.
    # 예: "대소변을 가리지 못해 기저귀를 착용"은 착의가 아니라 건강장애
    if any(keyword in text for keyword in health_keywords):
        return "건강장애"

    if any(keyword in text for keyword in behavior_keywords):
        return "행동특성"

    # 색상 + 점/흉터/자국/반점은 옷 색상이 아니라 신체 특징으로 본다.
    # 예: "흰색 점이 있고", "검은 점이 있음", "빨간 점", "푸른 반점"
    color_mark_pattern = (
        r"(흰색|검은색|검은|검정색|검정|까만|빨간색|빨간|빨강|"
        r"붉은색|붉은|푸른색|푸른|파란색|파란|갈색|밤색|회색)"
        r"\s*"
        r"(점|반점|흉터|상처|자국|수술자국|화상자국)"
    )

    if re.search(color_mark_pattern, text):
        return "신체특징"

    # 명확한 신체 손상/표식 표현은 색상 키워드보다 먼저 신체특징으로 본다.
    physical_mark_keywords = [
        "점이",
        "점 있음",
        "점이 있음",
        "점이 있고",
        "흉터",
        "상처",
        "반점",
        "수술자국",
        "화상자국",
        "자국",
    ]

    if any(keyword in text for keyword in physical_mark_keywords):
        return "신체특징"

    # 착의는 위의 신체 표식 예외를 거친 뒤 검사한다.
    # 예: "베델유치원복(빨간색)"은 착의외형
    if any(keyword in text for keyword in clothing_keywords):
        return "착의외형"

    if any(keyword in text for keyword in physical_keywords):
        return "신체특징"

    return None


# ------------------------------------------------------------
# 5. 행정/담당자 정보가 특징 뒤에 붙은 경우 분리
# ------------------------------------------------------------
def split_admin_attached_part(part):
    """
    특징 문장 뒤에 행정/담당자/가족/상황 정보가 붙은 경우에만 1번 분리한다.

    예:
    '청색모자 착용 의뢰자-대공원파출소 경사 조성희'
    →
    ['청색모자 착용', '의뢰자-대공원파출소 경사 조성희']
    """
    if not part:
        return []

    text = str(part).strip()

    # ✅ 1. 특징 뒤에 날짜형 수정 메모가 붙은 경우 먼저 분리
    # 예: "허리 약간 굽음(11.11.11 사진수정 - 안숙자)"
    # 예: "오른쪽 앞니가 절반쯤 났음(2012.9.26. 경위 홍보영. 신체특징 수정)"
    date_match = re.search(r"\(?\d{2,4}\.\s*\d{1,2}\.\s*\d{1,2}", text)

    if date_match and date_match.start() > 0:
        idx = date_match.start()
        left = text[:idx].strip(" -,/.\t()")
        right = text[idx:].strip(" -,/.\t()")

        if left and right:
            left_cat = rule_based_category(left)

            if left_cat in ["신체특징", "착의외형", "건강장애", "행동특성"]:
                return [left, right]

    # ✅ 2. 날짜 외 행정/담당자/가족 키워드 기준 분리
    cut_words = [
        "의뢰자",
        "관련근거",
        "경찰청",
        "전남청",
        "강진서",
        "서부파출소",
        "대공원파출소",
        "청주상당서",
        "서울청",
        "지방청",
        "인터넷 공개",
        "인터넷 공",
        "공개 수정",
        "수정 강봉희",
        "추적결과",
        "수정함",
        "정비계획",
        "기존유지",
        "행정관",
        "경관",
        "경사",
        "경장",
        "경위",
        "팀장",
        "부친",
        "모친",
        "신고자",
        "신고자가",
        "신고인",
        "부모인적사항",
        "인적사항",
        "이첩사유",
        "유전자",
        "국과수",
        "막내아들",
        "아들",
        "특수학교",
        "재학",
        "한강투신",
        "투신의심",
        "투신 의심",
        "투신의심자",
        "투신 의심자",

        # 괄호 안 날짜/수정 메모가 특징 뒤에 붙는 경우 분리
        "(2010",
        "(2011",
        "(2012",
        "(2013",
        "(2014",
        "(2015",
        "(2016",
        "(2017",
        "(2018",
        "(2019",
        "(2020",
        "(2021",
        "(2022",
        "(2023",
        "(2024",
        "(2025",
        "(2026",
    ]

    for word in cut_words:
        idx = text.find(word)

        if idx == 0:
            return [text]

        if idx > 0:
            left = text[:idx].strip(" -,/.\t()")
            right = text[idx:].strip(" -,/.\t()")

            if not left or not right:
                return [text]

            left_cat = rule_based_category(left)

            if left_cat in ["신체특징", "착의외형", "건강장애", "행동특성"]:
                return [left, right]

    return [text]

# ------------------------------------------------------------
# 6. 한 조각 안에 여러 정보가 섞인 경우 2차 분리
# ------------------------------------------------------------
def split_mixed_part(part):
    """
    한 조각 안에 여러 정보가 섞인 경우 제한적으로만 나눈다.

    나누는 예:
    - '검정랜드로바       쌍가마'
      → ['검정랜드로바', '쌍가마']

    - '분홍 슬리퍼 착용 말을 잘 못함'
      → ['분홍 슬리퍼 착용', '말을 잘 못함']

    - '청색모자 착용                  의뢰자-대공원파출소 경사 조성희'
      → ['청색모자 착용', '의뢰자-대공원파출소 경사 조성희']
    """
    if not part:
        return []

    text = str(part).strip()

    # 1순위: 특징 + 행정/담당자/가족 정보가 붙은 경우 1회 분리
    admin_split = split_admin_attached_part(text)
    if len(admin_split) > 1:
        return admin_split

    # 2순위: 이미 기타참고 성격이면 더 이상 쪼개지 않고 통째로 보존
    if rule_based_category(text) == "기타참고":
        return [text]

    # 3순위: + 기준은 명확한 나열이므로 분리
    plus_parts = [p.strip(" -") for p in re.split(r"\+", text) if p.strip(" -")]
    if len(plus_parts) > 1:
        return plus_parts

    # 4순위: 긴 공백 기준 분리
    # normalize_feature_text에서 긴 공백을 보존해야 이 로직이 살아난다.
    space_parts = [p.strip(" -") for p in re.split(r"\s{2,}", text) if p.strip(" -")]

    if len(space_parts) > 1:
        flattened = []

        for p in space_parts:
            # 긴 공백으로 나뉜 각 조각 안에도 착의+신체가 섞여 있을 수 있으므로
            # 한 번 더 제한적으로 split_mixed_part를 적용한다.
            sub_parts = split_mixed_part(p)

            if sub_parts == [p]:
                flattened.append(p)
            else:
                flattened.extend(sub_parts)

        return flattened

    # 5순위: 착의+신체 / 신체+착의 / 착의+건강 등 명확한 혼합만 분리
    split_keywords = [
        # 신체/건강 키워드
        "쌍가마",
        "앞가마",
        "가마",
        "말이",
        "말을",
        "체중",
        "몸무게",
        "시력",
        "시력이",
        "시력이나쁨",
        "다리에",
        "다리",
        "무릎",
        "허벅지",
        "모기물린",
        "흉터",
        "상처",
        "이마"

        # 머리/외형 신체 키워드
        "짧은 커트머리",
        "커트머리",
        "짧은머리",
        "짧은 머리",
        "단발",
        "파마머리",
        "흰머리",
        "대머리",
        "머리카락",
        "머리",

        # 착의 키워드
        "까만",
        "검정",
        "흰색",
        "회색",
        "청색",
        "남색",
        "자주색",
        "목티",
        "바지",
        "운동화",
        "장화",
        "슬리퍼",
        "샌들",
        "신발",
        "모자",
        "가방",
    ]

    for keyword in split_keywords:
        idx = text.find(keyword)

        if idx > 0:
            left = text[:idx].strip(" ,-/")
            right = text[idx:].strip(" ,-/")

            if len(left) < 2 or len(right) < 2:
                continue

            left_cat = rule_based_category(left)
            right_cat = rule_based_category(right)

            # 착의 + 신체/건강/행동
            if left_cat == "착의외형" and right_cat in ["신체특징", "건강장애", "행동특성"]:
                return [left, right]

            # 신체/건강/행동 + 착의
            if left_cat in ["신체특징", "건강장애", "행동특성"] and right_cat == "착의외형":
                return [left, right]

    return [text]


# ------------------------------------------------------------
# 7. 최종 문장 분리 함수
# ------------------------------------------------------------
def split_feature_text(text):
    """
    Safe182 etcSpfeatr 원문을 실제 분류 가능한 조각으로 분리한다.

    처리 순서:
    1. normalize_feature_text()로 원문 정리
    2. KSS로 큰 문장 단위 1차 분리
    3. 쉼표, 슬래시, 줄바꿈 기준 2차 분리
    4. 숫자 사이 마침표/날짜 슬래시는 보호
    5. 행정/가족/담당자 문장은 기타참고로 통째 보존
    6. 착의+신체, 착의+건강처럼 명확히 섞인 경우만 추가 분리
    """
    if not text:
        return []

    text = normalize_feature_text(text)

    # KSS로 큰 문장 단위 1차 분리
    sentence_candidates = split_by_korean_sentence(text)

    results = []

    for sentence in sentence_candidates:
        if not sentence:
            continue

        # 괄호 닫힘 뒤 하이픈으로 새 특징이 이어지는 경우 분리
        # 예: "...말도 잘하였다고 함)-이마 가운데 상처"
        # → "...말도 잘하였다고 함)\n이마 가운데 상처"
        sentence = re.sub(r"\)\s*-\s*", ")\n", sentence)

        # 날짜/소수점 보호
        # 2012.09.23 → 2012<DOT>09<DOT>23
        # 13.5kg → 13<DOT>5kg
        sentence = re.sub(r"(?<=\d)\.(?=\d)", "<DOT>", sentence)

        # 날짜 슬래시 보호
        # 9/16, 2011/5/6 → 9<SLASH>16, 2011<SLASH>5<SLASH>6
        sentence = re.sub(r"(?<=\d)/(?=\d)", "<SLASH>", sentence)

        # 쉼표, 슬래시, 줄바꿈 기준 2차 분리
        # 단, 숫자/숫자 날짜 슬래시는 <SLASH>로 보호되어 분리되지 않음
        raw_parts = re.split(r"[,，/\n\r]+", sentence)

        for raw in raw_parts:
            part = (
                raw
                .replace("<DOT>", ".")
                .replace("<SLASH>", "/")
                .strip(" -\t()")
            )

            if not part:
                continue

            # '없음 검은색조끼착용' → '검은색조끼착용'
            part = re.sub(r"^없음\s*", "", part).strip()

            if not part:
                continue

            if is_noise_part(part):
                continue

            sub_parts = split_mixed_part(part)

            for sub in sub_parts:
                sub = (
                    sub
                    .replace("<DOT>", ".")
                    .replace("<SLASH>", "/")
                    .strip(" -\t()")
                )

                sub = re.sub(r"^없음\s*", "", sub).strip()

                if not sub:
                    continue

                if is_noise_part(sub):
                    continue

                results.append(sub)

    return results

class Command(BaseCommand):
    help = "Safe182 API → MissingPerson etc_spfeatr 동기화 + AI 조각별 분류"

    def add_arguments(self, parser):
        parser.add_argument(
            "--page-size",
            type=int,
            default=100,
            help="Safe182 API 페이지당 요청 개수",
        )

        parser.add_argument(
            "--delay",
            type=float,
            default=DELAY,
            help="페이지 요청 사이 대기 시간",
        )

        parser.add_argument(
            "--classify",
            action="store_true",
            help="etc_spfeatr → AI 카테고리 분류 실행",
        )

        parser.add_argument(
            "--classify-batch-size",
            type=int,
            default=32,
            help="AI 분류 배치 크기",
        )

        parser.add_argument(
            "--min-confidence",
            type=float,
            default=0.25,
            help="이 값 미만이면 기타참고로 처리",
        )

    def handle(self, *args, **options):
        from dasibomapp.models import MissingPerson

        page_size = options["page_size"]
        delay = options["delay"]
        do_classify = options["classify"]
        batch_size = options["classify_batch_size"]
        min_conf = options["min_confidence"]

        # ─────────────────────────────────────────────
        # 1. Safe182 API 전체 수신
        # ─────────────────────────────────────────────
        first = self._fetch(page=1, page_size=page_size)

        if not first:
            self.stderr.write("API 호출 실패")
            return

        total = int(first.get("totalCount", 0))
        total_pages = math.ceil(total / page_size)

        self.stdout.write(f"전체 {total}건 / {total_pages}페이지")

        all_rows = first.get("list", [])

        for page in range(2, total_pages + 1):
            time.sleep(delay)

            data = self._fetch(page=page, page_size=page_size)

            if data:
                all_rows.extend(data.get("list", []))
            else:
                self.stderr.write(f"페이지 {page} 실패, 스킵")

        self.stdout.write(f"총 {len(all_rows)}건 수신 — DB 업데이트 시작...")

        # ─────────────────────────────────────────────
        # 2. etc_spfeatr DB 업데이트
        #    FOUND 처리된 실종자는 업데이트하지 않음
        # ─────────────────────────────────────────────
        updated = 0
        skipped = 0
        error = 0

        for row in all_rows:
            msspsn_id = str(row.get("msspsnIdntfccd", "")).strip()
            etc = (row.get("etcSpfeatr") or "").strip()

            if not msspsn_id:
                error += 1
                continue

            try:
                cnt = (
                    MissingPerson.objects
                    .filter(
                        msspsn_idntfccd=msspsn_id,
                        status=MissingPerson.Status.MISSING,
                    )
                    .update(etc_spfeatr=etc)
                )

                if cnt:
                    updated += 1
                else:
                    skipped += 1

            except Exception as e:
                logger.error(f"업데이트 실패 ({msspsn_id}): {e}")
                error += 1

        self.stdout.write(
            f"etc_spfeatr 동기화 — 업데이트: {updated} | 스킵: {skipped} | 오류: {error}"
        )

        # ─────────────────────────────────────────────
        # 3. AI 분류
        # ─────────────────────────────────────────────
        if not do_classify:
            self.stdout.write("분류 스킵 (--classify 없음)")
            return

        self._run_classification(
            batch_size=batch_size,
            min_conf=min_conf,
        )

    # ─────────────────────────────────────────────
    # AI 분류
    # ─────────────────────────────────────────────
    def _run_classification(self, batch_size: int, min_conf: float):
        """
        etc_spfeatr를 문장 조각 단위로 분리한 뒤 AI 배치 분류를 수행한다.

        저장 방식:
        1. etc_ai_segments
           - 문장 조각별 text/category/confidence 저장

        2. etc_ai_category
           - 조각별 결과 중 가장 많이 나온 대표 카테고리 저장

        3. etc_ai_confidence
           - 대표 카테고리에 해당하는 조각들의 confidence 평균 저장

        중요:
        - status=missing인 MissingPerson만 분류한다.
        - status=found인 데이터는 분류하지 않는다.
        - 가족/행정/담당자 정보는 삭제하지 않고 기타참고로 분류한다.
        - AI 원본 결과는 raw_category로 저장한다.
        - 최종 category는 raw AI 결과를 기본으로 사용하되,
          행정/가족/날짜/수정 메모와 강한 건강장애 패턴만 rule을 우선 적용한다.
        - 전처리 후 조각이 없는 대상자는 기존 AI 결과를 비운다.
        """
        from dasibomapp.models import MissingPerson
        from dasibomapp.ml_classifier import classify_batch

        self.stdout.write("\nAI 분류 시작...")
        self.stdout.write("  방식: KSS 1차 분리 → 룰 기반 조각 분리 → AI 분류 → 선택적 룰 보정 → etc_ai_segments 저장")
        self.stdout.write("  대상: status=missing 상태인 MissingPerson만 분류")
        self.stdout.write("  가족/행정/담당자 정보는 삭제하지 않고 기타참고로 저장")
        self.stdout.write("  최종 판단: AI raw 우선, 기타참고/강한 건강장애/명확한 착의만 룰 보정")

        qs = (
            MissingPerson.objects
            .filter(status=MissingPerson.Status.MISSING)
            .exclude(etc_spfeatr="")
            .exclude(etc_spfeatr__isnull=True)
            .only("id", "etc_spfeatr")
        )

        total = qs.count()
        self.stdout.write(f"  분류 대상 MissingPerson: {total}건")

        if total == 0:
            self.stdout.write("  분류 대상 없음")
            return

        # ------------------------------------------------------------
        # 1. MissingPerson별 etc_spfeatr를 문장 조각으로 분리
        # ------------------------------------------------------------
        all_parts = []
        owner_ids = []
        no_part_count = 0
        no_part_ids = []

        for mp in qs.iterator(chunk_size=500):
            raw_text = (mp.etc_spfeatr or "").strip()

            if not raw_text:
                no_part_count += 1
                no_part_ids.append(mp.id)
                continue

            parts = split_feature_text(raw_text)

            if not parts:
                no_part_count += 1
                no_part_ids.append(mp.id)
                continue

            for part in parts:
                all_parts.append(part)
                owner_ids.append(mp.id)

        part_total = len(all_parts)
        self.stdout.write(f"  분리된 문장 조각: {part_total}개")
        self.stdout.write(f"  전처리 후 조각 없음: {no_part_count}건")

        # ------------------------------------------------------------
        # 2. 조각 단위 AI 배치 분류
        # ------------------------------------------------------------
        part_results = []

        if part_total > 0:
            part_results = classify_batch(
                all_parts,
                batch_size=batch_size,
            )
        else:
            self.stdout.write("  분류할 문장 조각 없음 — 기존 AI 결과 비우기만 수행")

        # ------------------------------------------------------------
        # 3. MissingPerson id별 분류 결과 그룹화
        # ------------------------------------------------------------
        grouped = defaultdict(list)

        # rule이 건강장애로 잡혔을 때, raw보다 rule을 우선 적용할 강한 건강장애 패턴
        # 예: "돌이 지났음에도 걷지 못했다고 함"은 raw가 행동특성이어도 건강장애가 맞음
        force_health_patterns = [

            "걷지 못",
            "걷지못",
            "걷기 어려",
            "걸을 수 없",
            "보행",
            "보행이상",
            "보행 불편",
            "절뚝",
            "다리가 불편",
            "지팡이",
            "휠체어",
            "보조기",
            "마비",
            "실명",
            "청력",
            "시력",
            "보청기",
            "말을 하지 못",
            "말을 잘 못",
            "말을 못",
            "발음이부정확",
            "언어구사력",
            "의사소통",
            "대소변",
            "기저귀",
            "치매",
            "정신지체",
            "자폐",
            "장애",
        ]
        # 색상 + 점/흉터/자국처럼 AI가 착의외형으로 오판하기 쉬운 신체 표식 강제 보정
        force_physical_patterns = [
            "흰색 점",
            "흰 점",
            "검은 점",
            "검정색 점",
            "검정 점",
            "까만 점",
            "빨간 점",
            "빨강색 점",
            "붉은 점",
            "푸른 점",
            "파란 점",
            "갈색 점",
            "밤색 점",
            "회색 점",
            "주근깨",
            "반점",
            "흉터",
            "수술자국",
            "화상자국",
            "손톱자국",
            "점이 있었",
            "점이 있",
            "점 있음",
        ]

        for pk, part, result in zip(owner_ids, all_parts, part_results):
            raw_category, conf = result
            conf = float(conf)

            rule_category = rule_based_category(part)

            # --------------------------------------------------------
            # 최종 카테고리 결정 로직
            # --------------------------------------------------------
            # 1. 강한 건강장애 패턴은 rule을 우선 적용
            #    단, rule_category가 건강장애일 때만 적용한다.
            if (
                    rule_category == "건강장애"
                    and any(pattern in part for pattern in force_health_patterns)
            ):
                final_category = "건강장애"
            elif (
                    rule_category == "신체특징"
                    and any(pattern in part for pattern in force_physical_patterns)
            ):
                final_category = "신체특징"

            # 2. 행정/가족/날짜/수정/수사 메모는 rule 강제
            elif rule_category == "기타참고":
                final_category = "기타참고"

            # 3. AI가 기타참고로 봤는데 rule이 명확한 착의면 착의로 보정
            #    예: "횐색티", "검정랜드로바" 같은 짧은 착의 단어
            elif raw_category == "기타참고" and rule_category == "착의외형":
                final_category = "착의외형"

            # 4. AI confidence가 애매하고 rule이 있으면 rule 보조
            #    예: "보통체격" raw=건강장애 conf 낮음, rule=신체특징이면 신체특징으로 보정
            elif conf < 0.70 and rule_category:
                # 색상 단어 때문에 "흰색 점", "검은 점" 같은 신체특징이 착의외형으로 오탐되는 것 방지
                if raw_category == "신체특징" and rule_category == "착의외형":
                    final_category = raw_category
                else:
                    final_category = rule_category
            # 5. 그 외에는 confidence가 충분하면 AI raw를 우선
            elif conf >= min_conf:
                final_category = raw_category

            # 6. AI confidence가 낮을 때만 rule 보조
            elif rule_category:
                final_category = rule_category

            # 7. 둘 다 애매하면 기타참고
            else:
                final_category = "기타참고"

            grouped[pk].append({
                "text": part,
                "category": final_category,
                "raw_category": raw_category,
                "rule_category": rule_category,
                "confidence": round(conf, 4),
            })

        # ------------------------------------------------------------
        # 4. 각 MissingPerson별 대표 카테고리 + segments 저장값 생성
        # ------------------------------------------------------------
        bulk = []
        low_conf_count = 0
        rule_override_count = 0
        no_result_count = 0

        # 전처리 후 조각이 없는 대상자는 기존 AI 결과를 비운다.
        # 예: "없음", ".", "특이이상없음", "알수없음"
        for mp_id in no_part_ids:
            bulk.append(
                MissingPerson(
                    id=mp_id,
                    etc_ai_category="기타참고",
                    etc_ai_confidence=0.0,
                    etc_ai_segments=[],
                )
            )

        for mp_id, segment_results in grouped.items():
            if not segment_results:
                no_result_count += 1

                bulk.append(
                    MissingPerson(
                        id=mp_id,
                        etc_ai_category="기타참고",
                        etc_ai_confidence=0.0,
                        etc_ai_segments=[],
                    )
                )
                continue

            for item in segment_results:
                if item["confidence"] < min_conf:
                    low_conf_count += 1

                # raw와 최종 category가 달라진 경우를 실제 보정 건수로 계산
                if item.get("category") != item.get("raw_category"):
                    rule_override_count += 1

            # 대표 카테고리는 최종 category 기준으로 계산하되,
            # 기타참고는 특징 카테고리가 하나도 없을 때만 대표로 사용한다.
            feature_items = [
                item for item in segment_results
                if item["category"] != "기타참고"
            ]

            if feature_items:
                category_counter = Counter(
                    item["category"] for item in feature_items
                )
                representative_category = category_counter.most_common(1)[0][0]

                representative_confs = [
                    item["confidence"]
                    for item in feature_items
                    if item["category"] == representative_category
                ]
            else:
                category_counter = Counter(
                    item["category"] for item in segment_results
                )
                representative_category = category_counter.most_common(1)[0][0]

                representative_confs = [
                    item["confidence"]
                    for item in segment_results
                    if item["category"] == representative_category
                ]

            avg_conf = (
                sum(representative_confs) / len(representative_confs)
                if representative_confs
                else 0.0
            )

            segments = [
                {
                    "text": item["text"],
                    "category": item["category"],
                    "confidence": item["confidence"],
                    "raw_category": item["raw_category"],
                    "rule_category": item["rule_category"],
                }
                for item in segment_results
            ]

            bulk.append(
                MissingPerson(
                    id=mp_id,
                    etc_ai_category=representative_category,
                    etc_ai_confidence=round(avg_conf, 4),
                    etc_ai_segments=segments,
                )
            )

        # ------------------------------------------------------------
        # 5. bulk_update
        # ------------------------------------------------------------
        if bulk:
            MissingPerson.objects.bulk_update(
                bulk,
                [
                    "etc_ai_category",
                    "etc_ai_confidence",
                    "etc_ai_segments",
                ],
                batch_size=200,
            )

        self.stdout.write(
            self.style.SUCCESS(
                "AI 분류 완료 — "
                f"MissingPerson: {len(bulk)}건 | "
                f"문장 조각: {part_total}개 | "
                f"저신뢰 조각: {low_conf_count}개 | "
                f"룰 보정: {rule_override_count}개 | "
                f"결과 없음: {no_result_count}건 | "
                f"전처리 후 조각 없음: {no_part_count}건"
            )
        )    # ─────────────────────────────────────────────
    # Safe182 API 호출
    # ─────────────────────────────────────────────
    def _fetch(self, page: int, page_size: int):
        payload = {
            "esntlId": settings.SAFE182_USER_ID,
            "authKey": settings.SAFE182_API_KEY,
            "rowSize": page_size,
            "page": page,
        }

        try:
            resp = requests.post(
                API_URL,
                data=payload,
                timeout=15,
            )
            resp.raise_for_status()

            data = resp.json()

            if data.get("result") != "00":
                logger.warning(f"API 오류: {data.get('msg')}")
                return None

            return data

        except Exception as e:
            logger.error(f"API 요청 실패 page={page}: {e}")
            return None