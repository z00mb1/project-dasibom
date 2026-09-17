#views.py

# ==============================
# 1. Django
# ==============================
from django.conf import settings
from datetime import date
from dasibomapp.storage import media_url
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.timezone import now
from django.utils.dateparse import parse_datetime
from django.db import transaction
from django.db.models import Q, Count, Prefetch
from django.core.cache import cache
from django.core.files.storage import default_storage
from django.core.files.base import ContentFile
from django.contrib.auth.hashers import make_password, check_password
from .serializers import split_feature_text
# ==============================
# 2. DRF
# ==============================
from rest_framework import viewsets, status, filters, generics
from rest_framework.decorators import action, permission_classes
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.generics import ListAPIView
from rest_framework.permissions import IsAuthenticated, AllowAny

from rest_framework_simplejwt.tokens import AccessToken, RefreshToken
import requests
from django.http import HttpResponse
# ==============================
# 3. Third-party
# ==============================
from django_filters.rest_framework import DjangoFilterBackend
from firebase_admin import auth as firebase_auth
from difflib import SequenceMatcher
import uuid
import imagehash
from PIL import Image
import math
import logging
import json
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
logger = logging.getLogger(__name__)
from concurrent.futures import ThreadPoolExecutor, as_completed
import time
# ==============================
# 4. Python 기본
# ==============================
from datetime import datetime, timedelta

# ==============================
# 5. Local (중요🔥)
# ==============================
from .models import *

from .serializers import *

from dasibomapp.services.safety_map_service import get_nearby_facilities
from dasibomapp.permissons import *
def format_datetime_for_front(dt):
    """
    프론트 표시용 날짜/시간 포맷 변환
    예: 2026-05-26T05:11:36.254069Z → 2026.05.26 14:11
    """
    if not dt:
        return None

    try:
        local_dt = timezone.localtime(dt)
        return local_dt.strftime("%Y.%m.%d %H:%M")
    except Exception:
        return None

# =========================================================
# 지역 / 분류 필터 공통 매핑
# =========================================================

REGION_ALIASES = {
    "서울": ["서울", "서울특별시"],
    "서울특별시": ["서울", "서울특별시"],

    "부산": ["부산", "부산광역시"],
    "부산광역시": ["부산", "부산광역시"],

    "대구": ["대구", "대구광역시"],
    "대구광역시": ["대구", "대구광역시"],

    "인천": ["인천", "인천광역시"],
    "인천광역시": ["인천", "인천광역시"],

    "광주": ["광주", "광주광역시"],
    "광주광역시": ["광주", "광주광역시"],

    "대전": ["대전", "대전광역시"],
    "대전광역시": ["대전", "대전광역시"],

    "울산": ["울산", "울산광역시"],
    "울산광역시": ["울산", "울산광역시"],

    "세종": ["세종", "세종특별자치시"],
    "세종특별자치시": ["세종", "세종특별자치시"],

    "경기": ["경기", "경기도"],
    "경기도": ["경기", "경기도"],

    "강원": ["강원", "강원도", "강원특별자치도"],
    "강원도": ["강원", "강원도", "강원특별자치도"],
    "강원특별자치도": ["강원", "강원도", "강원특별자치도"],

    "충북": ["충북", "충청북도"],
    "충청북도": ["충북", "충청북도"],

    "충남": ["충남", "충청남도"],
    "충청남도": ["충남", "충청남도"],

    "전북": ["전북", "전라북도", "전북특별자치도"],
    "전라북도": ["전북", "전라북도", "전북특별자치도"],
    "전북특별자치도": ["전북", "전라북도", "전북특별자치도"],

    "전남": ["전남", "전라남도"],
    "전라남도": ["전남", "전라남도"],

    "경북": ["경북", "경상북도"],
    "경상북도": ["경북", "경상북도"],

    "경남": ["경남", "경상남도"],
    "경상남도": ["경남", "경상남도"],

    "제주": ["제주", "제주도", "제주특별자치도"],
    "제주도": ["제주", "제주도", "제주특별자치도"],
    "제주특별자치도": ["제주", "제주도", "제주특별자치도"],
}
# =========================================================
# 전국 시·군·구 → 시·도 매핑
#
# 주소에 시/도가 빠져 있어도
# "고양시 ...", "문경시 ..." 같은 주소를
# 해당 시/도로 분류하기 위한 데이터
# =========================================================

REGION_SIGUNGU = {
    "서울": [
        "종로구", "중구", "용산구", "성동구", "광진구",
        "동대문구", "중랑구", "성북구", "강북구", "도봉구",
        "노원구", "은평구", "서대문구", "마포구", "양천구",
        "강서구", "구로구", "금천구", "영등포구", "동작구",
        "관악구", "서초구", "강남구", "송파구", "강동구",
    ],

    "부산": [
        "중구", "서구", "동구", "영도구", "부산진구",
        "동래구", "남구", "북구", "해운대구", "사하구",
        "금정구", "강서구", "연제구", "수영구", "사상구",
        "기장군",
    ],

    "대구": [
        "중구", "동구", "서구", "남구", "북구",
        "수성구", "달서구", "달성군", "군위군",
    ],

    "인천": [
        "중구", "동구", "미추홀구", "연수구", "남동구",
        "부평구", "계양구", "서구", "강화군", "옹진군",
    ],

    "광주": [
        "동구", "서구", "남구", "북구", "광산구",
    ],

    "대전": [
        "동구", "중구", "서구", "유성구", "대덕구",
    ],

    "울산": [
        "중구", "남구", "동구", "북구", "울주군",
    ],

    # 세종은 기초자치단체가 따로 없지만
    # 비정형 데이터에서 "세종시"가 들어올 수 있으므로 포함
    "세종": [
        "세종시",
    ],

    "경기": [
        "수원시", "성남시", "의정부시", "안양시", "부천시",
        "광명시", "평택시", "동두천시", "안산시", "고양시",
        "과천시", "구리시", "남양주시", "오산시", "시흥시",
        "군포시", "의왕시", "하남시", "용인시", "파주시",
        "이천시", "안성시", "김포시", "화성시", "광주시",
        "양주시", "포천시", "여주시",
        "연천군", "가평군", "양평군",
    ],

    "강원": [
        "춘천시", "원주시", "강릉시", "동해시", "태백시",
        "속초시", "삼척시",
        "홍천군", "횡성군", "영월군", "평창군", "정선군",
        "철원군", "화천군", "양구군", "인제군", "고성군",
        "양양군",
    ],

    "충북": [
        "청주시", "충주시", "제천시",
        "보은군", "옥천군", "영동군", "증평군", "진천군",
        "괴산군", "음성군", "단양군",
    ],

    "충남": [
        "천안시", "공주시", "보령시", "아산시", "서산시",
        "논산시", "계룡시", "당진시",
        "금산군", "부여군", "서천군", "청양군", "홍성군",
        "예산군", "태안군",
    ],

    "전북": [
        "전주시", "군산시", "익산시", "정읍시", "남원시",
        "김제시",
        "완주군", "진안군", "무주군", "장수군", "임실군",
        "순창군", "고창군", "부안군",
    ],

    "전남": [
        "목포시", "여수시", "순천시", "나주시", "광양시",
        "담양군", "곡성군", "구례군", "고흥군", "보성군",
        "화순군", "장흥군", "강진군", "해남군", "영암군",
        "무안군", "함평군", "영광군", "장성군", "완도군",
        "진도군", "신안군",
    ],

    "경북": [
        "포항시", "경주시", "김천시", "안동시", "구미시",
        "영주시", "영천시", "상주시", "문경시", "경산시",
        "의성군", "청송군", "영양군", "영덕군", "청도군",
        "고령군", "성주군", "칠곡군", "예천군", "봉화군",
        "울진군", "울릉군",
    ],

    "경남": [
        "창원시", "진주시", "통영시", "사천시", "김해시",
        "밀양시", "거제시", "양산시",
        "의령군", "함안군", "창녕군", "고성군", "남해군",
        "하동군", "산청군", "함양군", "거창군", "합천군",
    ],

    "제주": [
        "제주시", "서귀포시",
    ],
}

CATEGORY_ALIASES = {
    "아동": ["아동"],
    "장애": ["장애"],

    # 화면에서는 둘 다 '치매'로 표시
    "치매": ["치매", "치매환자"],
    "치매환자": ["치매", "치매환자"],

    "가출인": ["가출인"],
}

def normalize_region_name(region):
    """
    시/도 약칭/정식명을 내부 대표명으로 통일
    """

    if not region:
        return None

    region = str(region).strip()

    REGION_NORMALIZE = {
        "서울": "서울",
        "서울특별시": "서울",

        "부산": "부산",
        "부산광역시": "부산",

        "대구": "대구",
        "대구광역시": "대구",

        "인천": "인천",
        "인천광역시": "인천",

        "광주": "광주",
        "광주광역시": "광주",

        "대전": "대전",
        "대전광역시": "대전",

        "울산": "울산",
        "울산광역시": "울산",

        "세종": "세종",
        "세종특별자치시": "세종",

        "경기": "경기",
        "경기도": "경기",

        "강원": "강원",
        "강원도": "강원",
        "강원특별자치도": "강원",

        "충북": "충북",
        "충청북도": "충북",

        "충남": "충남",
        "충청남도": "충남",

        "전북": "전북",
        "전라북도": "전북",
        "전북특별자치도": "전북",

        "전남": "전남",
        "전라남도": "전남",

        "경북": "경북",
        "경상북도": "경북",

        "경남": "경남",
        "경상남도": "경남",

        "제주": "제주",
        "제주도": "제주",
        "제주특별자치도": "제주",
    }

    return REGION_NORMALIZE.get(
        region,
        region,
    )
def build_unique_sigungu_map():
    """
    전국에서 이름이 하나의 시/도에만 존재하는
    시군구만 자동으로 매핑한다.

    예:
    고양시 -> 경기       O
    문경시 -> 경북       O
    광주시 -> 경기       O

    중구 -> 여러 지역    X
    서구 -> 여러 지역    X
    고성군 -> 강원/경남  X
    """

    temp = {}

    for region, names in REGION_SIGUNGU.items():

        for name in names:

            if name not in temp:
                temp[name] = set()

            temp[name].add(region)

    unique_map = {}

    for name, regions in temp.items():

        if len(regions) == 1:
            unique_map[name] = next(
                iter(regions)
            )

    return unique_map


UNIQUE_SIGUNGU_TO_REGION = build_unique_sigungu_map()
def build_region_query(region):
    """
    지역 필터.

    1. 시/도 정식명/약칭으로 시작하는 주소
    2. 시/도가 생략됐지만 전국에서 지역을
       유일하게 판별할 수 있는 시군구 주소

    예:
    region=경기

    O 경기도 고양시 ...
    O 경기 고양시 ...
    O 고양시 고양동 ...
    O 광주시 경안동 ...

    X 광주광역시 ...
    X 서울특별시 세종대로 ...

    이름이 중복되는 시군구는
    시도가 없으면 임의 판별하지 않는다.
    """

    if not region:
        return None

    region = str(region).strip()

    if not region:
        return None

    normalized_region = normalize_region_name(
        region
    )

    query = Q()

    # =====================================================
    # 1. 시/도 이름이 주소에 있는 경우
    # =====================================================

    aliases = REGION_ALIASES.get(
        region
    )

    # 정식명으로 들어와도 약칭의 alias 사용
    if not aliases:

        aliases = REGION_ALIASES.get(
            normalized_region,
            [region],
        )

    for alias in aliases:

        alias = str(alias).strip()

        if not alias:
            continue

        # 주소가 시/도명만 있는 경우
        query |= Q(
            occurred_location__iexact=alias
        )

        # 주소가 시/도로 시작
        query |= Q(
            occurred_location__istartswith=(
                f"{alias} "
            )
        )

    # =====================================================
    # 2. 시/도가 없는 주소
    #
    # 전국에서 해당 시군구가 한 시도에만 존재하는 경우에만
    # 지역 필터에 포함
    # =====================================================

    for sigungu, sigungu_region in (
        UNIQUE_SIGUNGU_TO_REGION.items()
    ):

        if sigungu_region != normalized_region:
            continue

        query |= Q(
            occurred_location__iexact=sigungu
        )

        query |= Q(
            occurred_location__istartswith=(
                f"{sigungu} "
            )
        )

    return query

def apply_category_filter(qs, category):
    """
    카드에 표시되는 분류명과 실제 DB 값을 맞춰서 필터링한다.
    """
    if not category:
        return qs

    category = str(category).strip()

    if not category:
        return qs

    # 카드에서 '기타'로 표시되는 값들
    #
    # serializers.py 기준:
    # 아동 / 장애 / 치매 / 치매환자 외에는 기타 표시
    #
    # 따라서 가출인도 기타에 포함
    if category == "기타":
        return qs.exclude(
            category__in=[
                "아동",
                "장애",
                "치매",
                "치매환자",
            ]
        )

    aliases = CATEGORY_ALIASES.get(
        category,
        [category],
    )

    return qs.filter(
        category__in=aliases
    )
def reverse_geocode(lat, lng):
    """
    위도/경도를 주소 문자열로 변환.
    실패하면 None 반환.
    """

    if lat is None or lng is None:
        return None

    try:
        response = requests.get(
            "https://nominatim.openstreetmap.org/reverse",
            params={
                "lat": lat,
                "lon": lng,
                "format": "json",
                "accept-language": "ko",
                "zoom": 18,
            },
            headers={
                "User-Agent": "Dasibom/1.0"
            },
            timeout=3,
        )

        if response.status_code != 200:
            logger.warning(
                "[reverse_geocode] 응답 실패 "
                f"status={response.status_code}"
            )
            return None

        data = response.json()

        address = data.get("display_name")

        if address:
            return address.strip()

        return None

    except Exception as e:
        logger.warning(
            f"[reverse_geocode] 주소 변환 실패: {e}"
        )
        return None
def get_image_hash(image_path):
    try:
        img = Image.open(image_path)
        return str(imagehash.phash(img))
    except:
        return None

def is_similar_image(hash1, hash2):
    if not hash1 or not hash2:
        return False

    # 해밍 거리
    diff = imagehash.hex_to_hash(hash1) - imagehash.hex_to_hash(hash2)

    return diff < 10  # 🔥 기준 (작을수록 비슷)

def calculate_similarity(case, name, location, occurred_at):
    score = 0

    # 1️⃣ 이름 유사도
    existing_name = case.reported_missing_name or ""
    name_similarity = SequenceMatcher(None, existing_name, name).ratio()

    if name_similarity > 0.8:
        score += 40
    elif name_similarity > 0.6:
        score += 25

    # 2️⃣ 위치 유사도
    if case.occr_location and location:
        if location in case.occr_location or case.occr_location in location:
            score += 30

    # 3️⃣ 시간 유사도
    if case.occr_date and occurred_at:
        diff = abs(case.occr_date - occurred_at)

        if diff <= timedelta(hours=1):
            score += 30
        elif diff <= timedelta(hours=3):
            score += 15

    return score

def find_similar_cases(name, location, occurred_at):
    if not occurred_at:
        return []
    candidates = (
        Case.objects
        .filter(
            type_code=Case.TypeCode.MISSING,
            occr_date__range=(
                occurred_at - timedelta(hours=6),
                occurred_at + timedelta(hours=6)
            )
        )
        .exclude(
            status=Case.Status.REJECTED
        )
    )

    similar_cases = []

    for case in candidates:
        score = calculate_similarity(
            case,
            name,
            location,
            occurred_at
        )

        if score >= 60:
            similar_cases.append({
                "case_id": case.id,
                "score": score
            })

    return similar_cases
def find_similar_cases_from_candidates(
    name,
    location,
    occurred_at,
    candidates,
):
    if not occurred_at:
        return []

    start_time = occurred_at - timedelta(hours=6)
    end_time = occurred_at + timedelta(hours=6)

    similar_cases = []

    for case in candidates:
        if not case.occr_date:
            continue

        if not (
            start_time
            <= case.occr_date
            <= end_time
        ):
            continue

        score = calculate_similarity(
            case,
            name,
            location,
            occurred_at,
        )

        if score >= 60:
            similar_cases.append({
                "case_id": case.id,
                "score": score,
            })

    return similar_cases
CATEGORY_MAP = {
    "정상아동": "아동",
    "정상아동(18세 미만)": "아동",
    "정상아동(18세미만)": "아동",  # 추가

    "지적장애인": "장애",
    "지적장애인(18세미만)": "장애",
    "지적장애인(18세이상)": "장애",

    "시설보호무연고자": "장애",
    "치매질환자": "치매환자",
    "가출인": "가출인",

    "불상(기타)": "기타",
    "불상":"기타"
}


class PersonViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated]
    queryset = Person.objects.all()
    serializer_class = PersonSerializer

    # ------------------------------
    # 프로필 수정
    # ------------------------------
    @action(detail=False, methods=["put"], url_path="update-profile")
    def update_profile(self, request):

        person = request.user.person

        serializer = PersonSerializer(person, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)

        return Response(serializer.errors, status=400)

    # ------------------------------
    # 보호자 등록
    # ------------------------------
    @action(detail=False, methods=["post"], url_path="add-guardian")
    def add_guardian(self, request):
        guardian_id = request.data.get("guardian_id")
        ward_id = request.data.get("ward_id")
        relation = request.data.get("relation")

        guardian = Guardian.objects.create(
            guardian=request.user.person,
            ward_id=ward_id,
            relation=relation
        )

        return Response({
            "message": "보호자 관계 등록 완료",
            "data": GuardianSerializer(guardian).data
        })

    # ------------------------------
    # 내가 가진 피보호자 목록
    @action(detail=False, methods=["get"], url_path="my-wards")
    def my_wards(self, request):
        qs = Guardian.objects.filter(
            guardian=request.user.person
        ).select_related(
            "ward",
            "guardian",
            "ward__badge",
        )

        result = []

        for guardian in qs:
            ward = guardian.ward

            device = (
                getattr(ward, "badge", None)
                if ward
                else None
            )

            prevention = None
            if ward:
                prevention = PreventionRegistration.objects.filter(
                    linked_person=ward,
                    is_active=True
                ).prefetch_related("photos").order_by("-created_at").first()

            # 예방등록 사진 처리
            photos = []
            main_photo = None

            if prevention:
                for photo in prevention.photos.all():
                    image = getattr(photo, "image", None)

                    if not image:
                        continue

                    url = media_url(
                        image.name,
                        request,
                    )

                    item = {
                        "id": photo.id,
                        "url": url,
                        "image": image.name,
                        "photo_type": getattr(photo, "photo_type", None),
                        "validation_status": getattr(photo, "validation_status", None),
                        "validation_message": getattr(photo, "validation_message", None),
                        "validation_confidence": getattr(photo, "validation_confidence", None),
                    }

                    photos.append(item)

                    if main_photo is None:
                        main_photo = url

                    if getattr(photo, "photo_type", None) == "face":
                        main_photo = url

            # 예방등록 연결된 피보호자인 경우: PreventionRegistration 기준 응답
            if prevention:
                result.append({
                    "id": guardian.id,
                    "relation": guardian.relation,

                    "guardian": guardian.guardian.id if guardian.guardian else None,
                    "guardian_name": guardian.guardian.name if guardian.guardian else None,

                    "ward": ward.id if ward else None,
                    "ward_id": ward.id if ward else None,
                    "person_id": ward.id if ward else None,

                    "prevention_registration_id": prevention.id,

                    "ward_name": prevention.name,
                    "ward_gender": prevention.gender,
                    "ward_phone": prevention.phone,

                    "name": prevention.name,
                    "gender": prevention.gender,
                    "phone": prevention.phone,
                    "address": prevention.address,
                    "frequent_place": prevention.frequent_place,
                    "note": prevention.note,

                    "height": prevention.height,
                    "weight": prevention.weight,
                    "body_type": prevention.body_type,
                    "face_type": prevention.face_type,
                    "hair_color": prevention.hair_color,
                    "hair_style": prevention.hair_style,
                    "blood_type": prevention.blood_type,
                    "eye_color": prevention.eye_color,
                    "physical_feature": prevention.physical_feature,
                    "health_info": prevention.health_info,

                    "guardian_phone": prevention.guardian_phone,

                    "status": prevention.status,
                    "status_label": prevention.get_status_display(),

                    "photo": main_photo,
                    "main_photo": main_photo,
                    "photos": photos,
                    "photo_items": photos,

                    "device_code": (
                        device.device_uid
                        if device
                        else prevention.device_code
                    ),

                    "device_id": device.id if device else None,
                    "device_status": device.status if device else None,

                    "created_at": guardian.created_at,
                    "updated_at": guardian.updated_at,
                })

            # fallback: 기존 Person 기준
            else:
                age = None
                if ward and ward.birth:
                    from datetime import date
                    today = date.today()
                    age = today.year - ward.birth.year

                result.append({
                    "id": guardian.id,
                    "relation": guardian.relation,

                    "guardian": guardian.guardian.id if guardian.guardian else None,
                    "guardian_name": guardian.guardian.name if guardian.guardian else None,

                    "ward": ward.id if ward else None,
                    "ward_id": ward.id if ward else None,
                    "person_id": ward.id if ward else None,

                    "ward_name": ward.name if ward else None,
                    "ward_gender": ward.sex if ward else None,
                    "ward_age": age,
                    "ward_phone": ward.phone if ward else None,

                    "name": ward.name if ward else None,
                    "gender": ward.sex if ward else None,
                    "age": age,
                    "phone": ward.phone if ward else None,
                    "address": ward.address if ward else None,
                    "health_info": ward.health_info if ward else None,

                    "photo": None,
                    "main_photo": None,
                    "photos": [],
                    "photo_items": [],

                    "device_code": device.device_uid if device else None,
                    "device_id": device.id if device else None,
                    "device_status": device.status if device else None,

                    "created_at": guardian.created_at,
                    "updated_at": guardian.updated_at,
                })

        return Response(result)
    # ------------------------------
    # 나의 보호자 목록
    # ------------------------------
    @action(detail=False, methods=["get"], url_path="my-guardians")
    def my_guardians(self, request):
        qs = Guardian.objects.filter(
            ward=request.user.person
        )

        return Response(
            GuardianSerializer(qs, many=True).data
        )

    from datetime import date

    @action(detail=False, methods=["get"], url_path="my-wards/simple")
    def my_wards_simple(self, request):

        guardians = (
            Guardian.objects
            .filter(
                guardian=request.user.person
            )
            .select_related(
                "ward",
                "guardian",
                "ward__badge",
            )
            .prefetch_related(
                Prefetch(
                    "ward__linked_prevention_registrations",
                    queryset=(
                        PreventionRegistration.objects
                        .filter(is_active=True)
                        .prefetch_related("photos")
                        .order_by("-created_at")
                    ),
                    to_attr="active_preventions",
                )
            )
        )

        result = []

        def calculate_age_from_rrn(rrn_front, rrn_back):
            if not rrn_front or not rrn_back:
                return None

            rrn_front = str(rrn_front).strip()
            rrn_back = str(rrn_back).strip()

            if len(rrn_front) != 6 or not rrn_front.isdigit():
                return None

            if len(rrn_back) < 1 or not rrn_back[0].isdigit():
                return None

            gender_code = rrn_back[0]

            if gender_code in ["1", "2", "5", "6"]:
                century = 1900
            elif gender_code in ["3", "4", "7", "8"]:
                century = 2000
            elif gender_code in ["9", "0"]:
                century = 1800
            else:
                return None

            try:
                year = century + int(rrn_front[0:2])
                month = int(rrn_front[2:4])
                day = int(rrn_front[4:6])

                birth_date = date(
                    year,
                    month,
                    day,
                )

                today = timezone.localdate()

                if birth_date > today:
                    return None

                return (
                        today.year
                        - birth_date.year
                        - (
                                (today.month, today.day)
                                <
                                (birth_date.month, birth_date.day)
                        )
                )

            except (TypeError, ValueError):
                return None

        # -------------------------------------------------
        # 1. 피보호자/기기/예방등록 정보 정리
        # -------------------------------------------------
        guardian_rows = []
        device_codes = set()

        for guardian in guardians:
            ward = guardian.ward

            device = (
                getattr(ward, "badge", None)
                if ward
                else None
            )

            preventions = (
                getattr(
                    ward,
                    "active_preventions",
                    [],
                )
                if ward
                else []
            )

            prevention = (
                preventions[0]
                if preventions
                else None
            )

            device_code = None

            if device:
                device_code = device.device_uid

            elif prevention and prevention.device_code:
                device_code = prevention.device_code

            if device_code:
                device_codes.add(device_code)

            guardian_rows.append({
                "guardian": guardian,
                "ward": ward,
                "device": device,
                "prevention": prevention,
                "device_code": device_code,
            })

        # -------------------------------------------------
        # 2. GPS 최신 위치를 한 번에 조회
        # -------------------------------------------------
        gps_map = {
            gps.device_code: gps
            for gps in GPSLocation.objects.filter(
                device_code__in=device_codes
            )
        }

        # -------------------------------------------------
        # 3. 응답 생성
        # -------------------------------------------------
        for row in guardian_rows:
            guardian = row["guardian"]
            ward = row["ward"]
            device = row["device"]
            prevention = row["prevention"]
            device_code = row["device_code"]

            gps = (
                gps_map.get(device_code)
                if device_code
                else None
            )

            latest_location = None

            if gps:
                address = reverse_geocode(
                    gps.lat,
                    gps.lng,
                )

                latest_location = {
                    "lat": gps.lat,
                    "lng": gps.lng,
                    "address": address,
                    "timestamp": gps.timestamp,
                    "updated_at": gps.updated_at,
                }

            photos = []
            main_photo = None

            if prevention:
                for photo in prevention.photos.all():
                    image = getattr(
                        photo,
                        "image",
                        None,
                    )

                    if not image:
                        continue

                    url = media_url(
                        image.name,
                        request,
                    )

                    item = {
                        "id": photo.id,
                        "url": url,
                        "image": image.name,
                        "photo_type": getattr(
                            photo,
                            "photo_type",
                            None,
                        ),
                        "validation_status": getattr(
                            photo,
                            "validation_status",
                            None,
                        ),
                        "validation_message": getattr(
                            photo,
                            "validation_message",
                            None,
                        ),
                        "validation_confidence": getattr(
                            photo,
                            "validation_confidence",
                            None,
                        ),
                    }

                    photos.append(item)

                    if main_photo is None:
                        main_photo = url

                    if (
                            getattr(
                                photo,
                                "photo_type",
                                None,
                            )
                            == "face"
                    ):
                        main_photo = url

            # -------------------------------------------------
            # 예방등록 연결된 피보호자
            # -------------------------------------------------
            if prevention:
                age = calculate_age_from_rrn(
                    prevention.rrn_front,
                    prevention.rrn_back,
                )

                result.append({
                    # 기존 응답 유지
                    "id": guardian.id,
                    "relation": guardian.relation,

                    "guardian": (
                        guardian.guardian.id
                        if guardian.guardian
                        else None
                    ),
                    "guardian_name": (
                        guardian.guardian.name
                        if guardian.guardian
                        else None
                    ),

                    "ward": ward.id if ward else None,
                    "ward_id": ward.id if ward else None,
                    "person_id": ward.id if ward else None,

                    "prevention_registration_id": prevention.id,

                    "ward_name": prevention.name,
                    "ward_gender": prevention.gender,
                    "ward_age": age,
                    "ward_phone": prevention.phone,

                    "name": prevention.name,
                    "gender": prevention.gender,
                    "age": age,
                    "current_age": age,

                    # 새 필드
                    "rrn_front": prevention.rrn_front,
                    "rrn_back": prevention.rrn_back,
                    "category": prevention.category,
                    "category_label": (
                        prevention.get_category_display()
                        if prevention.category
                        else ""
                    ),

                    "phone": prevention.phone,
                    "address": prevention.address,
                    "frequent_place": prevention.frequent_place,
                    "note": prevention.note,

                    "height": prevention.height,
                    "weight": prevention.weight,
                    "body_type": prevention.body_type,
                    "face_type": prevention.face_type,
                    "hair_color": prevention.hair_color,
                    "hair_style": prevention.hair_style,
                    "blood_type": prevention.blood_type,
                    "eye_color": prevention.eye_color,
                    "physical_feature": prevention.physical_feature,
                    "health_info": prevention.health_info,

                    "guardian_phone": prevention.guardian_phone,

                    "status": prevention.status,
                    "status_label": prevention.get_status_display(),

                    "photo": main_photo,
                    "main_photo": main_photo,
                    "photos": photos,
                    "photo_items": photos,

                    "device_code": device_code,
                    "device_id": (
                        device.id
                        if device
                        else None
                    ),
                    "device_status": (
                        device.status
                        if device
                        else None
                    ),

                    # 새 필드
                    "latest_location": latest_location,

                    "created_at": guardian.created_at,
                    "updated_at": guardian.updated_at,
                })

            # -------------------------------------------------
            # 기존 Person fallback
            # -------------------------------------------------
            else:
                age = None

                if ward and getattr(
                        ward,
                        "birth",
                        None,
                ):
                    today = timezone.localdate()
                    birth_date = ward.birth

                    age = (
                            today.year
                            - birth_date.year
                            - (
                                    (today.month, today.day)
                                    <
                                    (
                                        birth_date.month,
                                        birth_date.day,
                                    )
                            )
                    )

                result.append({
                    # 기존 응답 유지
                    "id": guardian.id,
                    "relation": guardian.relation,

                    "guardian": (
                        guardian.guardian.id
                        if guardian.guardian
                        else None
                    ),
                    "guardian_name": (
                        guardian.guardian.name
                        if guardian.guardian
                        else None
                    ),

                    "ward": ward.id if ward else None,
                    "ward_id": ward.id if ward else None,
                    "person_id": ward.id if ward else None,

                    "prevention_registration_id": None,

                    "ward_name": (
                        ward.name
                        if ward
                        else None
                    ),
                    "ward_gender": (
                        ward.sex
                        if ward
                        else None
                    ),
                    "ward_age": age,
                    "ward_phone": (
                        ward.phone
                        if ward
                        else None
                    ),

                    "name": (
                        ward.name
                        if ward
                        else None
                    ),
                    "gender": (
                        ward.sex
                        if ward
                        else None
                    ),
                    "age": age,
                    "current_age": age,

                    # 새 필드
                    "rrn_front": None,
                    "rrn_back": None,
                    "category": "",
                    "category_label": "",

                    "phone": (
                        ward.phone
                        if ward
                        else None
                    ),
                    "address": (
                        ward.address
                        if ward
                        else None
                    ),
                    "health_info": (
                        ward.health_info
                        if ward
                        else None
                    ),

                    "photo": None,
                    "main_photo": None,
                    "photos": [],
                    "photo_items": [],

                    "device_code": device_code,
                    "device_id": (
                        device.id
                        if device
                        else None
                    ),
                    "device_status": (
                        device.status
                        if device
                        else None
                    ),

                    # 새 필드
                    "latest_location": latest_location,

                    "created_at": guardian.created_at,
                    "updated_at": guardian.updated_at,
                })

        return Response(result)
    @action(detail=True, methods=["get"], url_path="prefill")
    def prefill(self, request, pk=None):
        person = get_object_or_404(Person, pk=pk)

        # 🔐 보호자 확인
        is_guardian = Guardian.objects.filter(
            guardian=request.user.person,
            ward=person
        ).exists()

        if not is_guardian:
            return Response({"error": "접근 권한 없음"}, status=403)

        # 🔥 나이 계산
        age = None
        if person.birth:
            from datetime import date
            today = date.today()
            age = today.year - person.birth.year

        return Response({
            "name": person.name,
            "gender": person.sex,
            "age_at_missing": age,
        })
# ==========================================================
# 📌 전화번호 인증 요청 (전체 10회 제한 + 미확정 요청 5분 만료)
# ==========================================================
class PhoneAuthViewSet(viewsets.ViewSet):

    @action(detail=False, methods=["post"], url_path="request-code")
    def request_code(self, request):
        from django.conf import settings

        phone = request.data.get("phone")

        if not phone:
            return Response({"error": "phone 필수"}, status=400)

        today = datetime.now().date()

        total_requests_today = PhoneRequest.objects.filter(
            created_at__date=today
        ).count()

        if total_requests_today >= 10:
            return Response({
                "allowed": False,
                "message": "오늘 인증 요청 가능 횟수(전체 10회)를 초과했습니다.",
                "total_used": total_requests_today,
                "limit": 10
            }, status=429)

        PhoneRequest.objects.create(
            phone=phone,
            confirmed=False
        )

        # ✅ 개발/시연 모드
        if getattr(settings, "DEV_SKIP_PHONE_VERIFY", False):
            return Response({
                "allowed": True,
                "message": "개발 모드: 아무 인증번호나 입력해도 인증됩니다.",
                "verified": False,
                "dev_skip": True,
                "total_used": total_requests_today + 1,
                "limit": 10
            })

        # ✅ 운영 모드
        return Response({
            "allowed": True,
            "message": "인증번호 전송 가능 — Flutter에서 verifyPhoneNumber 실행하세요.",
            "verified": False,
            "dev_skip": False,
            "total_used": total_requests_today + 1,
            "limit": 10
        })

# ==========================================================
# USER AUTH
# ==========================================================
class UserAuthViewSet(viewsets.ModelViewSet):
    queryset = UserAuth.objects.all()
    serializer_class = UserAuthSerializer

    @action(detail=False, methods=["post"], url_path="logout", permission_classes=[IsAuthenticated])
    def logout(self, request):
        auth_header = request.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            token = auth_header.split(" ")[1]
            try:
                access = AccessToken(token)
                # 토큰 만료시간까지 블랙리스트에 저장
                exp = access["exp"]
                now = datetime.now().timestamp()
                ttl = int(exp - now)
                if ttl > 0:
                    cache.set(f"blacklist_{token}", "true", timeout=ttl)
            except Exception:
                pass

        return Response({"message": "로그아웃 완료"})
    # ------------------------------
    # Firebase 기반 회원가입
    # ------------------------------
    @action(detail=False, methods=["post"], url_path="firebase-signup")
    def firebase_signup(self, request):
        id_token = request.headers.get("Authorization")

        if not id_token:
            return Response({"error": "Firebase ID Token 필요"}, status=400)

        if id_token.startswith("Bearer "):
            id_token = id_token.replace("Bearer ", "").strip()

        try:
            decoded = firebase_auth.verify_id_token(id_token)
        except Exception:
            return Response({"error": "유효하지 않은 Firebase 토큰"}, status=401)

        firebase_uid = decoded["uid"]
        phone_from_firebase = decoded.get("phone_number")

        if UserAuth.objects.filter(firebase_uid=firebase_uid).exists():
            return Response({"error": "이미 가입된 사용자"}, status=400)

        email = request.data.get("email")
        name = request.data.get("name")
        birth = request.data.get("birth")
        sex_raw = request.data.get("sex")
        password = request.data.get("password")

        sex_map = {"남자": "male", "여자": "female", "기타": "unknown"}
        sex = sex_map.get(sex_raw, "unknown")

        if UserAuth.objects.filter(email=email).exists():
            return Response({"error": "이미 존재하는 이메일"}, status=400)

        person = Person.objects.create(
            name=name,
            birth=birth,
            sex=sex,
            phone=phone_from_firebase
        )

        user = UserAuth.objects.create(
            person=person,
            firebase_uid=firebase_uid,
            email=email,
            password=make_password(password),
            is_approved=True
        )

        # -----------------------------------------------------
        # 🔥 전화번호 인증 성공 처리 (3분 제한)
        # -----------------------------------------------------
        pending = PhoneRequest.objects.filter(
            phone=phone_from_firebase,
            confirmed=False
        ).order_by("-created_at").first()

        if not pending:
            return Response({"error": "인증 요청 기록 없음. 다시 시도해주세요."}, status=400)

        # 🔥 3분(180초) 유효시간 체크
        elapsed = (timezone.now() - pending.created_at).total_seconds()
        if elapsed > 180:
            return Response({
                "error": "인증번호가 만료되었습니다. 3분 안에 다시 요청해주세요."
            }, status=400)

        # Firebase 인증 성공 처리
        pending.confirmed = True
        pending.save()

        today = datetime.now().date()
        PhoneLog.objects.create(
            phone=phone_from_firebase,
            date=today
        )
        return Response({
            "message": "회원가입 완료",
            "user": UserAuthSerializer(user).data
        }, status=201)

    # ------------------------------
    # 일반 회원가입
    # ------------------------------
    @action(detail=False, methods=["post"], url_path="signup")
    def signup(self, request):

        email = request.data.get("email")
        password = request.data.get("password")
        password_confirm = request.data.get("password_confirm")
        name = request.data.get("name")
        birth = request.data.get("birth")
        sex = request.data.get("sex")
        phone = request.data.get("phone")

        # ------------------------------
        # 1️⃣ 필수값 체크
        # ------------------------------
        if not all([email, password, password_confirm, name]):
            return Response({"error": "필수 항목 누락"}, status=400)

        # ------------------------------
        # 2️⃣ 비밀번호 일치 확인
        # ------------------------------
        if password != password_confirm:
            return Response({"error": "비밀번호가 일치하지 않습니다."}, status=400)

        # ------------------------------
        # 3️⃣ 이메일 중복 체크
        # ------------------------------
        if UserAuth.objects.filter(email=email).exists():
            return Response({"error": "이미 존재하는 이메일입니다."}, status=400)

        # ------------------------------
        # 4️⃣ Person 생성
        # ------------------------------
        person = Person.objects.create(
            name=name,
            birth=birth,
            sex=sex if sex in ["male", "female"] else "unknown",
            phone=phone,
        )

        # ------------------------------
        # 5️⃣ UserAuth 생성
        # ------------------------------
        user = UserAuth.objects.create(
            person=person,
            email=email,
            password=make_password(password),
            is_approved=True
        )

        return Response({
            "message": "회원가입 완료",
            "user_id": user.id,
            "email": user.email
        }, status=201)

    # ------------------------------
    # 일반 로그인
    # ------------------------------
    @action(detail=False, methods=["post"], url_path="login")
    def login(self, request):
        email = request.data.get("email")
        password = request.data.get("password")
        print(request.data)
        try:
            user = UserAuth.objects.get(email=email)
        except UserAuth.DoesNotExist:
            return Response({"error": "존재하지 않는 이메일"}, status=400)

        if not check_password(password, user.password):
            return Response({"error": "비밀번호 오류"}, status=400)

        refresh = RefreshToken.for_user(user)
        refresh["user_id"] = user.id
        refresh["email"] = user.email
        refresh["role"] = user.role
        return Response({
            "message": "로그인 성공",
            "refresh": str(refresh),
            "access": str(refresh.access_token),
            "user": UserAuthSerializer(user).data
        })

    @action(detail=False, methods=["get"], url_path="whoami",    permission_classes=[IsAuthenticated])
    def whoami(self, request):
        return Response({
            "user": str(request.user),
            "type": str(type(request.user)),
            "is_authenticated": request.user.is_authenticated,
            "role": request.user.role,  # ← 이거 추가하면 "guest" 뜸
        })
    # ------------------------------
    # 카카오 로그인
    # ------------------------------
    @action(detail=False, methods=["post"], url_path="kakao-login")
    def kakao_login(self, request):
        import requests

        access_token = request.data.get("access_token")

        if not access_token:
            return Response({"error": "access_token 필요"}, status=400)

        kakao_url = "https://kapi.kakao.com/v2/user/me"
        headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
        }

        kakao_response = requests.get(kakao_url, headers=headers)

        if kakao_response.status_code != 200:
            return Response({"error": "카카오 토큰 유효하지 않음"}, status=401)

        kakao_data = kakao_response.json()
        kakao_uid = str(kakao_data["id"])
        kakao_account = kakao_data.get("kakao_account", {})
        profile = kakao_account.get("profile", {})

        email = kakao_account.get("email")
        nickname = profile.get("nickname")

        user = UserAuth.objects.filter(kakao_uid=kakao_uid).first()

        if not user:
            person = Person.objects.create(
                name=nickname,
                sex="unknown",
                birth=None,
                phone=None,
            )

            user = UserAuth.objects.create(
                person=person,
                kakao_uid=kakao_uid,
                email=email,
                password=None,
                is_approved=True,
            )

        refresh = RefreshToken.for_user(user)

        return Response({
            "message": "카카오 로그인 성공",
            "refresh": str(refresh),
            "access": str(refresh.access_token),
            "user": UserAuthSerializer(user).data
        })

    @action(detail=False, methods=["get"], url_path="me", permission_classes=[IsAuthenticated])
    def me(self, request):
        user = request.user
        return Response({
            "id": user.id,
            "email": user.email,
            "role": user.role,
            "is_approved": user.is_approved,
            "person": PersonSerializer(user.person).data
        })
    #게스트 로그인
    @action(detail=False, methods=["post"], url_path="guest-login")
    def guest_login(self, request):

        # 1️⃣ Guest용 Person 생성
        person = Person.objects.create(
            name="Guest",
        )

        # 2️⃣ Guest용 UserAuth 생성
        user = UserAuth.objects.create(
            person=person,
            email=None,
            password=None,
            role=UserAuth.Role.GUEST,
            is_approved=True
        )

        # 3️⃣ JWT 발급
        refresh = RefreshToken.for_user(user)

        return Response({
            "message": "게스트 로그인 성공",
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "role": "guest"
        }, status=200)


# ==========================================================
# 나머지 모델 기본 CRUD
# ==========================================================
class GuardianViewSet(viewsets.ModelViewSet):
    queryset = Guardian.objects.all()
    serializer_class = GuardianSerializer

class AdminUserViewSet(viewsets.ViewSet):
    permission_classes = [IsAdmin]

    # ------------------------------
    # 1️⃣ 전체 사용자 목록
    # ------------------------------
    def list(self, request):
        qs = UserAuth.objects.select_related("person").all().order_by("-id")

        data = []
        for user in qs:
            data.append({
                "id": user.id,
                "email": user.email,
                "role": user.role,
                "is_approved": user.is_approved,
                "name": user.person.name if user.person else None,
                "phone": user.person.phone if user.person else None,
            })

        return Response(data)

    # ------------------------------
    # 2️⃣ 사용자 상세
    # ------------------------------
    def retrieve(self, request, pk=None):
        user = get_object_or_404(UserAuth, pk=pk)

        return Response({
            "id": user.id,
            "email": user.email,
            "role": user.role,
            "is_approved": user.is_approved,
            "person": {
                "name": user.person.name,
                "phone": user.person.phone,
                "birth": user.person.birth,
                "sex": user.person.sex,
                "address": user.person.address,
            }
        })

    # ------------------------------
    # 3️⃣ 사용자 정지 / 활성화
    # ------------------------------
    @action(detail=True, methods=["patch"])
    def ban(self, request, pk=None):
        user = get_object_or_404(UserAuth, pk=pk)

        user.is_approved = False
        user.save(update_fields=["is_approved"])

        return Response({
            "message": "사용자 정지 완료",
            "user_id": user.id
        })

    @action(detail=True, methods=["patch"])
    def unban(self, request, pk=None):
        user = get_object_or_404(UserAuth, pk=pk)

        user.is_approved = True
        user.save(update_fields=["is_approved"])

        return Response({
            "message": "사용자 활성화 완료",
            "user_id": user.id
        })

    # ------------------------------
    # 4️⃣ 역할 변경
    # ------------------------------
    @action(detail=True, methods=["patch"])
    def role(self, request, pk=None):
        user = get_object_or_404(UserAuth, pk=pk)

        new_role = request.data.get("role")

        allowed_roles = [r[0] for r in UserAuth.Role.choices]

        if new_role not in allowed_roles:
            return Response({
                "error": f"허용되지 않은 role. {allowed_roles}"
            }, status=400)

        user.role = new_role
        user.save(update_fields=["role"])

        return Response({
            "message": "권한 변경 완료",
            "user_id": user.id,
            "role": user.role
        })
class DeviceViewSet(viewsets.ModelViewSet):
    queryset = Device.objects.all()
    serializer_class = DeviceSerializer
    permission_classes = [IsAuthenticated]  # 🔥 추가

    # =====================================================
    # NFC badge UID 자동 등록
    # POST /dasibom/device/register-badge/
    # =====================================================
    @action(
        detail=False,
        methods=["post"],
        url_path="register-badge",
        permission_classes=[AllowAny],
    )
    def register_badge(self, request):

        # ---------------------------------------------
        # 1. 하드웨어 등록키 확인
        # ---------------------------------------------
        register_key = request.headers.get(
            "X-Device-Register-Key",
            ""
        )

        expected_key = getattr(
            settings,
            "DEVICE_REGISTER_KEY",
            ""
        )

        if (
                not expected_key
                or register_key != expected_key
        ):
            return Response(
                {
                    "status": "error",
                    "message": "등록 권한이 없습니다."
                },
                status=status.HTTP_403_FORBIDDEN
            )

        # ---------------------------------------------
        # 2. 요청값
        # ---------------------------------------------
        device_code = request.data.get("device_code")
        badge_uid = request.data.get("badge_uid")

        if not device_code or not badge_uid:
            return Response(
                {
                    "status": "error",
                    "message": "device_code와 badge_uid가 필요합니다."
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        # ---------------------------------------------
        # 3. UID 정규화
        # 04:A2-B3... → 04a2b3...
        # ---------------------------------------------
        uid = (
            str(badge_uid)
            .strip()
            .lower()
            .replace(":", "")
            .replace("-", "")
        )

        if not uid:
            return Response(
                {
                    "status": "error",
                    "message": "badge_uid가 올바르지 않습니다."
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        # ---------------------------------------------
        # 4. Device 조회
        # API에서는 device_code지만
        # Device 모델 내부 필드는 device_uid 사용
        # ---------------------------------------------
        device = Device.objects.filter(
            device_uid=device_code
        ).first()

        if device is None:
            return Response(
                {
                    "status": "error",
                    "message": "등록되지 않은 기기입니다."
                },
                status=status.HTTP_404_NOT_FOUND
            )

        # ---------------------------------------------
        # 5. 이 UID가 다른 Device에 이미 등록됐는지 확인
        # ---------------------------------------------
        duplicated_device = (
            Device.objects
            .filter(badge_uid=uid)
            .exclude(pk=device.pk)
            .first()
        )

        if duplicated_device:
            return Response(
                {
                    "status": "error",
                    "message": "이미 다른 기기에 등록된 뱃지입니다."
                },
                status=status.HTTP_409_CONFLICT
            )

        # ---------------------------------------------
        # 6. 이미 같은 UID라면 그대로 성공 처리
        # 재부팅/재전송에도 오류 안 나게 idempotent 처리
        # ---------------------------------------------
        if device.badge_uid == uid:
            return Response(
                {
                    "status": "success",
                    "message": "이미 등록된 뱃지입니다.",
                    "device_code": device.device_uid,
                    "badge_uid": device.badge_uid,
                    "created": False,
                },
                status=status.HTTP_200_OK
            )

        # ---------------------------------------------
        # 7. 다른 UID가 이미 붙은 기기는 자동 덮어쓰기 금지
        # ---------------------------------------------
        if device.badge_uid:
            return Response(
                {
                    "status": "error",
                    "message": "해당 기기에는 이미 다른 뱃지가 등록되어 있습니다."
                },
                status=status.HTTP_409_CONFLICT
            )

        # ---------------------------------------------
        # 8. 최초 자동 등록
        # ---------------------------------------------
        device.badge_uid = uid
        device.save(
            update_fields=["badge_uid"]
        )

        return Response(
            {
                "status": "success",
                "message": "뱃지 등록 완료",
                "device_code": device.device_uid,
                "badge_uid": device.badge_uid,
                "created": True,
            },
            status=status.HTTP_201_CREATED
        )

    @action(detail=False, methods=["post"], url_path="update-location")
    def update_location(self, request):
        device_uid = request.data.get("device_uid")
        lat = request.data.get("lat")
        lon = request.data.get("lon")


        device = Device.objects.get(device_uid=device_uid)

        device.lat = lat
        device.lon = lon
        device.last_signal_time = timezone.now()
        device.save()

        return Response({"message": "location updated"})

    @action(detail=False, methods=["post"], url_path="nfc-tag")
    def nfc_tag(self, request):
        device_uid = request.data.get("device_uid")
        location = request.data.get("location", "알 수 없음")

        device = Device.objects.get(device_uid=device_uid)

        device.nfc_tag = True
        device.save()

        Interaction.objects.create(
            to_person=device.person,
            type="nfc_tag",
            start_time=timezone.now(),
            location=location,
            result="success"
        )

        return Response({"message": "tag recorded"})

    @action(detail=True, methods=["get"], url_path="location")
    def location(self, request, pk=None):
        device = self.get_object()

        return Response({
            "lat": device.lat,
            "lon": device.lon,
            "last_signal_time": device.last_signal_time
        })

    @action(detail=True, methods=["get"], url_path="logs")
    def logs(self, request, pk=None):
        device = self.get_object()

        logs = Interaction.objects.filter(
            to_person=device.person
        ).order_by("-start_time")[:10]

        return Response([
            {
                "type": log.type,
                "location": log.location,
                "time": log.start_time
            }
            for log in logs
        ])



class CaseViewSet(viewsets.ModelViewSet):
    queryset = Case.objects.all()
    serializer_class = CaseSerializer

    #제보들 보기
    @action(detail=False, methods=["get"], url_path="tips")
    def tip_list(self, request):
        queryset = Case.objects.filter(
            type_code=Case.TypeCode.TIP
        ).select_related(
            "reporter",
            "missing_person"
        ).prefetch_related(
            "features",
            "photos"
        )
        serializer = TipListSerializer(
            queryset,
            many=True,
            context={"request": request}
        )
        return Response(serializer.data)

    @action(detail=False, methods=["get"], url_path="tips/admin",    permission_classes=[IsAdmin]
)
    def admin_tip_list(self, request):

        queryset = (
            Case.objects
            .filter(
                type_code=Case.TypeCode.TIP
            )
            .select_related(
                "reporter",
                "missing_person"
            )
            .prefetch_related(
                "features",
                "photos"
            )
        )

        # -------------------------
        # status 필터
        # -------------------------
        status_param = request.GET.get("status")

        if status_param:
            queryset = queryset.filter(
                status=status_param
            )

        # -------------------------
        # 특정 실종자 필터
        # -------------------------
        missing_seq = request.GET.get("missing_seq")

        if missing_seq:
            queryset = queryset.filter(
                missing_person__msspsn_idntfccd=missing_seq
            )

        # -------------------------
        # 이름 검색
        # -------------------------
        keyword = request.GET.get("keyword")

        if keyword:
            queryset = queryset.filter(
                Q(
                    reported_missing_name__icontains=keyword
                )
            )

        # -------------------------
        # 최신순 정렬
        # -------------------------
        queryset = queryset.order_by(
            "-created_at"
        )

        # =====================================================
        # 성능 개선:
        # 유사 신고 후보를 case마다 조회하지 않고
        # 한 번만 DB에서 조회
        # =====================================================
        similar_candidates = list(
            Case.objects
            .filter(
                type_code=Case.TypeCode.MISSING
            )
            .exclude(
                status=Case.Status.REJECTED
            )
            .only(
                "id",
                "reported_missing_name",
                "occr_location",
                "occr_date",
            )
        )

        data = []

        for case in queryset:

            serialized = AdminTipSerializer(
                case,
                context={
                    "request": request
                }
            ).data

            if (
                    case.reported_missing_name
                    and case.occr_location
                    and case.occr_date
            ):
                similar_cases = (
                    find_similar_cases_from_candidates(
                        name=case.reported_missing_name,
                        location=case.occr_location,
                        occurred_at=case.occr_date,
                        candidates=similar_candidates,
                    )
                )

            else:
                similar_cases = []

            # 프론트 필드명 유지
            serialized["similar_cases"] = (
                similar_cases
            )

            data.append(
                serialized
            )

        return Response(data)

    @action(
        detail=False,
        methods=["get"],
        url_path="reports/admin",
        permission_classes=[IsAdmin]
    )
    def admin_report_list(self, request):
        """
        GET /dasibom/case/reports/admin/

        관리자용 실종 신고 목록 조회

        Query Params:
        - status
        - keyword

        프론트 응답 구조는 기존 그대로 유지
        """

        queryset = (
            Case.objects
            .filter(
                type_code=Case.TypeCode.MISSING
            )
            .select_related(
                "reporter",
                "missing_person"
            )
            .prefetch_related(
                "photos"
            )
        )

        # -------------------------
        # 상태 필터
        # -------------------------
        status_param = request.GET.get(
            "status"
        )

        if status_param:
            queryset = queryset.filter(
                status=status_param
            )

        # -------------------------
        # 검색 필터
        # -------------------------
        keyword = request.GET.get(
            "keyword"
        )

        if keyword:
            queryset = queryset.filter(
                Q(
                    reported_missing_name__icontains=keyword
                )
                | Q(
                    occr_location__icontains=keyword
                )
                | Q(
                    description__icontains=keyword
                )
                | Q(
                    payload__reporter_name__icontains=keyword
                )
                | Q(
                    payload__reporter_phone__icontains=keyword
                )
                | Q(
                    payload__name__icontains=keyword
                )
            )

        queryset = queryset.order_by(
            "-created_at"
        )

        # =====================================================
        # 성능 개선:
        # 유사 신고 후보를 한 번만 조회
        # =====================================================
        similar_candidates = list(
            Case.objects
            .filter(
                type_code=Case.TypeCode.MISSING
            )
            .exclude(
                status=Case.Status.REJECTED
            )
            .only(
                "id",
                "reported_missing_name",
                "occr_location",
                "occr_date",
            )
        )

        data = []

        for case in queryset:

            payload = case.payload or {}

            reporter_name = (
                case.reporter.name
                if case.reporter
                else payload.get(
                    "reporter_name"
                )
            )

            reporter_phone = (
                case.reporter.phone
                if case.reporter
                else payload.get(
                    "reporter_phone"
                )
            )

            # =================================================
            # 이미 prefetch된 사진을 메모리에서 한 번만 사용
            # =================================================
            case_photos = [
                photo
                for photo in case.photos.all()
                if photo.image
            ]

            subject_photos = [
                photo
                for photo in case_photos
                if (
                        photo.photo_type
                        == TipPhoto.PhotoType.SUBJECT
                )
            ]

            item = {
                "id": case.id,
                "case_id": case.id,

                "created_at": (
                    format_datetime_for_front(
                        case.created_at
                    )
                ),

                "updated_at": (
                    format_datetime_for_front(
                        case.updated_at
                    )
                ),

                "type_code":
                    case.type_code,

                "status":
                    case.status,

                "reported_missing_name":
                    case.reported_missing_name,

                "occr_date": (
                    format_datetime_for_front(
                        case.occr_date
                    )
                ),

                "occr_location":
                    case.occr_location,

                "description":
                    case.description,

                "reporter_name":
                    reporter_name,

                "reporter_phone":
                    reporter_phone,

                "missing_person_id": (
                    case.missing_person.id
                    if case.missing_person
                    else None
                ),

                "missing_person_seq": (
                    case.missing_person.msspsn_idntfccd
                    if case.missing_person
                    else None
                ),

                "missing_person_name": (
                    case.missing_person.name
                    if case.missing_person
                    else None
                ),

                "payload":
                    payload,

                # 프론트 응답 필드명 그대로
                "photos": [
                    media_url(
                        photo.image.name,
                        request,
                    )
                    for photo
                    in subject_photos
                ],

                # 프론트 응답 필드명 그대로
                "photo_items": [
                    {
                        "id":
                            photo.id,

                        "url":
                            media_url(
                                photo.image.name,
                                request,
                            ),

                        "image":
                            photo.image.name,

                        "photo_type":
                            photo.photo_type,

                        "is_ai_generated":
                            photo.is_ai_generated,

                        "uploaded_at": (
                            timezone.localtime(
                                photo.uploaded_at
                            ).isoformat()
                            if photo.uploaded_at
                            else None
                        ),
                    }
                    for photo
                    in case_photos
                ],
            }

            # =================================================
            # 유사 신고 계산
            # DB 재조회 없이 위에서 가져온 후보 사용
            # =================================================
            try:

                if (
                        case.reported_missing_name
                        and case.occr_location
                        and case.occr_date
                ):

                    item["similar_cases"] = (
                        find_similar_cases_from_candidates(
                            name=case.reported_missing_name,
                            location=case.occr_location,
                            occurred_at=case.occr_date,
                            candidates=similar_candidates,
                        )
                    )

                else:
                    item["similar_cases"] = []

            except Exception:
                item["similar_cases"] = []

            data.append(
                item
            )

        return Response(
            data,
            status=status.HTTP_200_OK
        )
    @action(
        detail=True,
        methods=["patch"],
        url_path="update-case",
        permission_classes=[IsAuthenticated],
    )
    def edit_case(self, request, pk=None):
        print("\n\n========== [edit_case] 제보/신고 수정 API 호출 ==========")
        print("[1] 요청 기본 정보")
        print("request.method:", request.method)
        print("request.path:", request.path)
        print("case_id(pk):", pk)
        print("content_type:", request.content_type)
        print("request.user:", request.user)
        print("request.user.is_authenticated:", request.user.is_authenticated)
        print("request.user.role:", getattr(request.user, "role", None))
        print("request.user.person:", getattr(request.user, "person", None))
        print("======================================================\n")

        case = get_object_or_404(Case, pk=pk)

        print("[2] 수정 대상 Case 조회 완료")
        print("case.id:", case.id)
        print("case.type_code:", case.type_code)
        print("case.status:", case.status)
        print("case.reporter:", case.reporter)
        print("case.reported_missing_name:", case.reported_missing_name)
        print("case.occr_location:", case.occr_location)
        print("case.occr_date:", case.occr_date)
        print("case.payload BEFORE:", case.payload)
        print("======================================================\n")

        # -------------------------------------------------
        # 1. 권한 체크: 관리자 또는 본인
        # -------------------------------------------------
        is_admin = getattr(request.user, "role", None) == "admin"
        is_owner = (
                hasattr(request.user, "person")
                and case.reporter == request.user.person
        )

        print("[3] 권한 체크")
        print("is_admin:", is_admin)
        print("is_owner:", is_owner)
        print("case.reporter == request.user.person:", case.reporter == getattr(request.user, "person", None))
        print("======================================================\n")

        if not (is_admin or is_owner):
            print("[권한 실패] 본인 또는 관리자가 아님")
            return Response(
                {"error": "본인 또는 관리자만 수정할 수 있습니다."},
                status=status.HTTP_403_FORBIDDEN
            )

        # -------------------------------------------------
        # 2. 상태 체크
        # 관리자: 모든 상태 수정 가능
        # 일반 사용자: received 상태에서만 수정 가능
        # -------------------------------------------------
        print("[4] 상태 수정 가능 여부 체크")
        print("현재 case.status:", case.status)
        print("관리자 여부:", is_admin)
        print("일반 사용자 수정 가능 상태(received) 여부:", case.status == Case.Status.RECEIVED)
        print("======================================================\n")

        if not is_admin:

            if case.type_code == Case.TypeCode.TIP:
                allowed_statuses = [
                    Case.Status.RECEIVED,
                    Case.Status.COMPLETED,
                ]

            elif case.type_code == Case.TypeCode.MISSING:
                allowed_statuses = [
                    Case.Status.RECEIVED,
                ]

            else:
                allowed_statuses = []

            if case.status not in allowed_statuses:
                return Response(
                    {
                        "error": "현재 상태에서는 수정할 수 없습니다."
                    },
                    status=status.HTTP_400_BAD_REQUEST
                )

        # 정상이라면 여기부터 계속 실행
        data = request.data
        changed_case_fields = []



        # -------------------------------------------------
        # 프론트에서 보낸 값 확인
        # -------------------------------------------------
        print("[5] 프론트에서 넘어온 request.data 확인")
        print("request.data type:", type(data))
        print("request.data keys:", list(data.keys()))

        for key in data.keys():
            try:
                print(f"DATA[{key}] =", data.get(key))
            except Exception as e:
                print(f"DATA[{key}] 출력 실패:", e)

        print("------------------------------------------------------")
        print("[6] 프론트에서 넘어온 request.FILES 확인")
        print("request.FILES keys:", list(request.FILES.keys()))

        for file_key in request.FILES.keys():
            files = request.FILES.getlist(file_key)
            print(f"FILES[{file_key}] count:", len(files))

            for idx, file in enumerate(files, start=1):
                print(f"  - {file_key}[{idx}].name:", file.name)
                print(f"  - {file_key}[{idx}].size:", file.size)
                print(f"  - {file_key}[{idx}].content_type:", getattr(file, "content_type", None))

        print("======================================================\n")

        # -------------------------------------------------
        # A. 공통 Case 필드 수정
        # -------------------------------------------------
        print("[7] A. 공통 Case 필드 수정 시작")

        case_field_map = {
            "reported_missing_name": "reported_missing_name",
            "occr_location": "occr_location",
            "description": "description",
        }

        for req_key, model_field in case_field_map.items():
            if req_key in data:
                old_value = getattr(case, model_field)
                new_value = data.get(req_key)

                print(f"[공통 필드 변경] {model_field}: {old_value} -> {new_value}")

                setattr(case, model_field, new_value)

                if model_field not in changed_case_fields:
                    changed_case_fields.append(model_field)

        # 공통 occr_date 처리
        if "occr_date" in data and data.get("occr_date"):
            print("[공통 날짜 처리] occr_date 수신:", data.get("occr_date"))

            try:
                raw = data.get("occr_date")
                parsed = parse_datetime(raw) if isinstance(raw, str) else None

                print("parsed occr_date:", parsed)

                if parsed is None:
                    print("[날짜 오류] occr_date parse 실패")
                    return Response(
                        {"error": "occr_date 형식이 올바르지 않습니다. ISO-8601 형식이어야 합니다."},
                        status=status.HTTP_400_BAD_REQUEST
                    )

                print(f"[공통 날짜 변경] case.occr_date: {case.occr_date} -> {parsed}")
                case.occr_date = parsed

                if "occr_date" not in changed_case_fields:
                    changed_case_fields.append("occr_date")

            except Exception as e:
                print("[날짜 예외] occr_date 처리 중 오류:", e)
                return Response(
                    {"error": "occr_date 형식이 올바르지 않습니다."},
                    status=status.HTTP_400_BAD_REQUEST
                )

        print("changed_case_fields after common:", changed_case_fields)
        print("======================================================\n")

        # -------------------------------------------------
        # B. type_code별 payload 수정
        # -------------------------------------------------
        payload = case.payload or {}

        print("[8] B. type_code별 payload 수정 시작")
        print("case.type_code:", case.type_code)
        print("payload BEFORE:", payload)
        print("======================================================\n")

        if case.type_code == Case.TypeCode.MISSING:
            print("[8-1] 실종 신고 수정 분기 진입")

            payload_fields = [
                "name",
                "gender",
                "age_at_missing",
                "category",
                "nationality",
                "height",
                "weight",
                "body_type",
                "face_type",
                "hair_color",
                "hair_style",
                "clothing",
                "occurred_at",
                "occurred_location",
                "description",
                "reporter_name",
                "reporter_phone",

                # ✅ 카테고리형 추가 정보
                "physical",
                "health",
                "behavior",
                "etc",
            ]

            print("payload_fields:", payload_fields)

            for field in payload_fields:
                if field in data:
                    old_value = payload.get(field)
                    new_value = data.get(field)
                    print(f"[payload 변경 - missing] {field}: {old_value} -> {new_value}")
                    payload[field] = new_value

            # -------------------------------------------------
            # physical / clothing 문자열을 실제 개별 필드로 동기화
            #
            # 수정 화면에서는 기존 값을 누적하는 게 아니라
            # 해당 영역 전체를 새 값으로 교체한다.
            # -------------------------------------------------

            def split_edit_items(value):
                if value is None:
                    return []

                if isinstance(value, (list, tuple)):
                    raw_items = value
                else:
                    text = str(value).strip()

                    if not text:
                        return []

                    # JSON 배열 문자열 대응
                    if text.startswith("["):
                        try:
                            parsed = json.loads(text)

                            if isinstance(parsed, list):
                                raw_items = parsed
                            else:
                                raw_items = [text]

                        except Exception:
                            raw_items = [text]

                    else:
                        # 줄바꿈 / 쉼표 모두 대응
                        text = (
                            text
                            .replace("\r\n", "\n")
                            .replace("\r", "\n")
                            .replace("，", ",")
                            .replace("\n", ",")
                        )

                        raw_items = text.split(",")

                result = []

                for item in raw_items:
                    item = str(item).strip()

                    if item and item not in result:
                        result.append(item)

                return result

            # =================================================
            # 신체 특징
            # =================================================
            if "physical" in data:

                physical_items = split_edit_items(
                    data.get("physical")
                )

                # ★ 기존 값 먼저 제거
                # 수정 전 값이 남아 같이 표시되는 문제 방지
                payload["height"] = ""
                payload["weight"] = ""
                payload["body_type"] = ""
                payload["face_type"] = ""

                other_physical = []

                for item in physical_items:

                    if item.startswith("키"):
                        payload["height"] = (
                            item.replace("키", "", 1).strip()
                        )

                    elif item.startswith("몸무게"):
                        payload["weight"] = (
                            item.replace("몸무게", "", 1).strip()
                        )

                    elif item.startswith("체격"):
                        payload["body_type"] = (
                            item.replace("체격", "", 1).strip()
                        )

                    elif item.startswith("얼굴형"):
                        payload["face_type"] = (
                            item.replace("얼굴형", "", 1).strip()
                        )

                    else:
                        # "발이 커요" 같은 자유 입력값
                        other_physical.append(item)

                # 구조화되지 않은 신체 특징만 physical에 남김
                payload["physical"] = "\n".join(
                    other_physical
                )

            # =================================================
            # 착의·외형 정보
            # =================================================
            if "clothing" in data:

                clothing_items = split_edit_items(
                    data.get("clothing")
                )

                # ★ 기존 두발 정보 제거
                payload["hair_color"] = ""
                payload["hair_style"] = ""

                other_clothing = []

                for item in clothing_items:

                    if item.startswith("두발색상"):
                        payload["hair_color"] = (
                            item
                            .replace("두발색상", "", 1)
                            .strip()
                        )

                    elif item.startswith("두발형태"):
                        payload["hair_style"] = (
                            item
                            .replace("두발형태", "", 1)
                            .strip()
                        )

                    else:
                        other_clothing.append(item)

                # 실제 의상 정보만 clothing에 저장
                payload["clothing"] = "\n".join(
                    other_clothing
                )
            # 대표 이름 동기화
            if "name" in data:
                print(f"[Case 이름 동기화] reported_missing_name: {case.reported_missing_name} -> {data.get('name')}")
                case.reported_missing_name = data.get("name")

                if "reported_missing_name" not in changed_case_fields:
                    changed_case_fields.append("reported_missing_name")

            # 발생 장소 동기화
            if "occurred_location" in data:
                print(f"[Case 장소 동기화] occr_location: {case.occr_location} -> {data.get('occurred_location')}")
                case.occr_location = data.get("occurred_location")

                if "occr_location" not in changed_case_fields:
                    changed_case_fields.append("occr_location")

            # 발생 일시 동기화
            if "occurred_at" in data and data.get("occurred_at"):
                print("[missing 날짜 처리] occurred_at 수신:", data.get("occurred_at"))

                try:
                    raw = data.get("occurred_at")
                    parsed = parse_datetime(raw) if isinstance(raw, str) else None

                    print("parsed occurred_at:", parsed)

                    if parsed is None:
                        print("[날짜 오류] occurred_at parse 실패")
                        return Response(
                            {"error": "occurred_at 형식이 올바르지 않습니다. ISO-8601 형식이어야 합니다."},
                            status=status.HTTP_400_BAD_REQUEST
                        )

                    print(f"[Case 날짜 동기화] occr_date: {case.occr_date} -> {parsed}")
                    case.occr_date = parsed

                    if "occr_date" not in changed_case_fields:
                        changed_case_fields.append("occr_date")

                except Exception as e:
                    print("[날짜 예외] occurred_at 처리 중 오류:", e)
                    return Response(
                        {"error": "occurred_at 형식이 올바르지 않습니다."},
                        status=status.HTTP_400_BAD_REQUEST
                    )

            case.payload = payload

            if "payload" not in changed_case_fields:
                changed_case_fields.append("payload")

            print("[missing 저장 예정 값]")
            print("case.reported_missing_name:", case.reported_missing_name)
            print("case.occr_location:", case.occr_location)
            print("case.occr_date:", case.occr_date)
            print("case.payload AFTER:", case.payload)
            print("changed_case_fields:", changed_case_fields)
            print("======================================================\n")

        elif case.type_code == Case.TypeCode.TIP:
            print("[8-2] 제보 수정 분기 진입")

            # -------------------------------------------------
            # 프론트 CitizenStatusDetailPage에서 보내는 tip 필드:
            # reported_missing_name, gender, found_location,
            # found_datetime, physical, clothing, health,
            # behavior, etc
            # -------------------------------------------------
            payload_fields = [
                "missing_seq",
                "reporter_name",
                "reporter_phone",

                # 추가: 시민 현황 상세 프로필 수정 페이지 대응
                "reported_missing_name",
                "gender",

                "found_location",
                "found_datetime",
                "physical",
                "clothing",
                "health",
                "behavior",
                "etc",
            ]

            print("payload_fields:", payload_fields)

            for field in payload_fields:
                if field in data:
                    old_value = payload.get(field)
                    new_value = data.get(field)
                    print(f"[payload 변경 - tip] {field}: {old_value} -> {new_value}")
                    payload[field] = new_value

            # 제보 대상 이름 수정
            if "reported_missing_name" in data:
                print(
                    f"[Case 제보 대상 이름 변경] reported_missing_name: "
                    f"{case.reported_missing_name} -> {data.get('reported_missing_name')}"
                )

                case.reported_missing_name = data.get("reported_missing_name")
                payload["reported_missing_name"] = data.get("reported_missing_name")

                # 기존 payload에서 missing_name을 쓰는 화면이 있을 수 있어 같이 동기화
                payload["missing_name"] = data.get("reported_missing_name")

                if "reported_missing_name" not in changed_case_fields:
                    changed_case_fields.append("reported_missing_name")

            # 제보 대상 성별 저장
            if "gender" in data:
                print(f"[payload 성별 저장 - tip] gender: {payload.get('gender')} -> {data.get('gender')}")
                payload["gender"] = data.get("gender")

            # 발견 장소 → Case 기본 필드 동기화
            if "found_location" in data:
                print(f"[Case 발견 장소 동기화] occr_location: {case.occr_location} -> {data.get('found_location')}")
                case.occr_location = data.get("found_location")

                if "occr_location" not in changed_case_fields:
                    changed_case_fields.append("occr_location")

            # 발견 시간 → Case 기본 필드 동기화
            if "found_datetime" in data and data.get("found_datetime"):
                print("[tip 날짜 처리] found_datetime 수신:", data.get("found_datetime"))

                try:
                    raw = data.get("found_datetime")
                    parsed = parse_datetime(raw) if isinstance(raw, str) else None

                    print("parsed found_datetime:", parsed)

                    if parsed is None:
                        print("[날짜 오류] found_datetime parse 실패")
                        return Response(
                            {"error": "found_datetime 형식이 올바르지 않습니다. ISO-8601 형식이어야 합니다."},
                            status=status.HTTP_400_BAD_REQUEST
                        )

                    print(f"[Case 발견 시간 동기화] occr_date: {case.occr_date} -> {parsed}")
                    case.occr_date = parsed

                    if "occr_date" not in changed_case_fields:
                        changed_case_fields.append("occr_date")

                except Exception as e:
                    print("[날짜 예외] found_datetime 처리 중 오류:", e)
                    return Response(
                        {"error": "found_datetime 형식이 올바르지 않습니다."},
                        status=status.HTTP_400_BAD_REQUEST
                    )
            else:
                print("[tip 날짜 처리] found_datetime 미전송 또는 빈 값 -> 기존 case.occr_date 유지:", case.occr_date)

            case.payload = payload

            if "payload" not in changed_case_fields:
                changed_case_fields.append("payload")

            print("[tip payload 저장 예정]")
            print("case.payload AFTER:", case.payload)
            print("changed_case_fields:", changed_case_fields)
            print("------------------------------------------------------")

            # -------------------------------------------------
            # Feature 수정
            # 기존 Feature가 없으면 새로 생성
            # -------------------------------------------------
            print("[9] Feature 수정 시작")

            feature = case.features.first()

            if not feature:
                print("[Feature 없음] 새 Feature 생성")
                feature = Feature.objects.create(
                    case=case,
                    ai_source=Feature.AISource.MANUAL,
                    confidence=0.0,
                )
                print("created feature.id:", feature.id)
            else:
                print("[Feature 있음] 기존 Feature 수정")
                print("feature.id:", feature.id)
                print("feature.physical BEFORE:", feature.physical)
                print("feature.clothing BEFORE:", feature.clothing)
                print("feature.health BEFORE:", feature.health)
                print("feature.behavior BEFORE:", feature.behavior)
                print("feature.etc BEFORE:", feature.etc)

            feature_map = {
                "physical": "physical",
                "clothing": "clothing",
                "health": "health",
                "behavior": "behavior",
                "etc": "etc",
            }

            feature_changed = []

            for req_key, feature_field in feature_map.items():
                if req_key in data:
                    old_value = getattr(feature, feature_field)
                    new_value = data.get(req_key)

                    print(f"[Feature 변경] {feature_field}: {old_value} -> {new_value}")

                    setattr(feature, feature_field, new_value)
                    feature_changed.append(feature_field)

            print("feature_changed:", feature_changed)

            if feature_changed:
                if hasattr(feature, "updated_at"):
                    print("Feature save update_fields:", feature_changed + ["updated_at"])
                    feature.save(update_fields=feature_changed + ["updated_at"])
                else:
                    print("Feature save update_fields:", feature_changed)
                    feature.save(update_fields=feature_changed)

                feature.refresh_from_db()
                print("[Feature 저장 완료]")
                print("feature.physical AFTER:", feature.physical)
                print("feature.clothing AFTER:", feature.clothing)
                print("feature.health AFTER:", feature.health)
                print("feature.behavior AFTER:", feature.behavior)
                print("feature.etc AFTER:", feature.etc)
            else:
                print("[Feature 변경 없음] 저장 생략")

            print("======================================================\n")

        else:
            print("[분기 실패] 수정할 수 없는 case.type_code:", case.type_code)
            return Response(
                {"error": "수정할 수 없는 케이스 타입입니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        # -------------------------------------------------
        # C. 사진 수정
        # 프론트:
        # delete_photos = jsonEncode([1, 2, 3])
        # new_photos = multipart file list
        # -------------------------------------------------
        print("[10] C. 사진 수정 시작")
        print("현재 Case 사진 개수 BEFORE:", TipPhoto.objects.filter(case=case).count())
        print("현재 Case 사진 ID 목록 BEFORE:", list(TipPhoto.objects.filter(case=case).values_list("id", flat=True)))

        if "delete_photos" in data:
            raw_delete_ids = (
                data.getlist("delete_photos")
                if hasattr(data, "getlist")
                else data.get("delete_photos", [])
            )

            print("[사진 삭제] raw_delete_ids:", raw_delete_ids)
            print("[사진 삭제] raw_delete_ids type:", type(raw_delete_ids))

            # MultipartRequest fields로 JSON 문자열이 들어오는 경우:
            # "[1,2,3]"
            if isinstance(raw_delete_ids, str):
                try:
                    parsed_delete_ids = json.loads(raw_delete_ids)
                    print("[사진 삭제] json.loads(raw_delete_ids) 성공:", parsed_delete_ids)
                except Exception as e:
                    print("[사진 삭제] json.loads(raw_delete_ids) 실패:", e)
                    parsed_delete_ids = [raw_delete_ids]
            else:
                parsed_delete_ids = raw_delete_ids

            # getlist 결과가 ['[1,2,3]']처럼 들어오는 경우까지 처리
            if (
                    isinstance(parsed_delete_ids, list)
                    and len(parsed_delete_ids) == 1
                    and isinstance(parsed_delete_ids[0], str)
                    and parsed_delete_ids[0].strip().startswith("[")
            ):
                try:
                    parsed_delete_ids = json.loads(parsed_delete_ids[0])
                    print("[사진 삭제] json.loads(parsed_delete_ids[0]) 성공:", parsed_delete_ids)
                except Exception as e:
                    print("[사진 삭제] json.loads(parsed_delete_ids[0]) 실패:", e)

            cleaned_delete_ids = []

            if isinstance(parsed_delete_ids, list):
                for photo_id in parsed_delete_ids:
                    try:
                        cleaned_delete_ids.append(int(photo_id))
                    except (ValueError, TypeError) as e:
                        print(f"[사진 삭제] int 변환 실패 photo_id={photo_id}, error={e}")
            else:
                try:
                    cleaned_delete_ids.append(int(parsed_delete_ids))
                except (ValueError, TypeError) as e:
                    print(f"[사진 삭제] int 변환 실패 parsed_delete_ids={parsed_delete_ids}, error={e}")

            print("[사진 삭제] cleaned_delete_ids:", cleaned_delete_ids)

            if cleaned_delete_ids:
                delete_qs = TipPhoto.objects.filter(
                    case=case,
                    id__in=cleaned_delete_ids
                )

                print("[사진 삭제] 실제 삭제 대상 count:", delete_qs.count())
                print("[사진 삭제] 실제 삭제 대상 id 목록:", list(delete_qs.values_list("id", flat=True)))

                deleted_result = delete_qs.delete()

                print("[사진 삭제] delete 결과:", deleted_result)
            else:
                print("[사진 삭제] cleaned_delete_ids 없음 -> 삭제 생략")
        else:
            print("[사진 삭제] delete_photos 미전송 -> 삭제 생략")

        if "new_photos" in request.FILES:
            new_files = request.FILES.getlist("new_photos")
            print("[사진 추가] new_photos count:", len(new_files))

            for idx, file in enumerate(new_files, start=1):
                print(f"[사진 추가 {idx}] name:", file.name)
                print(f"[사진 추가 {idx}] size:", file.size)
                print(f"[사진 추가 {idx}] content_type:", getattr(file, "content_type", None))

                tip_photo = TipPhoto.objects.create(
                    case=case,
                    image=file,
                    photo_type=TipPhoto.PhotoType.SUBJECT,
                    is_ai_generated=False,
                )

                print(f"[사진 추가 {idx}] 저장 완료 TipPhoto.id:", tip_photo.id)
                print(f"[사진 추가 {idx}] 저장 경로 image.name:", tip_photo.image.name)
                print(f"[사진 추가 {idx}] is_ai_generated:", tip_photo.is_ai_generated)
        else:
            print("[사진 추가] new_photos 미전송 -> 추가 생략")

        print("현재 Case 사진 개수 AFTER:", TipPhoto.objects.filter(case=case).count())
        print("현재 Case 사진 ID 목록 AFTER:", list(TipPhoto.objects.filter(case=case).values_list("id", flat=True)))
        print("======================================================\n")

        # -------------------------------------------------
        # D. 저장
        # -------------------------------------------------
        print("[11] D. Case 저장 시작")
        print("changed_case_fields:", changed_case_fields)

        if changed_case_fields:
            print("Case save update_fields:", changed_case_fields + ["updated_at"])
            case.save(update_fields=changed_case_fields + ["updated_at"])
        else:
            print("changed_case_fields 없음 -> case.save() 전체 저장")
            case.save()

        case.refresh_from_db()

        print("[Case 저장 완료]")
        print("case.id:", case.id)
        print("case.type_code:", case.type_code)
        print("case.status:", case.status)
        print("case.reported_missing_name AFTER:", case.reported_missing_name)
        print("case.occr_location AFTER:", case.occr_location)
        print("case.occr_date AFTER:", case.occr_date)
        print("case.description AFTER:", case.description)
        print("case.payload AFTER DB:", case.payload)
        print("======================================================\n")

        print("[12] Log 생성 시작")

        log = Log.objects.create(
            user=getattr(request.user, "person", None),
            action="제보/신고 수정",
            target_type="Case",
            target_id=case.id
        )

        print("[Log 생성 완료]")
        print("log.id:", log.id)
        print("log.user:", log.user)
        print("log.action:", log.action)
        print("log.target_type:", log.target_type)
        print("log.target_id:", log.target_id)
        print("======================================================\n")

        response_data = {
            "message": "제보/신고 수정 완료",
            "case_id": case.id,
            "type_code": case.type_code,
            "status": case.status,
        }

        print("[13] 최종 응답")
        print("response_data:", response_data)
        print("========== [edit_case] 제보/신고 수정 API 종료 ==========\n\n")

        return Response(
            response_data,
            status=status.HTTP_200_OK
        )
    # --------------------------------
    # 2️⃣ 제보 수정
    # --------------------------------
    @action(detail=True, methods=["patch"], url_path="update-tip",permission_classes=[IsNotGuest])
    def update_tip(self, request, pk=None):
        """
        PATCH /dasibom/case/{id}/update-tip/
        body: {
            "occr_date": "2026-03-17T00:00:00",
            "occr_location": "서울시 ...",
            "physical": "...",
            "clothing": "...",
        }
        수정 가능 필드: occr_date, occr_location, physical, clothing
        completed 상태면 수정 불가
        """
        case = get_object_or_404(Case, pk=pk, type_code=Case.TypeCode.TIP)

        is_admin = getattr(request.user, "role", None) == "admin"
        is_owner = (
                hasattr(request.user, "person")
                and case.reporter == request.user.person
        )

        if not (is_admin or is_owner):
            return Response(
                {"error": "본인 또는 관리자만 수정할 수 있습니다."},
                status=403
            )

        # -------------------------------------------------
        # 2. 상태 체크
        #
        # 관리자:
        # - 모든 상태 수정 가능
        #
        # 일반 사용자:
        # - 제보: received / completed 수정 가능
        # - 실종 신고:
        #   received → Case 수정 가능
        #   completed → MissingPerson 수정 API 사용
        # -------------------------------------------------

        if not is_admin:

            if case.type_code == Case.TypeCode.TIP:
                allowed_statuses = [
                    Case.Status.RECEIVED,
                    Case.Status.COMPLETED,
                ]

            elif case.type_code == Case.TypeCode.MISSING:
                allowed_statuses = [
                    Case.Status.RECEIVED,
                ]

            else:
                allowed_statuses = []

            if case.status not in allowed_statuses:
                return Response(
                    {
                        "error": (
                            "현재 상태에서는 이 신고/제보를 수정할 수 없습니다."
                        )
                    },
                    status=status.HTTP_400_BAD_REQUEST
                )

        # Case 필드 수정
        updatable_case_fields = ["occr_date", "occr_location"]
        case_changed = []
        for field in updatable_case_fields:
            if field in request.data:
                setattr(case, field, request.data[field])
                case_changed.append(field)

        if case_changed:
            case.save(update_fields=case_changed + ["updated_at"])

        # Feature 필드 수정 (physical, clothing)
        feature_fields = ["physical", "clothing", "health", "behavior", "etc"]
        feature_data = {k: v for k, v in request.data.items() if k in feature_fields}

        if feature_data:
            feature = case.features.first()
            if feature:
                for field, value in feature_data.items():
                    setattr(feature, field, value)
                feature.save(update_fields=list(feature_data.keys()) + ["updated_at"])

        return Response({
            "message": "제보 수정 완료",
            "case_id": case.id,
            "status": case.status,
        })

    @action(detail=True, methods=["patch"], url_path="admin-status", permission_classes=[IsAdmin])
    def admin_status(self, request, pk=None):
        """
        PATCH /dasibom/prevention-registrations/{id}/admin-status/

        상태 전환:
        received  -> reviewing / rejected
        reviewing -> completed / rejected
        completed -> reviewing
        rejected  -> reviewing

        completed 전환 시:
        - PreventionRegistration 대상자를 Person 피보호자로 생성/연결
        - 로그인한 등록자(owner)를 guardian으로 하는 Guardian 관계 생성
        - device_code 기준 Device를 피보호자에게 연결
        """

        registration = get_object_or_404(PreventionRegistration, pk=pk)

        new_status = request.data.get("status")
        rejected_reason = request.data.get("rejected_reason")

        allowed_statuses = [
            PreventionRegistration.Status.RECEIVED,
            PreventionRegistration.Status.REVIEWING,
            PreventionRegistration.Status.COMPLETED,
            PreventionRegistration.Status.REJECTED,
        ]

        allowed_transitions = {
            PreventionRegistration.Status.RECEIVED: [
                PreventionRegistration.Status.REVIEWING,
                PreventionRegistration.Status.REJECTED,
            ],
            PreventionRegistration.Status.REVIEWING: [
                PreventionRegistration.Status.COMPLETED,
                PreventionRegistration.Status.REJECTED,
            ],
            PreventionRegistration.Status.COMPLETED: [
                PreventionRegistration.Status.REVIEWING,
            ],
            PreventionRegistration.Status.REJECTED: [
                PreventionRegistration.Status.REVIEWING,
            ],
        }

        if not new_status:
            return Response(
                {"error": "status 값이 필요합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if new_status not in allowed_statuses:
            return Response(
                {
                    "error": "유효하지 않은 상태값입니다.",
                    "allowed": allowed_statuses,
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        current_status = registration.status

        if current_status == new_status:
            return Response(
                {"error": f"이미 '{new_status}' 상태입니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if current_status not in allowed_transitions:
            return Response(
                {"error": f"현재 상태값이 올바르지 않습니다: {current_status}"},
                status=status.HTTP_400_BAD_REQUEST
            )

        if new_status not in allowed_transitions[current_status]:
            return Response(
                {
                    "error": "허용되지 않은 상태 전환입니다.",
                    "current_status": current_status,
                    "allowed_next": allowed_transitions[current_status],
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        linked_person_id = None
        linked_person_name = None
        guardian_created = False
        device_code = None
        device_connected = False

        with transaction.atomic():
            registration.status = new_status
            registration.reviewed_by = getattr(request.user, "person", None)
            registration.reviewed_at = timezone.now()

            if new_status == PreventionRegistration.Status.REJECTED:
                registration.rejected_reason = rejected_reason or "관리자에 의해 거절되었습니다."

            if (
                    current_status == PreventionRegistration.Status.REJECTED
                    and new_status == PreventionRegistration.Status.REVIEWING
            ):
                registration.rejected_reason = None

            # -------------------------------------------------
            # completed 전환 시 피보호자/보호자/기기 연결 처리
            # -------------------------------------------------
            if new_status == PreventionRegistration.Status.COMPLETED:
                person = getattr(registration, "linked_person", None)

                if person is None:
                    sex = Person.Sex.UNKNOWN

                    if registration.gender == "남자":
                        sex = Person.Sex.MALE
                    elif registration.gender == "여자":
                        sex = Person.Sex.FEMALE

                    person = Person.objects.create(
                        name=registration.name,
                        sex=sex,
                        phone=registration.phone,
                        address=registration.address,
                        health_info=registration.health_info,
                    )

                    registration.linked_person = person

                linked_person_id = person.id
                linked_person_name = person.name

                guardian, guardian_created = Guardian.objects.get_or_create(
                    guardian=registration.owner,
                    ward=person,
                    defaults={"relation": "피보호자"}
                )

                # 이미 배지 번호가 발급된 예방등록이면 기존 번호 유지
                if registration.device_code:
                    device_code = registration.device_code

                # 최초 완료 처리라면 다음 KIOSK 번호 자동 발급
                else:
                    device_code = self._generate_next_device_code()
                    registration.device_code = device_code

                Device.objects.update_or_create(
                    device_uid=device_code,
                    defaults={
                        "person": person,
                        "status": Device.Status.ACTIVE,
                    }
                )

                device_connected = True

            registration.save()

            Log.objects.create(
                user=getattr(request.user, "person", None),
                action=f"실종 예방 등록 상태 변경: {current_status} → {new_status}",
                target_type="PreventionRegistration",
                target_id=registration.id,
            )

        return Response(
            {
                "message": "상태 변경 완료",
                "id": registration.id,
                "old_status": current_status,
                "new_status": registration.status,
                "status_label": self._status_label(registration.status),
                "rejected_reason": registration.rejected_reason,
                "reviewed_by": registration.reviewed_by.id if registration.reviewed_by else None,
                "reviewed_by_name": registration.reviewed_by.name if registration.reviewed_by else None,
                "reviewed_at": self._format_datetime_for_front(registration.reviewed_at),

                "linked_person_id": linked_person_id,
                "linked_person_name": linked_person_name,
                "guardian_created": guardian_created,
                "device_code": device_code,
                "device_connected": device_connected,
            },
            status=status.HTTP_200_OK
        )
    @action(detail=False, methods=["get"], url_path="missing-requests", permission_classes=[IsAdmin])
    def missing_requests(self, request):
        """
        GET /dasibom/case/missing-requests/

        실종자 등록 요청 목록 (관리자용)
        """

        qs = Case.objects.filter(
            type_code=Case.TypeCode.MISSING,
            status=Case.Status.RECEIVED
        ).select_related(
            "reporter"
        ).prefetch_related(
            "photos"
        ).order_by("-created_at")
        data = []

        for case in qs:
            data.append({
                "case_id": case.id,
                "reporter_name": case.reporter.name if case.reporter else None,
                "reporter_phone": case.reporter.phone if case.reporter else None,
                "description": case.description,
                "payload": case.payload,
                "created_at": format_datetime_for_front(case.created_at),
                "photo_count": case.photos.filter(
                    photo_type=TipPhoto.PhotoType.SUBJECT
                ).count(),
                "photos": [
                    media_url(
                        photo.image.name,
                        request,
                    )
                    for photo in case.photos.filter(
                        photo_type=TipPhoto.PhotoType.SUBJECT
                    )
                    if photo.image
                ],
                "photo_items": [
    {
        "id": photo.id,
        "url": media_url(
            photo.image.name,
            request,
        ),
        "image": photo.image.name,
        "photo_type": photo.photo_type,
        "is_ai_generated": photo.is_ai_generated,
        "uploaded_at": format_datetime_for_front(
            photo.uploaded_at
        ),
    }
    for photo in case.photos.all()
    if photo.image
],
            })

        return Response(data)

    @action(detail=True, methods=["delete"], url_path="delete", permission_classes=[IsAdmin])
    def delete_case(self, request, pk=None):
        case = get_object_or_404(Case, pk=pk)

        case_id = case.id

        case.delete()

        # 🔥 로그 추가
        Log.objects.create(
            user = getattr(request.user, "person", None),
            action="제보 삭제",
            target_type="Case",
            target_id=case_id
        )

        return Response({
            "message": "제보 삭제 완료",
            "case_id": case_id
        })

    @action(detail=True, methods=["patch"], permission_classes=[IsAdmin])

    def approve_missing(self, request, pk=None):
        import uuid
        from datetime import date

        case = get_object_or_404(
            Case,
            pk=pk,
            type_code=Case.TypeCode.MISSING
        )

        # ------------------------------
        # 0️⃣ 이미 처리된 건 막기
        # ------------------------------
        if case.status != Case.Status.RECEIVED:
            return Response(
                {"error": "이미 처리된 요청입니다."},
                status=400
            )

        result = self._approve_missing_internal(case)

        if not result["success"]:
            return Response(
                {"error": "실종자 등록 실패", "detail": result["detail"]},
                status=400
            )

        missing = result["missing"]
        return Response({
            "message": "실종자 승인 및 생성 완료",
            "missing_id": missing.id,
            "identifier": missing.msspsn_idntfccd,
            "image_count": result["image_count"]
        })

    def _approve_missing_internal(self, case):
        print("\n🔥🔥🔥 _approve_missing_internal 호출됨 🔥🔥🔥")
        print("case.id:", case.id)
        print("case.status:", case.status)
        print("case.missing_person_id:", case.missing_person_id)
        print("========================================\n")
        """
        approve_missing의 핵심 로직.
        admin_status에서 completed 전환 시에도 재사용.

        처리:
        - Case.payload 기반 MissingPerson 생성
        - description_ai_segments가 있으면 카테고리 라벨로 etc_spfeatr 저장
        - 승인 시 AI 분류기는 새로 실행하지 않음
        """
        import uuid
        from datetime import date

        # 이미 MissingPerson이 연결돼 있으면 중복 생성 방지
        if case.missing_person_id:
            return {
                "success": True,
                "missing": case.missing_person,
                "image_count": 0
            }

        payload = case.payload or {}

        # ------------------------------
        # 1. 카테고리 매핑
        # ------------------------------
        if payload.get("category"):
            payload["category"] = CATEGORY_MAP.get(
                payload["category"],
                payload["category"]
            )

        # ------------------------------
        # 2. 성별 매핑
        # ------------------------------
        GENDER_MAP = {
            "male": "남자",
            "female": "여자",
            "unknown": "미상",
        }

        if payload.get("gender"):
            payload["gender"] = GENDER_MAP.get(payload["gender"], payload["gender"])

        # ------------------------------
        # 3. 필드 필터링
        # ------------------------------
        allowed_fields = [
            "name",
            "gender",
            "age_at_missing",
            "category",
            "nationality",
            "height",
            "weight",
            "body_type",
            "face_type",
            "hair_color",
            "hair_style",
            "clothing",
            "occurred_at",
            "occurred_location",
        ]

        filtered_payload = {
            k: v for k, v in payload.items()
            if k in allowed_fields
        }

        # ------------------------------
        # 4. description_ai_segments → etc_spfeatr 라벨 저장
        # ------------------------------
        extra_segments = []

        if payload.get("physical"):
            extra_segments.append(f"[신체 특징] {payload.get('physical')}")

        if payload.get("health"):
            extra_segments.append(f"[건강·장애 정보] {payload.get('health')}")

        if payload.get("behavior"):
            extra_segments.append(f"[성격·행동 특성] {payload.get('behavior')}")

        if payload.get("etc"):
            extra_segments.append(f"[기타 참고 사항] {payload.get('etc')}")

        description_ai_segments = payload.get("description_ai_segments") or []

        if description_ai_segments:
            CATEGORY_LABEL_MAP = {
                "신체특징": "신체 특징",
                "신체 특징": "신체 특징",
                "physical": "신체 특징",

                "착의외형": "착의·외형 정보",
                "착의·외형 정보": "착의·외형 정보",
                "착의 사항": "착의·외형 정보",
                "clothing": "착의·외형 정보",

                "건강장애": "건강·장애 정보",
                "건강·장애 정보": "건강·장애 정보",
                "health": "건강·장애 정보",

                "행동특성": "성격·행동 특성",
                "성격·행동 특성": "성격·행동 특성",
                "behavior": "성격·행동 특성",

                "기타": "기타 참고 사항",
                "기타 참고 사항": "기타 참고 사항",
                "extra": "기타 참고 사항",
            }

            for item in description_ai_segments:
                if not isinstance(item, dict):
                    continue

                text = item.get("text")
                category = item.get("category")

                if not text:
                    continue

                label = CATEGORY_LABEL_MAP.get(str(category).strip(), "기타 참고 사항")
                extra_segments.append(f"[{label}] {text}")

        elif payload.get("description"):
            # AI 결과가 없는 과거 데이터/실패 데이터만 fallback
            extra_segments.append(f"[기타 참고 사항] {payload.get('description')}")

        if extra_segments:
            filtered_payload["etc_spfeatr"] = "\n".join(extra_segments)

        # ------------------------------
        # 5. 날짜 변환
        # ------------------------------
        if filtered_payload.get("occurred_at"):
            try:
                filtered_payload["occurred_at"] = datetime.fromisoformat(
                    filtered_payload["occurred_at"]
                ).date()
            except Exception:
                filtered_payload["occurred_at"] = None

        # ------------------------------
        # 6. 현재나이 계산
        # ------------------------------
        age_at_missing = filtered_payload.get("age_at_missing")
        occurred_at = filtered_payload.get("occurred_at")

        if age_at_missing not in [None, ""]:
            try:
                # multipart/form-data로 들어온 나이는 문자열일 수 있으므로 int 변환
                age_at_missing = int(age_at_missing)

                # MissingPerson 생성 시에도 정수형으로 저장되도록 덮어쓰기
                filtered_payload["age_at_missing"] = age_at_missing

            except (ValueError, TypeError):
                return {
                    "success": False,
                    "detail": "age_at_missing 값은 숫자여야 합니다."
                }

        if age_at_missing is not None and occurred_at:
            occurred_year = occurred_at.year
            current_year = date.today().year
            diff = current_year - occurred_year

            filtered_payload["current_age"] = age_at_missing + diff
        # ------------------------------
        # 7. 트랜잭션 처리
        # ------------------------------
        try:
            with transaction.atomic():

                # ------------------------------
                # 7-1. MissingPerson 생성
                # ------------------------------
                print("🚨 MissingPerson 새로 생성 직전")
                print("case_id:", case.id)
                missing = MissingPerson.objects.create(
                    **filtered_payload,
                    msspsn_idntfccd=f"TEMP-{uuid.uuid4().hex[:8]}",
                    status=MissingPerson.Status.MISSING,
                    source=MissingPerson.Source.USER,
                )
                print("🚨 새 MissingPerson 생성됨:", missing.id)
                # ------------------------------
                # 승인 시 AI 분류 새로 실행하지 않음
                # register_missing 시 저장된 description_ai_segments만 사용
                # ------------------------------
                print("[_approve_missing_internal] 승인 시 AI 재실행 없음: description_ai_segments 사용")

                # ------------------------------
                # 7-2. 식별코드 확정
                # ------------------------------
                missing.msspsn_idntfccd = f"99{missing.id:08d}"
                missing.save(update_fields=["msspsn_idntfccd", "updated_at"])

                # ------------------------------
                # 7-3. 이미지 연결
                #
                # subject 사진만 MissingPerson 공식 사진으로 복사
                # parent1_face / parent2_face는 Case 사진으로 유지
                # → 이후 AI 몽타주 생성 시 자동으로 불러와 사용
                # ------------------------------
                new_images = []
                new_ai_images = []

                # =====================================================
                # 대상자 사진을 한 번만 조회
                # =====================================================
                subject_photos = list(
                    case.photos.filter(
                        photo_type=TipPhoto.PhotoType.SUBJECT
                    ).order_by("id")
                )

                print(
                    "[승인 이미지 처리]",
                    "전체 사진 수:",
                    case.photos.count(),
                    "/ 대상자 사진 수:",
                    len(subject_photos),
                )

                # =====================================================
                # 대상자 사진 병렬 복사
                # Cloudinary → 읽기 → Cloudinary 새 경로 저장
                # =====================================================
                copy_start = time.perf_counter()

                def copy_subject_photo(index, photo):
                    """
                    대상자 사진 1장을 MissingPerson 공식 사진 경로로 복사.

                    DB 작업은 하지 않고 파일 I/O만 수행한다.
                    """

                    if not photo.image:
                        return None

                    try:
                        # ---------------------------------------------
                        # 1. 기존 Cloudinary 파일 읽기
                        # ---------------------------------------------
                        photo.image.open("rb")

                        try:
                            old_path = photo.image.name
                            file_content = photo.image.read()

                        finally:
                            photo.image.close()

                        # ---------------------------------------------
                        # 2. 새 저장 경로 생성
                        # ---------------------------------------------
                        filename = old_path.split("/")[-1]

                        new_path = (
                            f"missing_persons/"
                            f"{missing.msspsn_idntfccd}/"
                            f"{filename}"
                        )

                        # ---------------------------------------------
                        # 3. Cloudinary에 저장
                        # ---------------------------------------------
                        saved_path = default_storage.save(
                            new_path,
                            ContentFile(file_content)
                        )

                        return {
                            "index": index,
                            "photo_id": photo.id,
                            "photo_type": photo.photo_type,
                            "saved_path": saved_path,
                            "is_ai_generated": photo.is_ai_generated,
                        }

                    except Exception as e:
                        logger.warning(
                            "[_approve_missing_internal] "
                            "대상자 사진 복사 실패 "
                            "TipPhoto.id=%s: %s",
                            photo.id,
                            e,
                        )

                        return None

                # =====================================================
                # 최대 4장 동시 처리
                # =====================================================
                copy_results = []

                if subject_photos:

                    max_workers = min(
                        4,
                        len(subject_photos),
                    )

                    with ThreadPoolExecutor(
                            max_workers=max_workers
                    ) as executor:

                        futures = [
                            executor.submit(
                                copy_subject_photo,
                                index,
                                photo,
                            )
                            for index, photo
                            in enumerate(subject_photos)
                        ]

                        for future in as_completed(futures):

                            try:
                                result = future.result()

                                if result:
                                    copy_results.append(
                                        result
                                    )

                            except Exception as e:
                                logger.warning(
                                    "[_approve_missing_internal] "
                                    "사진 병렬 작업 예외: %s",
                                    e,
                                )

                # =====================================================
                # 병렬 처리로 완료 순서가 달라질 수 있으므로
                # 원래 사진 순서로 다시 정렬
                # =====================================================
                copy_results.sort(
                    key=lambda item: item["index"]
                )

                for result in copy_results:

                    saved_path = result["saved_path"]

                    new_images.append(
                        saved_path
                    )

                    if result["is_ai_generated"]:
                        new_ai_images.append(
                            saved_path
                        )

                    print(
                        "[대상자 사진 복사 완료]",
                        f"TipPhoto.id={result['photo_id']}",
                        f"photo_type={result['photo_type']}",
                        f"saved_path={saved_path}",
                    )

                copy_elapsed = (
                        time.perf_counter()
                        - copy_start
                )

                logger.warning(
                    "[승인 이미지 병렬 복사 완료] "
                    "성공=%s/%s | %.2f초",
                    len(copy_results),
                    len(subject_photos),
                    copy_elapsed,
                )

                # MissingPerson 공식 사진 목록 저장
                if new_images:
                    missing.image_urls = new_images
                    missing.ai_image_urls = new_ai_images

                    missing.save(
                        update_fields=[
                            "image_urls",
                            "ai_image_urls",
                            "updated_at",
                        ]
                    )

                print(
                    "[승인 이미지 처리 완료]",
                    f"일반 사진={len(new_images)}",
                    f"AI 사진={len(new_ai_images)}",
                )

                # 가족사진은 MissingPerson.image_urls에 넣지 않고
                # Case의 TipPhoto에 그대로 보관
                parent1_photo = case.photos.filter(
                    photo_type=TipPhoto.PhotoType.PARENT1_FACE
                ).first()

                parent2_photo = case.photos.filter(
                    photo_type=TipPhoto.PhotoType.PARENT2_FACE
                ).first()

                print(
                    "[가족사진 보관 확인]",
                    "parent1=",
                    parent1_photo.image.name
                    if parent1_photo and parent1_photo.image
                    else None,
                    "parent2=",
                    parent2_photo.image.name
                    if parent2_photo and parent2_photo.image
                    else None,
                )
                # ------------------------------
                # 7-4. FK 연결 + 상태 완료
                # ------------------------------
                case.missing_person = missing
                case.status = Case.Status.COMPLETED
                case.save(update_fields=[
                    "missing_person",
                    "status",
                    "updated_at",
                ])

            print("description:", payload.get("description"))
            print("description_ai_segments:", payload.get("description_ai_segments"))

            return {
                "success": True,
                "missing": missing,
                "image_count": len(new_images)
            }

        except Exception as e:
            return {
                "success": False,
                "detail": str(e)
            }
    def _remove_missing_from_completed_case_internal(self, case):
        """
        completed -> reviewing 으로 되돌릴 때
        신고 승인으로 생성된 MissingPerson을 제거하는 내부 함수.

        처리 내용:
        1. case.missing_person 확인
        2. 연결된 MissingPerson이 USER source인지 확인
        3. MissingPerson 이미지 파일 삭제 시도
        4. case.missing_person 연결 해제
        5. MissingPerson DB 삭제
        """
        try:
            missing = case.missing_person

            if not missing:
                return {
                    "success": True,
                    "missing_id": None,
                    "identifier": None,
                    "detail": "연결된 MissingPerson이 없어 제거할 항목 없음"
                }

            missing_id = missing.id
            identifier = missing.msspsn_idntfccd

            # 🔥 안전장치
            # 시민 신고 승인으로 생성된 실종자만 삭제
            # Safe182 크롤링 데이터는 절대 삭제하지 않음
            if missing.source != MissingPerson.Source.USER:
                return {
                    "success": False,
                    "detail": "사용자 신고로 생성된 실종자가 아니므로 삭제할 수 없습니다."
                }

            # 🔥 이미지 파일 삭제 시도
            image_urls = missing.image_urls or []

            for image_path in image_urls:
                try:
                    if image_path:
                        default_storage.delete(
                            image_path
                        )
                except Exception as e:
                    logger.warning(
                        f"MissingPerson 이미지 삭제 실패 "
                        f"({image_path}): {e}"
                    )
            # 🔥 Case와 MissingPerson 연결 해제
            case.missing_person = None
            case.save(update_fields=["missing_person", "updated_at"])

            # 🔥 MissingPerson 삭제
            missing.delete()

            return {
                "success": True,
                "missing_id": missing_id,
                "identifier": identifier,
                "detail": "MissingPerson 제거 완료"
            }

        except Exception as e:
            return {
                "success": False,
                "detail": str(e)
            }

    @action(detail=False, methods=["get"], url_path="my-tips", permission_classes=[IsAuthenticated])
    def my_tips(self, request):
        qs = Case.objects.filter(
            reporter=request.user.person,
            type_code=Case.TypeCode.TIP
        ).select_related(
            "reporter",
            "missing_person"
        ).prefetch_related(
            "features",
            "photos"
        ).order_by("-created_at")

        serializer = TipListSerializer(
            qs,
            many=True,
            context={"request": request}
        )
        return Response(serializer.data)

    #본인의 제보 리스트
    @action(detail=False, methods=["get"], url_path="my-reports", permission_classes=[IsAuthenticated])
    def my_reports(self, request):
        import time

        total_start = time.perf_counter()

        qs = Case.objects.filter(
            reporter=request.user.person,
            type_code=Case.TypeCode.MISSING
        ).prefetch_related(
            "photos"
        ).order_by("-created_at")

        # 실제 DB 조회 시간
        db_start = time.perf_counter()
        cases = list(qs)
        db_elapsed = time.perf_counter() - db_start

        # serializer 시간
        serializer_start = time.perf_counter()

        serializer = CaseSerializer(
            cases,
            many=True,
            context={"request": request}
        )

        data = serializer.data

        serializer_elapsed = time.perf_counter() - serializer_start
        total_elapsed = time.perf_counter() - total_start

        print(
            "[my_reports timing]",
            f"db={db_elapsed:.3f}s",
            f"serializer={serializer_elapsed:.3f}s",
            f"total={total_elapsed:.3f}s",
            f"count={len(cases)}",
        )

        return Response(data)
    @action(detail=True, methods=["post"], url_path="guest-detail", permission_classes=[AllowAny])
    def guest_detail(self, request, pk=None):
        """
        POST /dasibom/case/{case_id}/guest-detail/

        비회원 신고/제보 상세 조회
        body:
        {
            "reporter_name": "꿀호떡",
            "reporter_phone": "01022937371"
        }
        """

        reporter_name = request.data.get("reporter_name")
        reporter_phone = request.data.get("reporter_phone")

        if not reporter_name:
            return Response(
                {"error": "reporter_name 값이 필요합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not reporter_phone:
            return Response(
                {"error": "reporter_phone 값이 필요합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        case = get_object_or_404(
            Case.objects.select_related(
                "missing_person"
            ).prefetch_related(
                "photos",
                "features"
            ),
            pk=pk
        )
        payload = case.payload or {}

        # ------------------------------
        # 비회원 본인 확인
        # ------------------------------
        is_guest_owner = (
                case.reporter is None
                and payload.get("is_guest_report") is True
                and payload.get("reporter_name") == reporter_name
                and payload.get("reporter_phone") == reporter_phone
        )

        if not is_guest_owner:
            return Response(
                {"error": "조회 권한이 없습니다. 이름과 전화번호를 확인해주세요."},
                status=status.HTTP_403_FORBIDDEN
            )

        photos = [
            media_url(
                photo.image.name,
                request,
            )
            for photo in case.photos.filter(
                photo_type=TipPhoto.PhotoType.SUBJECT
            )
            if photo.image
        ]

        photo_items = [
            {
                "id": photo.id,
                "url": media_url(
                    photo.image.name,
                    request,
                ),
                "image": photo.image.name,
                "photo_type": photo.photo_type,
                "is_ai_generated": photo.is_ai_generated,
                "uploaded_at": (
                    timezone.localtime(
                        photo.uploaded_at
                    ).isoformat()
                    if photo.uploaded_at
                    else None
                ),
            }
            for photo in case.photos.all()
            if photo.image
        ]

        base = {
            "case_id": case.id,
            "type_code": case.type_code,
            "status": case.status,
            "created_at": format_datetime_for_front(case.created_at),
            "updated_at": format_datetime_for_front(case.updated_at),

            "reporter": {
                "name": payload.get("reporter_name"),
                "phone": payload.get("reporter_phone"),
            },

            "photos": photos,
            "photo_items": photo_items,

            "missing_person": {
                "id": case.missing_person.id if case.missing_person else None,
                "msspsn_idntfccd": case.missing_person.msspsn_idntfccd if case.missing_person else None,
                "name": case.missing_person.name if case.missing_person else None,
            } if case.missing_person else None,
        }

        def filter_none(items):
            return [item for item in items if item]

        # ------------------------------
        # 신고 상세
        # ------------------------------
        if case.type_code == Case.TypeCode.MISSING:
            base["missing_info"] = {
                "name": payload.get("name"),
                "gender": payload.get("gender"),
                "age_at_missing": payload.get("age_at_missing"),
                "occurred_at": payload.get("occurred_at"),
                "occurred_location": payload.get("occurred_location"),
                "nationality": payload.get("nationality"),
            }

            # ✅ 핵심 수정:
            # 비회원 신고 상세도 회원/관리자 상세와 동일하게
            # 공통 categories 변환 함수를 사용한다.
            base["categories"] = build_missing_report_categories(payload)

        # ------------------------------
        # 제보 상세
        # ------------------------------
        elif case.type_code == Case.TypeCode.TIP:
            feature = case.features.first()

            base["tip_info"] = {
                "missing_name": (
                        payload.get("missing_name")
                        or payload.get("reported_missing_name")
                        or case.reported_missing_name
                ),
                "gender": payload.get("gender"),
                "found_location": (
                        payload.get("found_location")
                        or case.occr_location
                ),
                "found_datetime": (
                    format_datetime_for_front(case.occr_date)
                    if case.occr_date
                    else payload.get("found_datetime")
                ),
                "reporter_name": payload.get("reporter_name"),
                "reporter_phone": payload.get("reporter_phone"),
            }

            base["categories"] = {
                "신체 특징": (
    split_feature_text(feature.physical)
    if feature and feature.physical
    else []
),
"착의 사항": (
    split_feature_text(feature.clothing)
    if feature and feature.clothing
    else []
),
"건강·장애 정보": (
    split_feature_text(feature.health)
    if feature and feature.health
    else []
),
"성격·행동 특성": (
    split_feature_text(feature.behavior)
    if feature and feature.behavior
    else []
),
"기타 참고 사항": (
    split_feature_text(feature.etc)
    if feature and feature.etc
    else []
),
            }

        return Response(base, status=status.HTTP_200_OK)
    @action(detail=False, methods=["post"], url_path="guest-history", permission_classes=[AllowAny])
    def guest_history(self, request):
        """
        POST /dasibom/case/guest-history/

        비회원 신고/제보 내역 조회
        body:
        {
            "reporter_name": "꿀호떡",
            "reporter_phone": "01022937371",
            "type_code": "missing"  # 선택: missing | tip
        }
        """

        reporter_name = request.data.get("reporter_name")
        reporter_phone = request.data.get("reporter_phone")
        type_code = request.data.get("type_code")

        # ------------------------------
        # 1️⃣ 필수값 검증
        # ------------------------------
        if not reporter_name:
            return Response(
                {"error": "reporter_name 값이 필요합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not reporter_phone:
            return Response(
                {"error": "reporter_phone 값이 필요합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        # ------------------------------
        # 2️⃣ 비회원 신고/제보 조회
        # ------------------------------
        queryset = Case.objects.filter(
            reporter__isnull=True,
            payload__reporter_name=reporter_name,
            payload__reporter_phone=reporter_phone,
            payload__is_guest_report=True,
        ).select_related(
            "missing_person"
        ).prefetch_related(
            "photos",
            "features"
        )

        # 신고/제보 타입 필터 선택 적용
        if type_code:
            if type_code not in [Case.TypeCode.MISSING, Case.TypeCode.TIP]:
                return Response(
                    {"error": "type_code는 missing 또는 tip만 가능합니다."},
                    status=status.HTTP_400_BAD_REQUEST
                )

            queryset = queryset.filter(type_code=type_code)

        queryset = queryset.order_by("-created_at")

        # ------------------------------
        # 3️⃣ 응답 데이터 구성
        # ------------------------------
        results = []

        for case in queryset:
            payload = case.payload or {}

            item = {
                "case_id": case.id,
                "type_code": case.type_code,
                "status": case.status,

                "reported_missing_name": case.reported_missing_name or payload.get("name") or payload.get(
                    "missing_name"),
                "created_at": format_datetime_for_front(case.created_at),
                "updated_at": format_datetime_for_front(case.updated_at),

                "occr_date":  format_datetime_for_front(case.occr_date),
                "occr_location": case.occr_location,
                "description": case.description,

                "reporter_name": payload.get("reporter_name"),
                "reporter_phone": payload.get("reporter_phone"),

                "missing_person": {
                    "id": case.missing_person.id if case.missing_person else None,
                    "msspsn_idntfccd": case.missing_person.msspsn_idntfccd if case.missing_person else None,
                    "name": case.missing_person.name if case.missing_person else None,
                } if case.missing_person else None,

                "photo_count": case.photos.filter(
                    photo_type=TipPhoto.PhotoType.SUBJECT
                ).count(),
                "photos": [
                        media_url(
                            photo.image.name,
                            request,
                        )
                        for photo in case.photos.filter(
                            photo_type=TipPhoto.PhotoType.SUBJECT
                        )
                        if photo.image
                    ],
                "photo_items": [
    {
        "id": photo.id,
        "url": media_url(
            photo.image.name,
            request,
        ),
        "image": photo.image.name,
        "photo_type": photo.photo_type,
        "is_ai_generated": photo.is_ai_generated,
        "uploaded_at": (
            timezone.localtime(
                photo.uploaded_at
            ).isoformat()
            if photo.uploaded_at
            else None
        ),
    }
    for photo in case.photos.all()
    if photo.image
],
            }

            # 제보일 경우 Feature 정보 추가
            if case.type_code == Case.TypeCode.TIP:
                feature = case.features.first()

                item["feature"] = {
                    "physical": feature.physical if feature else "",
                    "clothing": feature.clothing if feature else "",
                    "health": feature.health if feature else "",
                    "behavior": feature.behavior if feature else "",
                    "etc": feature.etc if feature else "",
                }

            results.append(item)

        return Response(
            {
                "count": len(results),
                "results": results,
            },
            status=status.HTTP_200_OK
        )


    @action(detail=True, methods=["delete"], url_path="delete-my", permission_classes=[IsAuthenticated])
    def delete_my_case(self, request, pk=None):

        case = get_object_or_404(Case, pk=pk)

        # 🔥 본인만 가능
        if case.reporter != request.user.person:
            return Response({"error": "본인 제보만 삭제 가능"}, status=403)

        # 🔥 상태 제한
        if case.status != Case.Status.RECEIVED:
            return Response({"error": "접수 상태만 삭제 가능"}, status=400)

        case_id = case.id
        case.delete()
        Log.objects.create(
            user=request.user.person,
            action="본인 제보 삭제",
            target_type="Case",
            target_id=case_id
        )
        return Response({
            "message": "삭제 완료",
            "case_id": case_id
        })

    #제보 상세 정보
    @action(detail=True, methods=["get"], url_path="report_detail", permission_classes=[IsAuthenticated])
    def report_detail(self, request, pk=None):
        case = get_object_or_404(
            Case.objects.prefetch_related("photos"),
            pk=pk,
            reporter=request.user.person
        )

        serializer = MyReportDetailSerializer(
            case,
            context={"request": request}
        )
        return Response(serializer.data)

    @action(detail=True, methods=["get"], url_path="detail")
    def public_detail(self, request, pk=None):
        case = get_object_or_404(
            Case.objects.select_related(
                "reporter"
            ).prefetch_related(
                "photos",
                "features"
            ),
            pk=pk
        )

        serializer = CasePublicDetailSerializer(
            case,
            context={"request": request}
        )
        return Response(serializer.data)

    @action(detail=True, methods=["get"], url_path="tip-detail", permission_classes=[IsAuthenticated])
    def tip_detail(self, request, pk=None):
        case = get_object_or_404(
            Case.objects.prefetch_related(
                "photos",
                "features"
            ),
            pk=pk,
            reporter=request.user.person,
            type_code=Case.TypeCode.TIP
        )

        serializer = MyTipDetailSerializer(
            case,
            context={"request": request}
        )
        return Response(serializer.data)

    @action(detail=True, methods=["get"], url_path="case-detail", permission_classes=[IsAuthenticated])
    def case_detail(self, request, pk=None):
        # from dasibomapp.ml_classifier import classify_etc
        import time

        start = time.perf_counter()
        print("[case_detail] 시작")

        case = get_object_or_404(
            Case.objects.select_related(
                "reporter",
                "missing_person",
            ).prefetch_related(
                "photos",
                "features",
            ),
            pk=pk
        )

        is_admin = request.user.role == "admin"
        is_owner = case.reporter == request.user.person

        if not (is_admin or is_owner):
            return Response({"error": "조회 권한 없음"}, status=403)
        # =========================================================
        # 수정 권한
        #
        # 실종 신고(MISSING)
        # - 일반 사용자: received만 수정 가능
        #
        # 시민 제보(TIP)
        # - 일반 사용자: received / completed 수정 가능
        #
        # 관리자
        # - 항상 수정 가능
        # =========================================================
        if is_admin:
            can_edit = True

        elif not is_owner:
            can_edit = False

        elif case.type_code == Case.TypeCode.MISSING:
            can_edit = (
                    case.status == Case.Status.RECEIVED
            )

        elif case.type_code == Case.TypeCode.TIP:
            can_edit = (
                    case.status
                    in [
                        Case.Status.RECEIVED,
                        Case.Status.COMPLETED,
                    ]
            )

        else:
            can_edit = False
        def get_missing_person_photos(missing_person):
            """
            연결된 MissingPerson의 공식 등록 사진 목록을 반환한다.

            프론트 사진 비교 섹션용:
            - missing_photos
            - missing_person_photos
            - official_photos

            Case에 missing_person이 연결되지 않은 경우 빈 배열 반환.
            """
            if not missing_person:
                return []

            image_urls = getattr(missing_person, "image_urls", None) or []
            ai_image_urls = getattr(missing_person, "ai_image_urls", None) or []

            result = []

            for path in image_urls:
                if not path:
                    continue

                path_str = str(path)

                absolute_url = media_url(
                    path_str,
                    request,
                )
                result.append({
                    "url": absolute_url,
                    "path": path_str,
                    "is_ai_generated": path_str in ai_image_urls,
                })

            return result

        # -------------------------------------------------
        # 최신 몽타주 조회
        # Case에 연결된 Montage 중 가장 최근 생성된 결과 1개
        # -------------------------------------------------
        latest_montage = case.montages.order_by("-created_at").first()

        if latest_montage and latest_montage.result_img:
            latest_montage_data = {
                "id": latest_montage.id,
                "result_img": latest_montage.result_img.name,
                "result_img_url": media_url(
                    latest_montage.result_img.name,
                    request,
                ),
                "age_estimate": latest_montage.age_estimate,
                "confidence": str(latest_montage.confidence) if latest_montage.confidence is not None else None,
                "is_applied": latest_montage.is_applied,
                "created_at": format_datetime_for_front(latest_montage.created_at),
            }
        else:
            latest_montage_data = None

        # 연결된 실종자의 공식 등록 사진 목록
        missing_photos = get_missing_person_photos(case.missing_person)

        base = {
            "case_id": case.id,
            "type_code": case.type_code,
            "status": case.status,
            "created_at": format_datetime_for_front(case.created_at),
            "permissions": {
                        "is_owner": is_owner,
                        "is_admin": is_admin,
                        "can_edit": can_edit,
                    },
            "reporter": {
                "name": case.reporter.name if case.reporter else None,
                "phone": case.reporter.phone if case.reporter else None,
            },

            # -------------------------------------------------
            # 제보자 / 신고자가 첨부한 사진
            # -------------------------------------------------
            "photos": [
                media_url(
                    photo.image.name,
                    request,
                )
                for photo in case.photos.filter(
                    photo_type=TipPhoto.PhotoType.SUBJECT
                )
                if photo.image
            ],
            "photo_items": [
                    {
                        "id": photo.id,
                        "url": media_url(
                            photo.image.name,
                            request,
                        ),
                        "image": photo.image.name,
                        "photo_type": photo.photo_type,
                        "is_ai_generated": photo.is_ai_generated,
                        "uploaded_at": format_datetime_for_front(
                            photo.uploaded_at
                        ),
                    }
                    for photo in case.photos.all()
                    if photo.image
                ],

            # -------------------------------------------------
            # 연결된 실종자 정보
            # -------------------------------------------------
            "missing_person": (
                case.missing_person.id
                if case.missing_person
                else None
            ),

            "missing_person_id": (
                case.missing_person.id
                if case.missing_person
                else None
            ),

            "msspsn_idntfccd": (
                case.missing_person.msspsn_idntfccd
                if case.missing_person
                else None
            ),
            "missing_person_seq": (
                case.missing_person.msspsn_idntfccd
                if case.missing_person
                else None
            ),
            # -------------------------------------------------
            # 실종자 공식 등록 사진
            # 프론트 fallback 대응을 위해 같은 데이터를 3개 필드로 제공
            # -------------------------------------------------
            "missing_photos": missing_photos,
            "missing_person_photos": missing_photos,
            "official_photos": missing_photos,

            "latest_montage": latest_montage_data,
        }

        # ── 신고 (missing) ────────────────────────────────────────────
        if case.type_code == Case.TypeCode.MISSING:
            p = case.payload or {}

            base["missing_info"] = {
                "name": p.get("name"),
                "gender": p.get("gender"),
                "age_at_missing": p.get("age_at_missing"),
                "occurred_at": p.get("occurred_at"),
                "occurred_location": p.get("occurred_location"),
                "nationality": p.get("nationality"),
            }

            # ✅ 핵심 수정:
            # 프론트 요청 바디(height, weight, body_type, face_type, hair_color,
            # hair_style, clothing, category, description 등)를
            # 공통 함수로 categories 구조에 맞게 변환한다.
            base["categories"] = build_missing_report_categories(p)

        # ── 제보 (tip) ────────────────────────────────────────────────
        elif case.type_code == Case.TypeCode.TIP:
            feature = case.features.first()
            p = case.payload or {}

            base["tip_info"] = {
                "missing_name": (
                        p.get("missing_name")
                        or p.get("reported_missing_name")
                        or case.reported_missing_name
                ),
                "gender": p.get("gender"),
                "found_location": (
                        p.get("found_location")
                        or case.occr_location
                ),
                "found_datetime": (
                    format_datetime_for_front(case.occr_date)
                    if case.occr_date
                    else p.get("found_datetime")
                ),
                "reporter_name": p.get("reporter_name"),
                "reporter_phone": p.get("reporter_phone"),
            }

            physical = (
                split_feature_text(feature.physical)
                if feature and feature.physical
                else []
            )

            clothing_info = (
                split_feature_text(feature.clothing)
                if feature and feature.clothing
                else []
            )

            health = (
                split_feature_text(feature.health)
                if feature and feature.health
                else []
            )

            behavior = (
                split_feature_text(feature.behavior)
                if feature and feature.behavior
                else []
            )

            extra = (
                split_feature_text(feature.etc)
                if feature and feature.etc
                else []
            )

            base["categories"] = {
                "신체 특징": physical,
                "착의 사항": clothing_info,
                "건강·장애 정보": health,
                "성격·행동 특성": behavior,
                "기타 참고 사항": extra,
            }

        print("[case_detail] 전체 처리 시간:", time.perf_counter() - start)
        return Response(base, status=status.HTTP_200_OK)

    @action(
        detail=True,
        methods=["patch"],
        url_path="update-status",
        permission_classes=[IsAdmin]
    )
    def update_status(self, request, pk=None):
        """
        PATCH /dasibom/case/{id}/update-status/

        관리자 전용 제보/신고 공통 상태 변경 API

        대상:
        - tip: 시민 제보
        - missing: 실종자 등록 신고

        허용 상태 흐름:
        received  -> reviewing
        reviewing -> completed / rejected
        completed -> reviewing
        rejected  -> 변경 불가

        신고(missing) 추가 처리:
        - reviewing -> completed:
          MissingPerson 실제 생성 및 찾고 있어요 목록에 등록

        - completed -> reviewing:
          신고 승인으로 생성된 MissingPerson 삭제 및 연결 해제
        """

        # -------------------------------------------------
        # 1. Case 조회
        # 제보와 신고 모두 사용하므로 type_code 조건을 넣지 않음
        # -------------------------------------------------
        case = get_object_or_404(
            Case.objects.select_related("missing_person"),
            pk=pk
        )

        # 제보 / 신고 외 타입 방지
        allowed_type_codes = [
            Case.TypeCode.TIP,
            Case.TypeCode.MISSING,
        ]

        if case.type_code not in allowed_type_codes:
            return Response(
                {
                    "error": "제보 또는 신고 상태만 변경할 수 있습니다.",
                    "case_id": case.id,
                    "type_code": case.type_code,
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        new_status = request.data.get("status")
        current_status = case.status

        # -------------------------------------------------
        # 2. 필수값 검증
        # -------------------------------------------------
        if not new_status:
            return Response(
                {
                    "error": "status 값이 필요합니다."
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        # -------------------------------------------------
        # 3. 허용 상태값 검증
        # -------------------------------------------------
        allowed_statuses = [
            Case.Status.RECEIVED,
            Case.Status.REVIEWING,
            Case.Status.COMPLETED,
            Case.Status.REJECTED,
        ]

        if new_status not in allowed_statuses:
            return Response(
                {
                    "error": "유효하지 않은 상태값입니다.",
                    "allowed": allowed_statuses,
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        # -------------------------------------------------
        # 4. 동일 상태 변경 방지
        # -------------------------------------------------
        if current_status == new_status:
            return Response(
                {
                    "error": f"이미 '{new_status}' 상태입니다.",
                    "case_id": case.id,
                    "type_code": case.type_code,
                    "status": case.status,
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        # -------------------------------------------------
        # 5. 상태 전환 규칙
        # -------------------------------------------------
        allowed_transitions = {
            Case.Status.RECEIVED: [
                Case.Status.REVIEWING,
            ],
            Case.Status.REVIEWING: [
                Case.Status.COMPLETED,
                Case.Status.REJECTED,
            ],
            Case.Status.COMPLETED: [
                Case.Status.REVIEWING,
            ],
            Case.Status.REJECTED: [],
        }

        allowed_next = allowed_transitions.get(current_status, [])

        if new_status not in allowed_next:
            return Response(
                {
                    "error": "허용되지 않은 상태 전환입니다.",
                    "case_id": case.id,
                    "type_code": case.type_code,
                    "current_status": current_status,
                    "requested_status": new_status,
                    "allowed_next": allowed_next,
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        # -------------------------------------------------
        # 6. 응답용 초기값
        # -------------------------------------------------
        missing_person_created = False
        missing_person_removed = False

        missing_person_id = (
            case.missing_person.id
            if case.missing_person
            else None
        )

        missing_person_identifier = (
            case.missing_person.msspsn_idntfccd
            if case.missing_person
            else None
        )

        image_count = 0

        # -------------------------------------------------
        # 7. 상태 변경 및 신고 승인/복구 처리
        # -------------------------------------------------
        try:
            with transaction.atomic():

                # -----------------------------------------
                # 신고: reviewing -> completed
                # 실제 MissingPerson 생성 및 리스트 등록
                # -----------------------------------------
                if (
                        case.type_code == Case.TypeCode.MISSING
                        and current_status == Case.Status.REVIEWING
                        and new_status == Case.Status.COMPLETED
                ):
                    result = self._approve_missing_internal(case)

                    if not result["success"]:
                        return Response(
                            {
                                "error": "실종자 등록 실패",
                                "detail": result["detail"],
                                "case_id": case.id,
                            },
                            status=status.HTTP_400_BAD_REQUEST
                        )

                    missing = result["missing"]

                    missing_person_created = True
                    missing_person_id = missing.id
                    missing_person_identifier = missing.msspsn_idntfccd
                    image_count = result.get("image_count", 0)

                    # 내부 함수에서 case.status와 missing_person 연결을 저장함
                    case.refresh_from_db()

                # -----------------------------------------
                # 신고: completed -> reviewing
                # 승인으로 생성된 MissingPerson 제거
                # -----------------------------------------
                elif (
                        case.type_code == Case.TypeCode.MISSING
                        and current_status == Case.Status.COMPLETED
                        and new_status == Case.Status.REVIEWING
                ):
                    remove_result = self._remove_missing_from_completed_case_internal(
                        case
                    )

                    if not remove_result["success"]:
                        return Response(
                            {
                                "error": "실종자 등록 상태 복구 실패",
                                "detail": remove_result["detail"],
                                "case_id": case.id,
                            },
                            status=status.HTTP_400_BAD_REQUEST
                        )

                    missing_person_removed = True
                    missing_person_id = remove_result.get("missing_id")
                    missing_person_identifier = remove_result.get("identifier")

                    case.refresh_from_db()
                    case.status = new_status
                    case.save(
                        update_fields=[
                            "status",
                            "updated_at",
                        ]
                    )

                # -----------------------------------------
                # 제보 또는 일반 신고 상태 변경
                # -----------------------------------------
                else:
                    case.status = new_status
                    case.save(
                        update_fields=[
                            "status",
                            "updated_at",
                        ]
                    )

                # -----------------------------------------
                # 상태 변경 로그
                # -----------------------------------------
                Log.objects.create(
                    user=getattr(request.user, "person", None),
                    action=(
                        f"제보/신고 상태 변경: "
                        f"{current_status} → {new_status}"
                    ),
                    target_type="Case",
                    target_id=case.id,
                )

        except Exception as e:
            logger.exception(
                f"[update_status] 상태 변경 실패 case_id={case.id}: {e}"
            )

            return Response(
                {
                    "error": "상태 변경 중 오류가 발생했습니다.",
                    "detail": str(e),
                    "case_id": case.id,
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

        # 최신 상태 다시 조회
        case.refresh_from_db()

        # -------------------------------------------------
        # 8. 최종 응답
        # -------------------------------------------------
        return Response(
            {
                "message": "상태 변경 완료",
                "case_id": case.id,
                "type_code": case.type_code,
                "old_status": current_status,
                "status": case.status,

                "missing_person_created": missing_person_created,
                "missing_person_removed": missing_person_removed,

                "missing_person_id": (
                    case.missing_person.id
                    if case.missing_person
                    else missing_person_id
                ),
                "missing_person_identifier": (
                    case.missing_person.msspsn_idntfccd
                    if case.missing_person
                    else missing_person_identifier
                ),
                "image_count": image_count,
            },
            status=status.HTTP_200_OK
        )
class FeatureViewSet(viewsets.ModelViewSet):
    queryset = Feature.objects.all()
    serializer_class = FeatureSerializer

class MontageViewSet(viewsets.ModelViewSet):
    """
    이미 등록된 실종자의 AI 몽타주 생성 및 적용 ViewSet

    사용 흐름:
    1. POST  /dasibom/montage/generate/
       - 기존 MissingPerson을 대상으로 AI 몽타주 생성
       - Montage.result_img에 결과 임시 저장

    2. PATCH /dasibom/montage/{montage_id}/apply/
       - 생성된 AI 몽타주를 해당 MissingPerson 사진 목록에 등록
       - MissingPerson.image_urls에 저장
       - MissingPerson.ai_image_urls에 저장

    신고 Case 및 신고 상태와는 무관하게 동작한다.
    """

    queryset = Montage.objects.all().order_by("-created_at")
    serializer_class = MontageSerializer
    permission_classes = [IsAuthenticated]

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context

    # =================================================
    # 1. AI 몽타주 생성
    # =================================================
    @action(
        detail=False,
        methods=["post"],
        url_path="generate",
        permission_classes=[IsAdmin]
    )
    def generate_montage(self, request):
        """
        POST /dasibom/montage/generate/

        이미 등록된 실종자의 AI 몽타주를 생성한다.

        Content-Type:
        multipart/form-data

        필수:
        - missing_person_id
        - image
        - source_age
        - target_age
        - gender

        선택:
        - ethnicity
        - father_image
        - father_age
        - mother_image
        - mother_age
        - alpha
        """
        import time

        total_start = time.perf_counter()

        # -------------------------------------------------
        # 1. 프론트 요청값 받기
        # -------------------------------------------------
        missing_person_id = request.data.get("missing_person_id")

        image = request.FILES.get("image")
        source_age = request.data.get("source_age")
        target_age = request.data.get("target_age")
        gender = request.data.get("gender")
        ethnicity = request.data.get("ethnicity", "korean")

        father_image = request.FILES.get("father_image")
        mother_image = request.FILES.get("mother_image")

        father_age = request.data.get("father_age")
        mother_age = request.data.get("mother_age")

        alpha = request.data.get("alpha", 0.3)

        # -------------------------------------------------
        # 2. MissingPerson 필수 검증
        # -------------------------------------------------
        if not missing_person_id:
            return Response(
                {
                    "error": "missing_person_id 값이 필요합니다.",
                    "message": "이미 등록된 실종자만 AI 몽타주를 생성할 수 있습니다."
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        missing_person = MissingPerson.objects.filter(
            id=missing_person_id
        ).first()

        if not missing_person:
            return Response(
                {
                    "error": "존재하지 않는 missing_person_id입니다."
                },
                status=status.HTTP_404_NOT_FOUND
            )
        # -------------------------------------------------
        # 2-1. 실종 신고 당시 저장한 가족사진 자동 조회
        #
        # 프론트에서 father_image / mother_image를
        # 새로 보내지 않은 경우에만 기존 신고 사진 사용
        # -------------------------------------------------

        opened_parent_files = []

        origin_case = (
            Case.objects
            .filter(
                type_code=Case.TypeCode.MISSING,
                status=Case.Status.COMPLETED,
                missing_person=missing_person,
            )
            .prefetch_related("photos")
            .order_by("-created_at")
            .first()
        )

        if origin_case:

            # 가족사진 1
            if not father_image:
                parent1_photo = (
                    origin_case.photos
                    .filter(
                        photo_type=TipPhoto.PhotoType.PARENT1_FACE
                    )
                    .order_by("-uploaded_at")
                    .first()
                )

                if (
                        parent1_photo
                        and parent1_photo.image
                ):
                    try:
                        parent1_photo.image.open("rb")

                        father_image = parent1_photo.image
                        opened_parent_files.append(
                            parent1_photo.image
                        )

                        logger.warning(
                            "[AI 몽타주] "
                            "신고 저장 가족사진1 자동 사용 | "
                            "case_id=%s | photo_id=%s",
                            origin_case.id,
                            parent1_photo.id,
                        )

                    except Exception as e:
                        logger.warning(
                            "[AI 몽타주] "
                            "가족사진1 로드 실패: %s",
                            e,
                        )

            # 가족사진 2
            if not mother_image:
                parent2_photo = (
                    origin_case.photos
                    .filter(
                        photo_type=TipPhoto.PhotoType.PARENT2_FACE
                    )
                    .order_by("-uploaded_at")
                    .first()
                )

                if (
                        parent2_photo
                        and parent2_photo.image
                ):
                    try:
                        parent2_photo.image.open("rb")

                        mother_image = parent2_photo.image
                        opened_parent_files.append(
                            parent2_photo.image
                        )

                        logger.warning(
                            "[AI 몽타주] "
                            "신고 저장 가족사진2 자동 사용 | "
                            "case_id=%s | photo_id=%s",
                            origin_case.id,
                            parent2_photo.id,
                        )

                    except Exception as e:
                        logger.warning(
                            "[AI 몽타주] "
                            "가족사진2 로드 실패: %s",
                            e,
                        )
        # -------------------------------------------------
        # 3. 필수 파라미터 검증
        # -------------------------------------------------
        if not image:
            return Response(
                {"error": "image 파일이 필요합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if source_age is None:
            return Response(
                {"error": "source_age 값이 필요합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if target_age is None:
            return Response(
                {"error": "target_age 값이 필요합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not gender:
            return Response(
                {"error": "gender 값이 필요합니다. M 또는 F로 보내주세요."},
                status=status.HTTP_400_BAD_REQUEST
            )

        # -------------------------------------------------
        # 4. 기본 타입 검증
        # -------------------------------------------------
        try:
            source_age = int(source_age)
            target_age = int(target_age)
        except (ValueError, TypeError):
            return Response(
                {"error": "source_age와 target_age는 int 값이어야 합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if source_age <= 0 or target_age <= 0:
            return Response(
                {"error": "source_age와 target_age는 1 이상이어야 합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        gender = str(gender).upper().strip()

        if gender not in ["M", "F"]:
            return Response(
                {"error": "gender는 M 또는 F만 가능합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        ethnicity = str(ethnicity).lower().strip()

        if ethnicity not in ["korean", "western"]:
            return Response(
                {"error": "ethnicity는 korean 또는 western만 가능합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        # -------------------------------------------------
        # 5. 부모 나이 선택값 검증
        # -------------------------------------------------
        if father_age not in [None, ""]:
            try:
                father_age = int(father_age)
            except (ValueError, TypeError):
                return Response(
                    {"error": "father_age는 int 값이어야 합니다."},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if father_age <= 0:
                return Response(
                    {"error": "father_age는 1 이상이어야 합니다."},
                    status=status.HTTP_400_BAD_REQUEST
                )

        if mother_age not in [None, ""]:
            try:
                mother_age = int(mother_age)
            except (ValueError, TypeError):
                return Response(
                    {"error": "mother_age는 int 값이어야 합니다."},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if mother_age <= 0:
                return Response(
                    {"error": "mother_age는 1 이상이어야 합니다."},
                    status=status.HTTP_400_BAD_REQUEST
                )

        # -------------------------------------------------
        # 6. alpha 검증
        # -------------------------------------------------
        try:
            alpha = float(alpha)
        except (ValueError, TypeError):
            return Response(
                {"error": "alpha는 float 값이어야 합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if alpha < 0.0 or alpha > 0.5:
            return Response(
                {"error": "alpha는 0.0 이상 0.5 이하만 가능합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        # -------------------------------------------------
        # 7. AI 서버 요청 준비
        # -------------------------------------------------
        ai_url = getattr(
            settings,
            "AI_AGING_API_URL",
            f"{settings.AI_SERVER_URL}/api/aging",
        )

        timeout = getattr(
            settings,
            "AI_AGING_TIMEOUT",
            300
        )

        data = {
            "source_age": source_age,
            "target_age": target_age,
            "gender": gender,
            "ethnicity": ethnicity,
            "alpha": alpha,
        }

        if father_age not in [None, ""]:
            data["father_age"] = father_age

        if mother_age not in [None, ""]:
            data["mother_age"] = mother_age

        files = {
            "image": (
                image.name,
                image,
                getattr(
                    image,
                    "content_type",
                    "application/octet-stream"
                )
            )
        }

        if father_image:
            files["father_image"] = (
                father_image.name,
                father_image,
                getattr(
                    father_image,
                    "content_type",
                    "application/octet-stream"
                )
            )

        if mother_image:
            files["mother_image"] = (
                mother_image.name,
                mother_image,
                getattr(
                    mother_image,
                    "content_type",
                    "application/octet-stream"
                )
            )

        logger.warning(
            "[AI 몽타주] 요청 시작 | missing_person_id=%s | "
            "source_age=%s | target_age=%s | gender=%s | "
            "ethnicity=%s | father=%s | mother=%s | alpha=%s",
            missing_person_id,
            source_age,
            target_age,
            gender,
            ethnicity,
            bool(father_image),
            bool(mother_image),
            alpha,
        )

        ai_headers = {
            "ngrok-skip-browser-warning": "true"
        }

        # -------------------------------------------------
        # 8. AI 서버 호출
        # -------------------------------------------------
        ai_start = time.perf_counter()

        try:
            ai_response = requests.post(
                ai_url,
                data=data,
                files=files,
                headers=ai_headers,
                timeout=timeout,
            )

        except requests.exceptions.Timeout:
            logger.warning(
                "[AI 몽타주] AI 서버 Timeout | %.2f초",
                time.perf_counter() - ai_start
            )

            return Response(
                {"error": "AI 서버 응답 시간이 초과되었습니다."},
                status=status.HTTP_504_GATEWAY_TIMEOUT
            )

        except requests.exceptions.ConnectionError:
            logger.warning(
                "[AI 몽타주] AI 서버 연결 실패 | %.2f초",
                time.perf_counter() - ai_start
            )

            return Response(
                {
                    "error": (
                        "AI 서버에 연결할 수 없습니다. "
                        "AI 서버가 켜져 있는지 확인해주세요."
                    )
                },
                status=status.HTTP_502_BAD_GATEWAY
            )

        except requests.exceptions.RequestException as e:
            logger.exception(
                "[AI 몽타주] AI 서버 요청 예외: %s",
                e
            )

            return Response(
                {
                    "error": "AI 서버 요청 중 오류가 발생했습니다.",
                    "detail": str(e),
                },
                status=status.HTTP_502_BAD_GATEWAY
            )
        for opened_file in opened_parent_files:
            try:
                opened_file.close()
            except Exception:
                pass
        ai_elapsed = time.perf_counter() - ai_start

        logger.warning(
            "[AI 몽타주] AI 서버 응답 시간: %.2f초 | status=%s",
            ai_elapsed,
            ai_response.status_code,
        )

        # -------------------------------------------------
        # 9. AI 서버 에러 응답 처리
        # -------------------------------------------------
        if ai_response.status_code >= 400:
            try:
                error_body = ai_response.json()
            except Exception:
                error_body = ai_response.text

            return Response(
                {
                    "error": "AI 서버에서 오류가 반환되었습니다.",
                    "ai_status_code": ai_response.status_code,
                    "ai_response": error_body,
                    "debug_timing": {
                        "ai_seconds": round(ai_elapsed, 2),
                    },
                },
                status=status.HTTP_502_BAD_GATEWAY
            )

        # -------------------------------------------------
        # 10. AI 서버 결과 이미지 확인
        # -------------------------------------------------
        content_type = ai_response.headers.get(
            "Content-Type",
            ""
        )

        if not content_type.startswith("image/"):
            return Response(
                {
                    "error": "AI 서버 응답이 이미지가 아닙니다.",
                    "content_type": content_type,
                    "data": ai_response.text[:500],
                    "debug_timing": {
                        "ai_seconds": round(ai_elapsed, 2),
                    },
                },
                status=status.HTTP_502_BAD_GATEWAY
            )

        # -------------------------------------------------
        # 11. 확장자 + AI 응답 헤더
        # -------------------------------------------------
        ext = "png"

        if "jpeg" in content_type or "jpg" in content_type:
            ext = "jpg"

        identity_score = ai_response.headers.get(
            "X-Identity-Score"
        )

        target_age_header = ai_response.headers.get(
            "X-Target-Age"
        )

        calibrated_target = ai_response.headers.get(
            "X-Calibrated-Target"
        )

        age_warning = ai_response.headers.get(
            "X-Age-Warning"
        )

        blending = ai_response.headers.get(
            "X-Blending"
        )

        response_alpha = ai_response.headers.get(
            "X-Alpha"
        )

        parent_score = ai_response.headers.get(
            "X-Parent-Score"
        )

        pti = ai_response.headers.get(
            "X-PTI"
        )

        ffhq_scale = ai_response.headers.get(
            "X-FFHQ-Scale"
        )

        # -------------------------------------------------
        # 12. DB + Cloudinary 저장
        # -------------------------------------------------
        save_start = time.perf_counter()

        with transaction.atomic():
            montage = Montage.objects.create(
                case=None,
                missing_person=missing_person,
                generated_by=getattr(
                    request.user,
                    "person",
                    None
                ),
                age_estimate=target_age,
                confidence=None,
                is_applied=False,
            )

            result_filename = f"montage_{montage.id}.{ext}"

            montage.result_img.save(
                result_filename,
                ContentFile(ai_response.content),
                save=True
            )

            MontageInputPhoto.objects.create(
                montage=montage,
                image=image
            )

            Log.objects.create(
                user=getattr(
                    request.user,
                    "person",
                    None
                ),
                action="AI 몽타주 생성",
                target_type="Montage",
                target_id=montage.id
            )

        save_elapsed = time.perf_counter() - save_start

        logger.warning(
            "[AI 몽타주] DB + Cloudinary 저장 시간: %.2f초",
            save_elapsed,
        )

        # -------------------------------------------------
        # 13. 응답 URL 생성
        # -------------------------------------------------
        result_img_url = (
            media_url(
                montage.result_img.name,
                request,
            )
            if montage.result_img
            else None
        )

        # 여기까지의 전체 시간
        total_elapsed = (
                time.perf_counter()
                - total_start
        )

        logger.warning(
            "[AI 몽타주] 전체 처리 시간: %.2f초",
            total_elapsed,
        )

        # -------------------------------------------------
        # 14. 응답 데이터
        # -------------------------------------------------
        response_data = {
            "message": "AI 몽타주 생성 및 저장 완료",

            "montage_id": montage.id,

            "missing_person_id": missing_person.id,
            "missing_person_name": missing_person.name,
            "missing_person_identifier": (
                missing_person.msspsn_idntfccd
            ),

            "result_img": (
                montage.result_img.name
                if montage.result_img
                else None
            ),
            "result_img_url": result_img_url,

            "input_photo_count": (
                montage.input_photos.count()
            ),

            "source_age": source_age,
            "target_age": target_age,
            "gender": gender,
            "ethnicity": ethnicity,

            "father_age": father_age,
            "mother_age": mother_age,

            "alpha": response_alpha or alpha,
            "blending": blending,

            "identity_score": identity_score,
            "parent_score": parent_score,

            "target_age_header": target_age_header,
            "calibrated_target": calibrated_target,
            "age_warning": age_warning,
            "pti": pti,
            "ffhq_scale": ffhq_scale,

            "age_estimate": montage.age_estimate,
            "confidence": None,
            "is_applied": montage.is_applied,

            "created_at": format_datetime_for_front(
                montage.created_at
            ),

            # 임시 속도 측정용
            "debug_timing": {
                "ai_seconds": round(
                    ai_elapsed,
                    2
                ),
                "save_seconds": round(
                    save_elapsed,
                    2
                ),
                "total_seconds": round(
                    total_elapsed,
                    2
                ),
            },
        }

        response = Response(
            response_data,
            status=status.HTTP_201_CREATED
        )

        # -------------------------------------------------
        # 15. AI 응답 헤더 프론트로 전달
        # -------------------------------------------------
        forward_headers = [
            "X-Identity-Score",
            "X-Target-Age",
            "X-Calibrated-Target",
            "X-Age-Warning",
            "X-Blending",
            "X-Alpha",
            "X-Parent-Score",
            "X-PTI",
            "X-FFHQ-Scale",
        ]

        for header_name in forward_headers:
            header_value = ai_response.headers.get(
                header_name
            )

            if header_value is not None:
                response[header_name] = header_value

        return response
    # =================================================
    # 2. AI 몽타주를 실종자 사진에 적용
    # =================================================
    @action(
        detail=True,
        methods=["patch"],
        url_path="apply",
        permission_classes=[IsAdmin]
    )
    def apply_montage(self, request, pk=None):
        """
        PATCH /dasibom/montage/{montage_id}/apply/

        생성된 AI 몽타주 결과를 연결된 MissingPerson 사진 목록에 등록한다.

        Request Body:
        필요 없음

        저장 대상:
        - MissingPerson.image_urls
        - MissingPerson.ai_image_urls
        """

        # -------------------------------------------------
        # 1. Montage 조회
        # -------------------------------------------------
        montage = get_object_or_404(
            Montage.objects.select_related(
                "missing_person"
            ),
            pk=pk
        )

        if not montage.result_img:
            return Response(
                {
                    "error": "반영할 AI 몽타주 결과 이미지가 없습니다."
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        missing_person = montage.missing_person

        if not missing_person:
            return Response(
                {
                    "error": "연결된 실종자 정보가 없습니다.",
                    "message": (
                        "missing_person_id가 연결된 몽타주만 "
                        "실종자 사진에 적용할 수 있습니다."
                    )
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        # -------------------------------------------------
        # 2. 이미 적용된 Montage 중복 처리
        # -------------------------------------------------
        if montage.is_applied:
            return Response(
                {
                    "error": "이미 적용된 AI 몽타주입니다.",
                    "montage_id": montage.id,
                    "missing_person_id": missing_person.id,
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        # -------------------------------------------------
        # 3. Montage 결과 파일 읽기
        # -------------------------------------------------
        montage.result_img.open("rb")

        result_content = montage.result_img.read()

        montage.result_img.close()

        ext = (
            montage.result_img.name.split(".")[-1]
            if "." in montage.result_img.name
            else "png"
        )

        missing_filename = f"montage_{montage.id}.{ext}"

        missing_path = (
            f"missing_persons/"
            f"{missing_person.msspsn_idntfccd}/"
            f"{missing_filename}"
        )

        # -------------------------------------------------
        # 4. MissingPerson 사진 목록에 저장
        # -------------------------------------------------
        with transaction.atomic():
            current_images = list(
                missing_person.image_urls or []
            )

            current_ai_images = list(
                missing_person.ai_image_urls or []
            )

            # 동일 경로가 없을 때만 파일 저장
            if missing_path not in current_images:
                saved_path = default_storage.save(
                    missing_path,
                    ContentFile(result_content)
                )

                current_images.append(saved_path)
                missing_path = saved_path

            # 일반 사진 목록에 포함
            if missing_path not in current_images:
                current_images.append(missing_path)

            # AI 사진 목록에 포함
            if missing_path not in current_ai_images:
                current_ai_images.append(missing_path)

            missing_person.image_urls = current_images
            missing_person.ai_image_urls = current_ai_images

            missing_person.save(
                update_fields=[
                    "image_urls",
                    "ai_image_urls",
                    "updated_at",
                ]
            )

            montage.is_applied = True

            montage.save(
                update_fields=[
                    "is_applied",
                    "updated_at",
                ]
            )

            Log.objects.create(
                user=getattr(request.user, "person", None),
                action="AI 몽타주 결과를 실종자 사진에 반영",
                target_type="MissingPerson",
                target_id=missing_person.id
            )

            Log.objects.create(
                user=getattr(request.user, "person", None),
                action="AI 몽타주 결과 적용",
                target_type="Montage",
                target_id=montage.id
            )

        # -------------------------------------------------
        # 5. 응답 URL 생성
        # -------------------------------------------------
        missing_person_image_url = media_url(
            missing_path,
            request,
        )

        # -------------------------------------------------
        # 6. 최종 응답
        # -------------------------------------------------
        return Response(
            {
                "message": "AI 몽타주 결과가 실종자 사진에 등록되었습니다.",

                "montage_id": montage.id,
                "is_applied": montage.is_applied,

                "missing_person_id": missing_person.id,
                "missing_person_name": missing_person.name,
                "missing_person_identifier": (
                    missing_person.msspsn_idntfccd
                ),

                "missing_person_image_path": missing_path,
                "missing_person_image_url": missing_person_image_url,

                "photo_count": len(
                    missing_person.image_urls or []
                ),
                "ai_photo_count": len(
                    missing_person.ai_image_urls or []
                ),
            },
            status=status.HTTP_200_OK
        )
class AIAgingAPIView(APIView):
    """
    AI 이미지 나이 변환 프록시 API

    POST /dasibom/ai/aging/
    Content-Type: multipart/form-data

    필수값:
    - image
    - source_age
    - target_age
    - gender

    선택값:
    - ethnicity
    - father_image
    - father_age
    - mother_image
    - mother_age
    - alpha
    """

    permission_classes = [IsAuthenticated]

    def post(self, request):
        # -------------------------------------------------
        # 1. 요청 파라미터 받기
        # -------------------------------------------------
        image = request.FILES.get("image")
        source_age = request.data.get("source_age")
        target_age = request.data.get("target_age")
        gender = request.data.get("gender")
        ethnicity = request.data.get("ethnicity", "korean")

        # 부모 관련 선택값
        father_image = request.FILES.get("father_image")
        mother_image = request.FILES.get("mother_image")

        father_age = request.data.get("father_age")
        mother_age = request.data.get("mother_age")

        alpha = request.data.get("alpha", 0.3)

        # -------------------------------------------------
        # 2. 필수값 검증
        # -------------------------------------------------
        if not image:
            return Response(
                {"error": "image 파일이 필요합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if source_age is None:
            return Response(
                {"error": "source_age 값이 필요합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if target_age is None:
            return Response(
                {"error": "target_age 값이 필요합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not gender:
            return Response(
                {"error": "gender 값이 필요합니다. M 또는 F로 보내주세요."},
                status=status.HTTP_400_BAD_REQUEST
            )

        # -------------------------------------------------
        # 3. 기본 타입 검증
        # -------------------------------------------------
        try:
            source_age = int(source_age)
            target_age = int(target_age)
        except (ValueError, TypeError):
            return Response(
                {"error": "source_age와 target_age는 int 값이어야 합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if source_age <= 0 or target_age <= 0:
            return Response(
                {"error": "source_age와 target_age는 1 이상이어야 합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        gender = str(gender).upper().strip()

        if gender not in ["M", "F"]:
            return Response(
                {"error": "gender는 M 또는 F만 가능합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        ethnicity = str(ethnicity).lower().strip()

        if ethnicity not in ["korean", "western"]:
            return Response(
                {"error": "ethnicity는 korean 또는 western만 가능합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        # -------------------------------------------------
        # 4. 부모 나이 선택값 검증
        # -------------------------------------------------
        if father_age not in [None, ""]:
            try:
                father_age = int(father_age)
            except (ValueError, TypeError):
                return Response(
                    {"error": "father_age는 int 값이어야 합니다."},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if father_age <= 0:
                return Response(
                    {"error": "father_age는 1 이상이어야 합니다."},
                    status=status.HTTP_400_BAD_REQUEST
                )

        if mother_age not in [None, ""]:
            try:
                mother_age = int(mother_age)
            except (ValueError, TypeError):
                return Response(
                    {"error": "mother_age는 int 값이어야 합니다."},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if mother_age <= 0:
                return Response(
                    {"error": "mother_age는 1 이상이어야 합니다."},
                    status=status.HTTP_400_BAD_REQUEST
                )

        # -------------------------------------------------
        # 5. alpha 선택값 검증
        # -------------------------------------------------
        try:
            alpha = float(alpha)
        except (ValueError, TypeError):
            return Response(
                {"error": "alpha는 float 값이어야 합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        if alpha < 0.0 or alpha > 0.5:
            return Response(
                {"error": "alpha는 0.0 이상 0.5 이하만 가능합니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        # -------------------------------------------------
        # 6. AI 서버 요청 준비
        # -------------------------------------------------
        ai_url = getattr(
            settings,
            "AI_AGING_API_URL",
            f"{settings.AI_SERVER_URL}/api/aging",
        )

        timeout = getattr(settings, "AI_AGING_TIMEOUT", 3000)

        data = {
            "source_age": source_age,
            "target_age": target_age,
            "gender": gender,
            "ethnicity": ethnicity,
            "alpha": alpha,
        }

        # 부모 나이는 값이 있을 때만 전달
        if father_age not in [None, ""]:
            data["father_age"] = father_age

        if mother_age not in [None, ""]:
            data["mother_age"] = mother_age

        files = {
            "image": (
                image.name,
                image,
                getattr(image, "content_type", "application/octet-stream")
            )
        }

        # 부모 사진은 파일이 있을 때만 전달
        if father_image:
            files["father_image"] = (
                father_image.name,
                father_image,
                getattr(
                    father_image,
                    "content_type",
                    "application/octet-stream"
                )
            )

        if mother_image:
            files["mother_image"] = (
                mother_image.name,
                mother_image,
                getattr(
                    mother_image,
                    "content_type",
                    "application/octet-stream"
                )
            )

        print("========== [AI Aging API] ==========")
        print("프론트 요청 수신 완료")
        print("image:", image.name)
        print("source_age:", source_age)
        print("target_age:", target_age)
        print("gender:", gender)
        print("ethnicity:", ethnicity)

        print(
            "father_image:",
            father_image.name if father_image else None
        )
        print("father_age:", father_age)

        print(
            "mother_image:",
            mother_image.name if mother_image else None
        )
        print("mother_age:", mother_age)

        print("alpha:", alpha)
        print("AI 서버 요청 URL:", ai_url)
        print("===================================")

        # -------------------------------------------------
        # 7. AI 서버 호출
        # -------------------------------------------------
        ai_headers = {
            "ngrok-skip-browser-warning": "true"
        }
        try:
            ai_response = requests.post(
                ai_url,
                data=data,
                files=files,
                headers=ai_headers,
                timeout=timeout,
            )

        except requests.exceptions.Timeout:
            return Response(
                {"error": "AI 서버 응답 시간이 초과되었습니다."},
                status=status.HTTP_504_GATEWAY_TIMEOUT
            )

        except requests.exceptions.ConnectionError:
            return Response(
                {
                    "error": (
                        "AI 서버에 연결할 수 없습니다. "
                        "AI 서버가 켜져 있는지 확인해주세요."
                    )
                },
                status=status.HTTP_502_BAD_GATEWAY
            )

        except requests.exceptions.RequestException as e:
            return Response(
                {
                    "error": "AI 서버 요청 중 오류가 발생했습니다.",
                    "detail": str(e)
                },
                status=status.HTTP_502_BAD_GATEWAY
            )

        # -------------------------------------------------
        # 8. AI 서버 에러 응답 처리
        # -------------------------------------------------
        if ai_response.status_code >= 400:
            try:
                error_body = ai_response.json()
            except Exception:
                error_body = ai_response.text

            return Response(
                {
                    "error": "AI 서버에서 오류가 반환되었습니다.",
                    "ai_status_code": ai_response.status_code,
                    "ai_response": error_body,
                },
                status=status.HTTP_502_BAD_GATEWAY
            )

        # -------------------------------------------------
        # 9. AI 서버가 이미지 파일을 반환하는 경우
        # -------------------------------------------------
        content_type = ai_response.headers.get("Content-Type", "")

        if content_type.startswith("image/"):
            response = HttpResponse(
                ai_response.content,
                content_type=content_type
            )

            response["Content-Disposition"] = (
                'inline; filename="aged_image.png"'
            )

            # AI 서버 응답 헤더를 프론트로 그대로 전달
            forward_headers = [
                "X-Identity-Score",
                "X-Target-Age",
                "X-Calibrated-Target",
                "X-Age-Warning",
                "X-Blending",
                "X-Alpha",
                "X-Parent-Score",
                "X-PTI",
                "X-FFHQ-Scale",
            ]

            for header_name in forward_headers:
                header_value = ai_response.headers.get(
                    header_name
                )

                if header_value is not None:
                    response[header_name] = header_value
            return response

        # -------------------------------------------------
        # 10. AI 서버가 JSON을 반환하는 경우
        # -------------------------------------------------
        try:
            return Response(
                ai_response.json(),
                status=status.HTTP_200_OK
            )

        except Exception:
            return Response(
                {
                    "message": "AI 서버 응답을 그대로 반환합니다.",
                    "content_type": content_type,
                    "data": ai_response.text,
                },
                status=status.HTTP_200_OK
            )
class InteractionViewSet(viewsets.ModelViewSet):
    queryset = Interaction.objects.all()
    serializer_class = InteractionSerializer

class LogViewSet(viewsets.ModelViewSet):
    queryset = Log.objects.all()
    serializer_class = LogSerializer
    permission_classes = [IsAdmin]  # 🔥 관리자만 접근

    def list(self, request):
        qs = Log.objects.all().order_by("-timestamp")

        # -------------------------
        # 🔹 사용자 필터
        # -------------------------
        user_id = request.GET.get("user_id")
        if user_id:
            qs = qs.filter(user_id=user_id)

        # -------------------------
        # 🔹 타입 필터
        # -------------------------
        target_type = request.GET.get("target_type")
        if target_type:
            qs = qs.filter(target_type=target_type)

        # -------------------------
        # 🔹 action 검색
        # -------------------------
        keyword = request.GET.get("keyword")
        if keyword:
            qs = qs.filter(
                Q(action__icontains=keyword)
            )

        # -------------------------
        # 🔹 날짜 필터
        # -------------------------
        start_date = request.GET.get("start_date")
        end_date = request.GET.get("end_date")

        if start_date:
            qs = qs.filter(timestamp__date__gte=start_date)
        if end_date:
            qs = qs.filter(timestamp__date__lte=end_date)

        # -------------------------
        # 🔹 최신순
        # -------------------------
        qs = qs.order_by("-timestamp")

        serializer = LogSerializer(qs, many=True)
        return Response(serializer.data)

    @action(
        detail=False,
        methods=["get"],
        url_path="admin-timeline",
        permission_classes=[IsAdmin],
    )
    def admin_timeline(self, request):
        """
        GET /dasibom/log/admin-timeline/

        관리자 로그 타임라인용 API
        프론트 AdminLogPage의 _LogEntry 구조에 맞춘 응답 반환

        ※ 프론트 응답 형식/판정 로직 유지
        ※ DB 조회 방식만 N+1 -> 일괄 조회로 최적화
        """

        STATUS_LABEL = {
            "received": "접수 중",
            "reviewing": "확인 중",
            "completed": "등록 완료",
            "rejected": "거절",
            "missing": "실종",
            "found": "발견",
        }

        def get_status_label(value):
            if not value:
                return None

            value = str(value).strip()
            return STATUS_LABEL.get(value, value)

        def get_admin_name(log):
            if log.user and getattr(log.user, "name", None):
                return log.user.name

            if log.action and ("생성" in log.action or "접수" in log.action):
                return "시스템"

            return "관리자"

        def get_case_code(case):
            if not case:
                return None

            if case.type_code == Case.TypeCode.TIP:
                return f"TIP-{case.id:03d}"

            if case.type_code == Case.TypeCode.MISSING:
                return f"RPT-{case.id:03d}"

            return f"CASE-{case.id:03d}"

        def parse_status_change(action):
            """
            예:
            '제보/신고 상태 변경: received → reviewing'
            '실종 예방 등록 상태 변경: received → reviewing'
            """
            if not action or "→" not in action:
                return None, None

            try:
                status_part = action.split(":")[-1].strip()
                from_status, to_status = status_part.split("→")

                return (
                    from_status.strip(),
                    to_status.strip(),
                )

            except Exception:
                return None, None

        # =========================================================
        # 1. 기존 필터 로직 그대로
        # =========================================================
        qs = (
            Log.objects
            .select_related("user")
            .all()
            .order_by("-timestamp")
        )

        action_type = request.GET.get("actionType")
        target_type = request.GET.get("target_type")
        keyword = request.GET.get("keyword")
        start_date = request.GET.get("start_date")
        end_date = request.GET.get("end_date")

        if target_type:
            qs = qs.filter(
                target_type=target_type
            )

        if keyword:
            qs = qs.filter(
                Q(action__icontains=keyword)
            )

        if start_date:
            qs = qs.filter(
                timestamp__date__gte=start_date
            )

        if end_date:
            qs = qs.filter(
                timestamp__date__lte=end_date
            )

        # 여기서 로그를 한 번만 조회
        logs = list(qs)

        # =========================================================
        # 2. 로그에서 target_id 수집
        # =========================================================
        case_ids = {
            log.target_id
            for log in logs
            if log.target_type == "Case"
               and log.target_id
        }

        missing_person_ids = {
            log.target_id
            for log in logs
            if log.target_type == "MissingPerson"
               and log.target_id
        }

        prevention_ids = {
            log.target_id
            for log in logs
            if log.target_type == "PreventionRegistration"
               and log.target_id
        }

        emergency_ids = {
            log.target_id
            for log in logs
            if log.target_type == "EmergencyReport"
               and log.target_id
        }

        location_log_ids = {
            log.target_id
            for log in logs
            if log.target_type == "DeviceLocationLog"
               and log.target_id
        }

        montage_ids = {
            log.target_id
            for log in logs
            if log.target_type == "Montage"
               and log.target_id
        }

        # =========================================================
        # 3. 기존 조회와 동일한 객체를 일괄 조회
        # =========================================================

        case_map = {
            obj.id: obj
            for obj in (
                Case.objects
                .filter(id__in=case_ids)
                .select_related(
                    "missing_person",
                    "reporter",
                )
            )
        }

        missing_person_map = {
            obj.id: obj
            for obj in (
                MissingPerson.objects
                .filter(id__in=missing_person_ids)
            )
        }

        prevention_map = {
            obj.id: obj
            for obj in (
                PreventionRegistration.objects
                .filter(id__in=prevention_ids)
                .select_related(
                    "owner",
                    "reviewed_by",
                )
            )
        }

        emergency_map = {
            obj.id: obj
            for obj in (
                EmergencyReport.objects
                .filter(id__in=emergency_ids)
            )
        }

        location_log_map = {
            obj.id: obj
            for obj in (
                DeviceLocationLog.objects
                .filter(id__in=location_log_ids)
                .select_related(
                    "device",
                    "device__person",
                )
            )
        }

        montage_map = {
            obj.id: obj
            for obj in (
                Montage.objects
                .filter(id__in=montage_ids)
            )
        }

        # =========================================================
        # 4. 기존 Guardian.objects.filter(...).first()와
        #    동일하게 ward별 가장 작은 pk 관계 사용
        # =========================================================
        ward_ids = {
            location_log.device.person.id
            for location_log in location_log_map.values()
            if (
                    location_log.device
                    and location_log.device.person
            )
        }

        guardian_by_ward = {}

        if ward_ids:
            guardian_relations = (
                Guardian.objects
                .filter(ward_id__in=ward_ids)
                .select_related("guardian")
                .order_by("pk")
            )

            for relation in guardian_relations:
                if relation.ward_id not in guardian_by_ward:
                    guardian_by_ward[
                        relation.ward_id
                    ] = relation

        # =========================================================
        # 5. 기존 build_log_item 로직 그대로
        # =========================================================
        def build_log_item(log):
            action = log.action or ""

            action_type = "tipReceived"
            target_name = "대상자"
            case_id = None
            from_status = None
            to_status = None

            kiosk_id = None
            kiosk_number = None
            device_code = None
            guardian_name = None
            guardian_id = None
            ward_name = None
            ward_id = None

            # ------------------------------------
            # 1. Case 로그 처리
            # ------------------------------------
            if log.target_type == "Case":

                # 기존:
                # Case.objects.filter(id=log.target_id)
                # .select_related(...).first()

                case = case_map.get(
                    log.target_id
                )

                if case:
                    target_name = (
                            case.reported_missing_name
                            or (case.payload or {}).get("name")
                            or (case.payload or {}).get("missing_name")
                            or "대상자"
                    )

                    case_id = get_case_code(case)

                    # 제보 생성
                    if case.type_code == Case.TypeCode.TIP and (
                            "제보 생성" in action
                            or "시민 제보 생성" in action
                    ):
                        action_type = "tipReceived"

                    # 실종 신고 생성
                    elif case.type_code == Case.TypeCode.MISSING and (
                            "신고 생성" in action
                            or "실종자 신고 생성" in action
                    ):
                        action_type = "reportReceived"

                    # 상태 변경
                    elif "상태 변경" in action:
                        raw_from, raw_to = (
                            parse_status_change(action)
                        )

                        from_status = (
                            get_status_label(raw_from)
                        )

                        to_status = (
                            get_status_label(raw_to)
                        )

                        if raw_to == Case.Status.REJECTED:
                            action_type = "missingRejected"

                        elif (
                                case.type_code
                                == Case.TypeCode.MISSING
                                and raw_to
                                == Case.Status.COMPLETED
                        ):
                            action_type = "missingRegistered"

                        else:
                            action_type = "tipStatusChanged"

                    # 신고 승인으로 실종자 등록
                    elif (
                            "실종자 승인" in action
                            or "실종자 등록" in action
                    ):
                        action_type = "missingRegistered"

                    elif "수정" in action:
                        action_type = "caseUpdated"

                    elif "삭제" in action:
                        if case.type_code == Case.TypeCode.TIP:
                            action_type = "tipDeleted"
                        else:
                            action_type = "reportDeleted"

                    else:
                        action_type = "tipStatusChanged"

                else:
                    # 기존 fallback 그대로
                    if "제보" in action and "삭제" in action:
                        action_type = "tipDeleted"

                    elif "신고" in action and "삭제" in action:
                        action_type = "reportDeleted"

                    else:
                        action_type = "tipStatusChanged"

                    target_name = "삭제된 신고/제보"

                    case_id = (
                        f"CASE-{log.target_id:03d}"
                        if log.target_id
                        else None
                    )

            # ------------------------------------
            # 2. MissingPerson 로그 처리
            # ------------------------------------
            elif log.target_type == "MissingPerson":

                person = missing_person_map.get(
                    log.target_id
                )

                if person:
                    target_name = (
                            person.name
                            or "대상자"
                    )

                    case_id = (
                        f"MP-{person.id:03d}"
                    )

                else:
                    target_name = "삭제된 실종자"

                    case_id = (
                        f"MP-{log.target_id:03d}"
                        if log.target_id
                        else None
                    )

                if "상태 변경" in action:
                    raw_from, raw_to = (
                        parse_status_change(action)
                    )

                    from_status = (
                        get_status_label(raw_from)
                    )

                    to_status = (
                        get_status_label(raw_to)
                    )

                    if (
                            raw_to == MissingPerson.Status.FOUND
                            or "found" in action
                    ):
                        action_type = "missingFound"
                        to_status = "발견"

                    else:
                        action_type = "missingStatusChanged"

                elif "수정" in action:
                    action_type = "caseUpdated"

                elif "삭제" in action:
                    action_type = "missingDeleted"

                else:
                    action_type = "missingRegistered"

            # ------------------------------------
            # 3. PreventionRegistration 로그 처리
            # ------------------------------------
            elif log.target_type == "PreventionRegistration":

                registration = prevention_map.get(
                    log.target_id
                )

                if registration:
                    target_name = (
                            registration.name
                            or "예방등록 대상자"
                    )

                    case_id = (
                        f"PREV-{registration.id:03d}"
                    )

                else:
                    target_name = "삭제된 예방등록"

                    case_id = (
                        f"PREV-{log.target_id:03d}"
                        if log.target_id
                        else None
                    )

                # 기존 순서 그대로
                if "생성" in action:
                    action_type = "preventionRegistered"

                elif "수정" in action:
                    action_type = "preventionUpdated"

                elif "비활성화" in action:
                    action_type = "preventionDeactivated"

                elif "삭제" in action:
                    action_type = "preventionDeleted"

                elif "상태 변경" in action:
                    raw_from, raw_to = (
                        parse_status_change(action)
                    )

                    from_status = (
                        get_status_label(raw_from)
                    )

                    to_status = (
                        get_status_label(raw_to)
                    )

                    if (
                            raw_to
                            == PreventionRegistration.Status.REJECTED
                    ):
                        action_type = "preventionRejected"

                    elif (
                            raw_to
                            == PreventionRegistration.Status.COMPLETED
                    ):
                        action_type = "preventionCompleted"

                    else:
                        action_type = "preventionStatusChanged"

                else:
                    action_type = "preventionStatusChanged"

            # ------------------------------------
            # 4. EmergencyReport 로그 처리
            # ------------------------------------
            elif log.target_type == "EmergencyReport":

                emergency = emergency_map.get(
                    log.target_id
                )

                if emergency:
                    target_name = (
                            emergency.device_code
                            or "긴급신고 기기"
                    )

                    case_id = (
                        f"EMG-{emergency.id:03d}"
                    )

                else:
                    target_name = "긴급신고"

                    case_id = (
                        f"EMG-{log.target_id:03d}"
                        if log.target_id
                        else None
                    )

                action_type = "emergencyReceived"

            # ------------------------------------
            # 5. DeviceLocationLog 로그 처리
            # ------------------------------------
            elif log.target_type == "DeviceLocationLog":

                location_log = location_log_map.get(
                    log.target_id
                )

                if location_log:
                    device_code = (
                        location_log.device_code
                    )

                    target_name = (
                            device_code
                            or "위치공유 기기"
                    )

                    case_id = (
                        f"LOC-{location_log.id:03d}"
                    )

                    ward = (
                        location_log.device.person
                        if (
                                location_log.device
                                and location_log.device.person
                        )
                        else None
                    )

                    if ward:
                        ward_name = ward.name
                        ward_id = ward.id

                        # 기존 .first()와 동일한 관계
                        guardian_relation = (
                            guardian_by_ward.get(
                                ward.id
                            )
                        )

                        if (
                                guardian_relation
                                and guardian_relation.guardian
                        ):
                            guardian_name = (
                                guardian_relation.guardian.name
                            )

                            guardian_id = (
                                guardian_relation.guardian.id
                            )

                    # 기존 코드 그대로
                    if device_code:
                        try:
                            kiosk_id = int(
                                device_code.split("_")[-1]
                            )

                            kiosk_number = (
                                f"{kiosk_id}번"
                            )

                        except (
                                ValueError,
                                IndexError,
                        ):
                            kiosk_id = None
                            kiosk_number = None

                else:
                    target_name = "위치공유"

                    case_id = (
                        f"LOC-{log.target_id:03d}"
                        if log.target_id
                        else None
                    )

                action_type = "locationShared"

            # ------------------------------------
            # 6. Montage 로그 처리
            # ------------------------------------
            elif log.target_type == "Montage":

                montage = montage_map.get(
                    log.target_id
                )

                if montage:
                    target_name = "AI 몽타주"

                    case_id = (
                        f"MON-{montage.id:03d}"
                    )

                else:
                    target_name = "AI 몽타주"

                    case_id = (
                        f"MON-{log.target_id:03d}"
                        if log.target_id
                        else None
                    )

                if "생성" in action:
                    action_type = "montageCreated"

                elif (
                        "적용" in action
                        or "반영" in action
                ):
                    action_type = "montageApplied"

                else:
                    action_type = "montageUpdated"

            # ------------------------------------
            # 7. 기타 로그 처리
            # ------------------------------------
            else:
                action_type = "tipStatusChanged"

            # ------------------------------------
            # 응답 필드명/형식 기존 그대로
            # ------------------------------------
            return {
                "id": log.id,

                "timestamp": (
                    format_datetime_for_front(
                        log.timestamp
                    )
                ),

                "timestamp_iso": (
                    timezone.localtime(
                        log.timestamp
                    ).isoformat()
                    if log.timestamp
                    else None
                ),

                "display_timestamp": (
                    format_datetime_for_front(
                        log.timestamp
                    )
                ),

                "actionType": action_type,
                "targetName": target_name,
                "caseId": case_id,
                "fromStatus": from_status,
                "toStatus": to_status,

                "adminName": (
                    get_admin_name(log)
                ),

                "rawAction": action,
                "targetType": log.target_type,
                "targetId": log.target_id,
                "ward_name": ward_name,
                "ward_id": ward_id,

                "kiosk_id": kiosk_id,
                "kiosk_number": kiosk_number,
                "device_code": device_code,
                "guardian_name": guardian_name,
                "guardian_id": guardian_id,
            }

        # =========================================================
        # 6. 결과 생성
        # =========================================================
        result = [
            build_log_item(log)
            for log in logs
        ]

        # 기존과 동일:
        # actionType은 변환 후 필터
        if action_type:
            result = [
                item
                for item in result
                if item["actionType"] == action_type
            ]

        return Response(
            result,
            status=status.HTTP_200_OK,
        )


class FacilityListAPIView(APIView):
    """
    안전지도 시설 목록 API
    - lat, lng 기준
    - 서버 검색 반경 500m 고정
    """

    def get(self, request):
        lat = request.GET.get("lat")
        lng = request.GET.get("lng")

        client_type = request.headers.get(
            "X-Client-Type",
            "unknown"
        )
        ip = request.META.get("REMOTE_ADDR")

        print(
            f"[시설API] "
            f"client={client_type} | "
            f"ip={ip} | "
            f"lat={lat}, lng={lng}"
        )

        # 1. 필수 파라미터
        if lat is None or lng is None:
            return Response(
                {
                    "code": 400,
                    "message": "lat, lng 파라미터가 필요합니다."
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        # 2. 숫자 변환
        try:
            lat = float(lat)
            lng = float(lng)

        except (ValueError, TypeError):
            return Response(
                {
                    "code": 400,
                    "message": "lat, lng는 숫자(float)여야 합니다."
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        # 3. NaN / Infinity 검사
        if (
            not math.isfinite(lat)
            or not math.isfinite(lng)
        ):
            return Response(
                {
                    "code": 400,
                    "message": "lat, lng 값이 올바르지 않습니다."
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        # ★ 무조건 500m
        radius = 0.5

        print(
            f"[시설API] ★ 서버 고정 반경 "
            f"lat={lat}, lng={lng}, "
            f"radius={radius}km"
        )

        try:
            facilities = get_nearby_facilities(
                lat=lat,
                lng=lng,
                radius_km=radius,
            )

        except Exception as e:
            import traceback
            traceback.print_exc()

            return Response(
                {
                    "code": 500,
                    "message": "시설 데이터 조회 중 오류 발생",
                    "error": str(e),
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        return Response(
            {
                "code": 200,
                "message": "성공",
                "data": facilities,
            },
            status=status.HTTP_200_OK,
        )
from django.db.models import Count
import time
from datetime import datetime

from rest_framework.views import APIView
from rest_framework.response import Response


class PingAPIView(APIView):
    authentication_classes = []
    permission_classes = []

    def get(self, request):
        print(
            "[PING VIEW 진입]",
            datetime.now().strftime("%H:%M:%S.%f"),
            flush=True,
        )

        return Response({
            "code": 200,
            "message": "pong",
            "timestamp": time.time(),
        })
class ProtectedPersonViewSet(viewsets.ReadOnlyModelViewSet):
    """
    보호중이에요 ViewSet

    [목록]
    GET /dasibom/protectedperson/
    GET /dasibom/protectedperson/cards/   ← 카드용

    [상세]
    GET /dasibom/protectedperson/<id>/

    [통계]
    GET /dasibom/protectedperson/stats/

    Query:
        - search
        - category
        - gender
        - ordering
    """

    queryset = ProtectedPerson.objects.all()
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]

    filterset_fields = {
        "gender": ["exact"],
        "status": ["exact"],
        "nationality": ["exact"],
        "current_age": ["gte", "lte"],
        "occurred_at": ["gte", "lte"],
    }

    search_fields = ["name", "occurred_location", "clothing", "msspsn_idntfccd"]
    ordering_fields = ["occurred_at", "current_age", "crawled_at", "updated_at", "name"]
    ordering = ["-occurred_at"]

    # -------------------------------------------------- #
    # Serializer 선택
    # -------------------------------------------------- #
    def get_serializer_class(self):
        if self.action == "retrieve":
            return ProtectedPersonDetailSerializer
        if self.action == "cards":
            return ProtectedPersonCardSerializer
        return ProtectedPersonListSerializer

    # -------------------------------------------------- #
    # 🔥 핵심 1: 기타 → "" 변환
    # -------------------------------------------------- #
    def get_queryset(self):
        qs = super().get_queryset()

        # =====================================================
        # 1. 분류 필터
        # =====================================================
        category = self.request.query_params.get(
            "category"
        )

        qs = apply_category_filter(
            qs,
            category,
        )

        # =====================================================
        # 2. 지역 필터
        # =====================================================
        sido = self.request.query_params.get(
            "sido"
        )

        sigungu = self.request.query_params.get(
            "sigungu"
        )

        region = self.request.query_params.get(
            "region"
        )

        # ---------------------------------------------
        # 시/도
        # ---------------------------------------------
        if sido:
            region_query = build_region_query(
                sido
            )

            if region_query is not None:
                qs = qs.filter(
                    region_query
                )

        # ---------------------------------------------
        # region
        #
        # 기존 프론트/키오스크 호환 유지
        # ---------------------------------------------
        if region:
            region_query = build_region_query(
                region
            )

            if region_query is not None:
                qs = qs.filter(
                    region_query
                )

        # ---------------------------------------------
        # 시/군/구
        #
        # 이미 sido와 조합되는 경우
        # 해당 시/도 안에서 시군구 검색
        # ---------------------------------------------
        if sigungu:
            qs = qs.filter(
                occurred_location__icontains=sigungu
            )

        return qs
    # -------------------------------------------------- #
    # 🔥 핵심 2: category만 제거하고 나머지 필터 유지
    # -------------------------------------------------- #
    @action(detail=False, methods=["get"])
    def cards(self, request):
        qs = self.get_queryset()

        # search / gender / ordering 등
        # 기존 DjangoFilterBackend 기능 유지
        qs = self.filter_queryset(qs)

        page = self.paginate_queryset(qs)

        if page is not None:
            serializer = ProtectedPersonCardSerializer(
                page,
                many=True,
                context={
                    "request": request
                }
            )

            return self.get_paginated_response(
                serializer.data
            )

        serializer = ProtectedPersonCardSerializer(
            qs,
            many=True,
            context={
                "request": request
            }
        )

        return Response(
            serializer.data
        )
    @action(
        detail=False,
        methods=["get"],
        url_path=r"(?P<msspsn_idntfccd>[^/.]+)/detail",
    )
    def detail_view(self, request, msspsn_idntfccd=None):
        person = get_object_or_404(
            ProtectedPerson,
            msspsn_idntfccd=msspsn_idntfccd,
        )

        serializer = ProtectedPersonDetailSerializer(
            person,
            context={"request": request},
        )

        return Response(
            serializer.data,
            status=status.HTTP_200_OK,
        )
    # -------------------------------------------------- #
    # 통계 API
    # -------------------------------------------------- #
    @action(detail=False, methods=["get"])
    def stats(self, request):
        qs = ProtectedPerson.objects.all()

        # category 통계 (빈값 → 기타)
        by_category_raw = (
            qs.values("category")
            .annotate(count=Count("id"))
            .order_by("-count")
        )

        by_category = []
        etc_count = 0

        for item in by_category_raw:
            if not item["category"]:  # "" or None
                etc_count += item["count"]
            else:
                by_category.append(item)

        if etc_count > 0:
            by_category.append({"category": "기타", "count": etc_count})

        by_category.sort(key=lambda x: x["count"], reverse=True)

        return Response({
            "total": qs.count(),
            "by_gender": list(
                qs.values("gender")
                .annotate(count=Count("id"))
                .order_by("gender")
            ),
            "by_category": by_category,
            "by_status": list(
                qs.values("status")
                .annotate(count=Count("id"))
                .order_by("-count")
            ),
            "last_crawled_at": qs.order_by("-crawled_at")
            .values_list("crawled_at", flat=True)
            .first(),
        })
class MissingPersonViewSet(viewsets.ReadOnlyModelViewSet):
    """
    '찾고 있어요' 실종자 ViewSet  (읽기 전용, 크롤러로만 데이터 적재)

    [목록]
    GET /dasibom/missingperson/          → MissingPersonListSerializer
    GET /dasibom/missingperson/cards/    → MissingPersonCardSerializer (프론트 카드용)

    [상세]
    GET /dasibom/missingperson/<id>/     → MissingPersonSerializer

    [통계]
    GET /dasibom/missingperson/stats/

    Query Parameters (cards & list 공통):
        - search    : 이름, 발생장소, 착의의상, 식별코드 통합검색
        - category  : 아동 | 장애 | 치매환자 | 가출인
        - gender    : 남자 | 여자
        - ordering  : occurred_at | -occurred_at | current_age | crawled_at
    """

    queryset = MissingPerson.objects.all()

    filter_backends = [
        DjangoFilterBackend,
        filters.SearchFilter,
        filters.OrderingFilter,
    ]
    filterset_fields = {
        "gender": ["exact"],
        "status": ["exact"],
        "nationality": ["exact"],
        "current_age": ["gte", "lte"],
        "occurred_at": ["gte", "lte"],
    }
    search_fields = ["name", "occurred_location", "clothing", "msspsn_idntfccd"]
    ordering_fields = ["occurred_at", "current_age", "crawled_at", "updated_at", "name"]
    ordering = ["-occurred_at"]

    def get_queryset(self):
        qs = super().get_queryset()

        # =====================================================
        # 0. 발견된 실종자는 기본 목록에서 제외
        # =====================================================
        qs = qs.exclude(
            status=MissingPerson.Status.FOUND
        )

        # =====================================================
        # 1. 분류 필터
        # =====================================================
        category = self.request.query_params.get(
            "category"
        )

        qs = apply_category_filter(
            qs,
            category,
        )

        # =====================================================
        # 2. 지역 필터
        # =====================================================
        sido = self.request.query_params.get(
            "sido"
        )

        sigungu = self.request.query_params.get(
            "sigungu"
        )

        region = self.request.query_params.get(
            "region"
        )

        # ---------------------------------------------
        # 시/도
        # ---------------------------------------------
        if sido:
            region_query = build_region_query(
                sido
            )

            if region_query is not None:
                qs = qs.filter(
                    region_query
                )

        # ---------------------------------------------
        # region
        #
        # 기존 Flutter / 키오스크 파라미터 호환
        # ---------------------------------------------
        if region:
            region_query = build_region_query(
                region
            )

            if region_query is not None:
                qs = qs.filter(
                    region_query
                )

        # ---------------------------------------------
        # 시/군/구
        # ---------------------------------------------
        if sigungu:
            qs = qs.filter(
                occurred_location__icontains=sigungu
            )

        return qs
    def get_serializer_class(self):
        if self.action == "retrieve":
            return MissingPersonSerializer
        if self.action == "cards":
            return MissingPersonCardSerializer
        return MissingPersonListSerializer

    # ── 카드 목록 ─────────────────────────────────────────────────────────────

    @action(detail=False, methods=["get"])
    def cards(self, request):
        """
        GET /dasibom/missingperson/cards/

        프론트 카드 UI용 목록
        Query Parameters:
            - search    : 이름 검색
            - category  : 전체 | 장애 | 치매환자 | 아동 | 가출인
            - gender    : 남자 | 여자
            - ordering  : occurred_at | -occurred_at (기본: -occurred_at)
        """
        qs = self.filter_queryset(self.get_queryset())

        page = self.paginate_queryset(qs)
        if page is not None:
            serializer = MissingPersonCardSerializer(
                page, many=True, context={"request": request}
            )
            return self.get_paginated_response(serializer.data)

        serializer = MissingPersonCardSerializer(
            qs, many=True, context={"request": request}
        )
        return Response(serializer.data)

    # ── 최근 실종자 (30일 이내) ────────────────────────────────────────────────

    @action(detail=False, methods=["get"], url_path="recent")
    def recent_missing(self, request):
        """
        GET /dasibom/missingperson/recent/
        발생일 기준 최근 30일 이내 실종자 랜덤 5건
        """
        from django.utils.timezone import now
        from datetime import timedelta

        threshold = now().date() - timedelta(days=30)
        qs = (
            MissingPerson.objects
            .filter(
                occurred_at__isnull=False,
                occurred_at__gte=threshold
            )
            .exclude(status=MissingPerson.Status.FOUND)  # 🔥 추가
            .order_by("?")[:5]
        )
        return Response(
            MissingPersonCardSerializer(qs, many=True, context={"request": request}).data
        )

    # ── 장기 실종자 (30일 초과) ────────────────────────────────────────────────

    @action(detail=False, methods=["get"], url_path="long-term")
    def long_term_missing(self, request):
        """
        GET /dasibom/missingperson/long-term/
        발생일 기준 30일 초과 실종자 랜덤 5건
        """
        from django.utils.timezone import now
        from datetime import timedelta

        threshold = now().date() - timedelta(days=30)
        qs = (
            MissingPerson.objects
            .filter(occurred_at__lt=threshold)
            .exclude(status=MissingPerson.Status.FOUND)  # ✅ 추가
            .order_by("?")[:5]
        )
        return Response(
            MissingPersonCardSerializer(qs, many=True, context={"request": request}).data
        )

    # ── 상세 조회 (msspsn_idntfccd 기준) ─────────────────────────────────────


    @action(
        detail=False,
        methods=["get"],
        url_path=r"(?P<msspsn_idntfccd>[^/.]+)/detail",
        permission_classes=[AllowAny],
    )
    def detail_view(self, request, msspsn_idntfccd=None):
        """
        GET /dasibom/missingperson/{msspsn_idntfccd}/detail/

        공개 상세 조회 API.
        로그인 토큰이 함께 들어오면 요청자가
        원본 실종신고 작성자인지 확인하여 수정 권한을 반환한다.

        추가:
        - 원본 실종신고 Case에 저장된 부모사진 반환
        - parent1_face / parent2_face
        """

        # =========================================================
        # 1. MissingPerson 조회
        # =========================================================
        person = get_object_or_404(
            MissingPerson,
            msspsn_idntfccd=msspsn_idntfccd,
            status=MissingPerson.Status.MISSING,
        )

        # =========================================================
        # 2. 로그인 / 권한 정보
        # =========================================================
        is_authenticated = bool(
            request.user
            and request.user.is_authenticated
        )

        user_person = (
            getattr(request.user, "person", None)
            if is_authenticated
            else None
        )

        is_admin = (
                is_authenticated
                and getattr(request.user, "role", None) == "admin"
        )

        # =========================================================
        # 3. 관리자 승인으로 이 MissingPerson을 생성한
        #    원본 실종 신고 Case 조회
        # =========================================================
        origin_case = (
            Case.objects
            .filter(
                type_code=Case.TypeCode.MISSING,
                status=Case.Status.COMPLETED,
                missing_person=person,
            )
            .select_related("reporter")
            .prefetch_related("photos")
            .order_by("-created_at")
            .first()
        )

        # =========================================================
        # 4. 부모사진 조회
        #
        # 원본 Case의 TipPhoto 중
        # parent1_face / parent2_face 타입을 찾아 URL 반환
        # =========================================================
        parent_photos = {
            "parent1_face": None,
            "parent2_face": None,
        }

        if origin_case:
            parent1_photo = (
                origin_case.photos
                .filter(
                    photo_type=TipPhoto.PhotoType.PARENT1_FACE
                )
                .order_by("-uploaded_at")
                .first()
            )

            parent2_photo = (
                origin_case.photos
                .filter(
                    photo_type=TipPhoto.PhotoType.PARENT2_FACE
                )
                .order_by("-uploaded_at")
                .first()
            )

            if (
                    parent1_photo
                    and parent1_photo.image
            ):
                parent_photos["parent1_face"] = media_url(
                    parent1_photo.image.name,
                    request,
                )

            if (
                    parent2_photo
                    and parent2_photo.image
            ):
                parent_photos["parent2_face"] = media_url(
                    parent2_photo.image.name,
                    request,
                )

        # =========================================================
        # 5. 신고 작성자 여부 확인
        # =========================================================
        is_owner = bool(
            user_person
            and origin_case
            and origin_case.reporter_id == user_person.id
        )

        # =========================================================
        # 6. 수정 권한
        # =========================================================
        can_edit = (
                person.status == MissingPerson.Status.MISSING
                and (
                        is_admin
                        or is_owner
                )
        )

        # =========================================================
        # 7. MissingPerson 기본 serializer
        # =========================================================
        serializer = MissingPersonSerializer(
            person,
            context={"request": request},
        )

        data = dict(serializer.data)

        # =========================================================
        # 8. 추가 응답 필드
        # =========================================================

        # PATCH 수정 API에서 사용하는 MissingPerson DB PK
        data["missing_person_id"] = person.id

        # 원본 신고 Case ID
        data["origin_case_id"] = (
            origin_case.id
            if origin_case
            else None
        )

        # 부모사진
        data["parent_photos"] = parent_photos

        # 권한
        data["permissions"] = {
            "is_owner": is_owner,
            "is_admin": is_admin,
            "can_edit": can_edit,
        }

        # =========================================================
        # 9. 응답
        # =========================================================
        return Response(
            data,
            status=status.HTTP_200_OK,
        )
    # ── 통계 ──────────────────────────────────────────────────────────────────

    @action(detail=False, methods=["get"])
    def stats(self, request):
        """
        GET /dasibom/missingperson/stats/
        """
        qs = MissingPerson.objects.exclude(
            status=MissingPerson.Status.FOUND
        )
        # 빈 category → '기타' 치환
        by_category_raw = (
            qs.values("category").annotate(count=Count("id")).order_by("-count")
        )
        by_category = []
        etc_count = 0
        for item in by_category_raw:
            if not item["category"]:
                etc_count += item["count"]
            else:
                by_category.append(item)
        if etc_count > 0:
            by_category.append({"category": "기타", "count": etc_count})
        by_category.sort(key=lambda x: x["count"], reverse=True)

        return Response({
            "total": qs.count(),
            "by_gender": list(
                qs.values("gender").annotate(count=Count("id")).order_by("gender")
            ),
            "by_category": by_category,
            "by_status": list(
                qs.values("status").annotate(count=Count("id")).order_by("-count")
            ),
            "last_crawled_at": (
                qs.order_by("-crawled_at")
                .values_list("crawled_at", flat=True)
                .first()
            ),
        })

    @action(
        detail=True,
        methods=["patch"],
        url_path="edit",
        permission_classes=[IsAuthenticated]
    )
    def edit_missing(self, request, pk=None):
        from datetime import datetime
        from django.db import transaction
        from django.core.files.storage import default_storage
        import json
        import uuid
        import logging

        logger = logging.getLogger(__name__)

        print("\n========== edit_missing ==========")
        print("PATCH 수정 요청")
        print("pk:", pk)
        print("request.path:", request.path)
        print("request.data:", request.data)
        print("==================================\n")

        # =========================================================
        # 0. 수정 대상 조회
        # =========================================================
        person = get_object_or_404(
            MissingPerson,
            pk=pk
        )

        # 발견 완료된 실종자는 수정 불가
        if person.status == MissingPerson.Status.FOUND:
            return Response(
                {
                    "error": "이미 발견된 실종자는 수정할 수 없습니다."
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        data = request.data

        # =========================================================
        # 1. 권한 확인
        #
        # 관리자:
        #   수정 가능
        #
        # 일반 회원:
        #   해당 MissingPerson을 생성한
        #   완료된 실종 신고 작성자만 수정 가능
        # =========================================================
        is_admin = (
                getattr(
                    request.user,
                    "role",
                    None
                )
                == UserAuth.Role.ADMIN
        )

        user_person = getattr(
            request.user,
            "person",
            None
        )

        if not is_admin:

            is_owner = bool(
                user_person
                and Case.objects.filter(
                    type_code=Case.TypeCode.MISSING,
                    status=Case.Status.COMPLETED,
                    missing_person=person,
                    reporter=user_person,
                ).exists()
            )

            if not is_owner:
                return Response(
                    {
                        "error": "해당 실종자를 신고한 회원만 수정할 수 있습니다."
                    },
                    status=status.HTTP_403_FORBIDDEN
                )

        # =========================================================
        # 2. 공통 헬퍼
        # =========================================================

        def get_list_value(key):
            """
            JSON / multipart / JSON 문자열 모두 처리

            예:
            ["키 170", "체격 보통"]

            또는
            '["키 170", "체격 보통"]'

            또는
            키 170
            체격 보통
            """

            if key not in data:
                return []

            # multipart QueryDict
            if hasattr(data, "getlist"):

                values = data.getlist(key)

                if values:

                    # JSON 배열 문자열 하나
                    if (
                            len(values) == 1
                            and isinstance(values[0], str)
                            and values[0].strip().startswith("[")
                    ):
                        try:
                            parsed = json.loads(
                                values[0]
                            )

                            if isinstance(
                                    parsed,
                                    list
                            ):
                                return parsed

                        except Exception:
                            pass

                    if len(values) > 1:
                        return values

            value = data.get(key)

            # JSON 배열
            if isinstance(
                    value,
                    list
            ):
                return value

            if isinstance(
                    value,
                    str
            ):

                value = value.strip()

                if not value:
                    return []

                # JSON 문자열 배열
                if value.startswith("["):
                    try:

                        parsed = json.loads(
                            value
                        )

                        if isinstance(
                                parsed,
                                list
                        ):
                            return parsed

                    except Exception:
                        pass

                # 여러 줄 TextField
                return [
                    item.strip()
                    for item in value.splitlines()
                    if item.strip()
                ]

            return []

        def english_text_list(key):
            """
            Flutter에서

            physical
            health
            behavior
            clothing
            description
            etc

            같은 문자열로 보낸 값을
            List 형태로 변환
            """

            if key not in data:
                return []

            raw = data.get(key)

            if raw is None:
                return []

            if isinstance(
                    raw,
                    list
            ):
                return [
                    str(item).strip()
                    for item in raw
                    if str(item).strip()
                ]

            text = str(
                raw
            ).strip()

            if not text:
                return []

            # JSON 배열 문자열
            if text.startswith("["):
                try:

                    parsed = json.loads(
                        text
                    )

                    if isinstance(
                            parsed,
                            list
                    ):
                        return [
                            str(item).strip()
                            for item in parsed
                            if str(item).strip()
                        ]

                except Exception:
                    pass

            # 줄바꿈 + 쉼표 기준
            result = []

            for line in text.replace("，", ",").splitlines():
                for item in line.split(","):
                    item = item.strip()

                    if item and item not in result:
                        result.append(item)

            return result
        def normalize_lines(value):
            """
            문자열 / 리스트를
            줄 단위로 분리 후 중복 제거.

            순서는 유지한다.
            """

            if value is None:
                return []

            if isinstance(
                    value,
                    (list, tuple)
            ):
                raw_items = value

            else:
                raw_items = [value]

            result = []

            for raw in raw_items:

                if raw is None:
                    continue

                for line in str(
                        raw
                ).splitlines():

                    line = line.strip()

                    if (
                            line
                            and line not in result
                    ):
                        result.append(
                            line
                        )

            return result

        # =========================================================
        # 3. 기본값 검증
        # =========================================================

        VALID_CATEGORIES = [
            "아동",
            "장애",
            "치매환자",
            "가출인",
        ]

        # ---------------------------------------------------------
        # category
        # ---------------------------------------------------------
        if "category" in data:

            category_value = str(
                data.get("category")
                or ""
            ).strip()

            if (
                    category_value
                    and category_value
                    not in VALID_CATEGORIES
            ):
                return Response(
                    {
                        "error": "잘못된 category 값입니다."
                    },
                    status=status.HTTP_400_BAD_REQUEST
                )


        # =========================================================
        # 4. 일반 필드 적용
        #
        # clothing은 아래에서 별도 처리
        # =========================================================

        allowed_fields = [
            "name",
            "occurred_location",
            "height",
            "weight",
            "body_type",
            "face_type",
            "hair_color",
            "hair_style",
            "nationality",
            "category",
        ]

        for field in allowed_fields:

            if field not in data:
                continue

            value = data.get(field)

            if value is not None:
                value = str(
                    value
                ).strip()

            setattr(
                person,
                field,
                value
            )

        # =========================================================
        # 5. 성별
        # =========================================================

        if "gender" in data:

            gender_raw = str(
                data.get("gender")
                or ""
            ).strip()

            gender_map = {
                "male": "남자",
                "female": "여자",

                "남성": "남자",
                "여성": "여자",

                "남자": "남자",
                "여자": "여자",
            }

            converted_gender = gender_map.get(
                gender_raw.lower(),
                gender_raw
            )

            if converted_gender not in [
                "",
                "남자",
                "여자",
            ]:
                return Response(
                    {
                        "error": "잘못된 gender 값입니다."
                    },
                    status=status.HTTP_400_BAD_REQUEST
                )

            person.gender = converted_gender

        # =========================================================
        # 6. 실종 당시 나이
        # =========================================================

        if "age_at_missing" in data:

            raw_age = data.get(
                "age_at_missing"
            )

            if raw_age in [
                None,
                "",
            ]:
                person.age_at_missing = None

            else:

                try:

                    person.age_at_missing = int(
                        raw_age
                    )

                except (
                        TypeError,
                        ValueError,
                ):

                    return Response(
                        {
                            "error": "실종 당시 나이는 숫자여야 합니다."
                        },
                        status=status.HTTP_400_BAD_REQUEST
                    )

        # =========================================================
        # 7. 실종 발생 일시
        #
        # MissingPerson.occurred_at = DateField
        # =========================================================

        if "occurred_at" in data:

            raw_date = data.get(
                "occurred_at"
            )

            if not raw_date:

                person.occurred_at = None

            else:

                try:

                    value = str(
                        raw_date
                    ).strip()

                    value = value.replace(
                        "Z",
                        "+00:00"
                    )

                    parsed = datetime.fromisoformat(
                        value
                    )

                    person.occurred_at = (
                        parsed.date()
                    )

                except Exception:

                    try:

                        person.occurred_at = (
                            datetime.strptime(
                                str(raw_date)[:10],
                                "%Y-%m-%d"
                            ).date()
                        )

                    except Exception:

                        return Response(
                            {
                                "error": "날짜 형식 오류"
                            },
                            status=status.HTTP_400_BAD_REQUEST
                        )

        # =========================================================
        # 8. 신체 특징
        #
        # 프론트:
        # physical =
        #
        # 키 180
        # 몸무게 82
        # 체격 보통
        # 얼굴형 사각형
        # =========================================================

        physical_list = get_list_value(
            "신체 특징"
        )

        if not physical_list:
            physical_list = english_text_list(
                "physical"
            )

        physical_list = normalize_lines(
            physical_list
        )

        for item in physical_list:

            item = str(item).strip()

            if not item:
                continue

            if item.startswith("키"):

                value = (
                    item
                    .replace("키", "", 1)
                    .strip()
                )

                person.height = value

            elif item.startswith("몸무게"):

                value = (
                    item
                    .replace("몸무게", "", 1)
                    .strip()
                )

                person.weight = value

            elif item.startswith("체격"):

                person.body_type = (
                    item
                    .replace("체격", "", 1)
                    .strip()
                )

            elif item.startswith("얼굴형"):

                person.face_type = (
                    item
                    .replace("얼굴형", "", 1)
                    .strip()
                )

            elif item.startswith("두발색상"):

                person.hair_color = (
                    item
                    .replace("두발색상", "", 1)
                    .strip()
                )

            elif item.startswith("두발형태"):

                person.hair_style = (
                    item
                    .replace("두발형태", "", 1)
                    .strip()
                )        # =========================================================
        # 9. 착의·외형 정보
        #
        # ★ 중요
        #
        # 이 블록은 physical for문 밖에 있어야 함.
        #
        # Flutter:
        # clothing =
        #
        # 두발색상 흑색
        # 두발형태 짧은머리(생머리)
        # 캐주얼차림
        #
        # ↓
        #
        # hair_color = 흑색
        # hair_style = 짧은머리(생머리)
        # clothing = 캐주얼차림
        # =========================================================

        has_clothing_input = (
                "착의·외형 정보" in data
                or "착의 사항" in data
                or "clothing" in data
        )

        if has_clothing_input:

            clothing_lines = []

            clothing_lines += get_list_value(
                "착의·외형 정보"
            )

            clothing_lines += get_list_value(
                "착의 사항"
            )

            clothing_lines += english_text_list(
                "clothing"
            )

            clothing_lines = normalize_lines(
                clothing_lines
            )

            other_clothing_items = []

            for line in clothing_lines:

                line = str(
                    line
                ).strip()

                if not line:
                    continue

                if line.startswith(
                        "두발색상"
                ):

                    person.hair_color = (
                        line
                        .replace(
                            "두발색상",
                            "",
                            1
                        )
                        .strip()
                    )

                elif line.startswith(
                        "두발형태"
                ):

                    person.hair_style = (
                        line
                        .replace(
                            "두발형태",
                            "",
                            1
                        )
                        .strip()
                    )

                else:

                    if (
                            line not in
                            other_clothing_items
                    ):
                        other_clothing_items.append(
                            line
                        )

            # 두발 정보는 clothing에 저장하지 않음
            #
            # 두발 정보밖에 없다면 ""
            # 기존에 잘못 저장된 두발 중복값도 제거됨
            person.clothing = "\n".join(
                other_clothing_items
            ).strip()

        # =========================================================
        # 10. 건강·장애 정보
        #
        # Flutter:
        # health
        # =========================================================

        health_list = get_list_value(
            "건강·장애 정보"
        )

        if not health_list:
            health_list = english_text_list(
                "health"
            )

        health_list = normalize_lines(
            health_list
        )

        if health_list:

            for item in health_list:

                candidate = str(
                    item
                ).strip()

                if candidate in VALID_CATEGORIES:
                    person.category = candidate
                    break

        # =========================================================
        # 11. 기타 참고 사항 + 성격·행동 특성
        #
        # 현재 EditMissingPage:
        #
        # behavior    → 성격·행동 특성
        # description → 기타 참고 사항
        #
        # 추가 호환:
        # etc
        # "기타 참고 사항"
        # "성격·행동 특성"
        # =========================================================

        has_etc_input = (
                "기타 참고 사항" in data
                or "etc" in data
                or "description" in data
                or "behavior" in data
                or "성격·행동 특성" in data
        )

        if has_etc_input:

            etc_lines = []

            # -----------------------------------------------------
            # 성격·행동 특성
            # -----------------------------------------------------

            behavior_items = []

            behavior_items += get_list_value(
                "성격·행동 특성"
            )

            behavior_items += english_text_list(
                "behavior"
            )

            behavior_items = normalize_lines(
                behavior_items
            )

            for item in behavior_items:

                item = str(
                    item
                ).strip()

                if not item:
                    continue

                value = (
                    f"[성격·행동 특성] "
                    f"{item}"
                )

                if value not in etc_lines:
                    etc_lines.append(
                        value
                    )

            # -----------------------------------------------------
            # 기타 참고 사항
            #
            # ★ 현재 Flutter가 description으로 보냄
            # -----------------------------------------------------

            extra_items = []

            extra_items += get_list_value(
                "기타 참고 사항"
            )

            extra_items += english_text_list(
                "etc"
            )

            extra_items += english_text_list(
                "description"
            )

            extra_items = normalize_lines(
                extra_items
            )

            for item in extra_items:

                item = str(
                    item
                ).strip()

                if not item:
                    continue

                value = (
                    f"[기타 참고 사항] "
                    f"{item}"
                )

                if value not in etc_lines:
                    etc_lines.append(
                        value
                    )

            # -----------------------------------------------------
            # 새 내용으로 완전히 교체
            #
            # 빈칸으로 수정한 경우에도
            # 기존 값이 제거됨
            # -----------------------------------------------------

            person.etc_spfeatr = "\n".join(
                etc_lines
            ).strip()

            # -----------------------------------------------------
            # ★ 기존 AI 분류값 제거
            #
            # 수정 전 내용 기준 AI 결과가 남아 있으면
            # GET 상세에서 예전 내용이 다시 표시될 수 있음
            # -----------------------------------------------------

            if hasattr(
                    person,
                    "etc_ai_segments"
            ):
                person.etc_ai_segments = []

            if hasattr(
                    person,
                    "etc_ai_category"
            ):
                person.etc_ai_category = None

            if hasattr(
                    person,
                    "etc_ai_confidence"
            ):
                person.etc_ai_confidence = None

        # =========================================================
        # 12. 기존 이미지 삭제
        # =========================================================

        if "delete_photos" in data:

            delete_list = get_list_value(
                "delete_photos"
            )

            # "a.jpg,b.jpg" 대응
            if (
                    len(delete_list) == 1
                    and isinstance(
                delete_list[0],
                str
            )
                    and ","
                    in delete_list[0]
            ):
                delete_list = [
                    item.strip()
                    for item
                    in delete_list[0].split(",")
                    if item.strip()
                ]

            delete_list = [
                str(item).strip()
                for item in delete_list
                if str(item).strip()
            ]

            current_images = list(
                person.image_urls
                or []
            )

            # 실제 Storage 파일 삭제
            for image_path in current_images:

                if (
                        str(image_path)
                        in delete_list
                ):

                    try:

                        default_storage.delete(
                            str(image_path)
                        )

                    except Exception as e:

                        logger.warning(
                            "[edit_missing] "
                            "이미지 삭제 실패 "
                            "(%s): %s",
                            image_path,
                            e,
                        )

            # DB 이미지 목록
            person.image_urls = [
                url
                for url in current_images
                if str(url)
                   not in delete_list
            ]

            # AI 이미지 목록
            person.ai_image_urls = [
                url
                for url in (
                        person.ai_image_urls
                        or []
                )
                if str(url)
                   not in delete_list
            ]

        # =========================================================
        # 13. 새 이미지 추가
        # =========================================================

        new_photos = request.FILES.getlist(
            "new_photos"
        )

        if new_photos:

            image_urls = list(
                person.image_urls
                or []
            )

            for file in new_photos:

                ext = ""

                if "." in file.name:
                    ext = (
                            "."
                            + file.name
                            .split(".")[-1]
                            .lower()
                    )

                unique_name = (
                    f"{uuid.uuid4().hex}"
                    f"{ext}"
                )

                path = (
                    f"missing_persons/"
                    f"{person.msspsn_idntfccd}/"
                    f"{unique_name}"
                )

                saved_path = (
                    default_storage.save(
                        path,
                        file
                    )
                )

                if (
                        saved_path
                        not in image_urls
                ):
                    image_urls.append(
                        saved_path
                    )

            person.image_urls = (
                image_urls
            )

        # =========================================================
        # 14. AI 재분류
        #
        # 수정 API에서는 실행하지 않음.
        #
        # 기존 AI 결과는 11번에서 초기화함.
        # 수정 요청마다 AI 호출하면 응답 지연 가능성이 크고,
        # 과거 분류 결과와 충돌할 수 있으므로 사용 X
        # =========================================================

        # =========================================================
        # 15. DB 저장 + 로그
        #
        # ★★★★★ 중요 ★★★★★
        #
        # 반드시 if new_photos 밖에 있어야 함.
        #
        # 사진 없이 텍스트만 수정해도
        # person.save()가 무조건 실행되어야 함.
        # =========================================================

        try:

            with transaction.atomic():

                person.save()

                Log.objects.create(
                    user=user_person,
                    action="실종자 수정",
                    target_type="MissingPerson",
                    target_id=person.id
                )

        except Exception as e:

            logger.exception(
                "[edit_missing] "
                "실종자 수정 저장 실패 | "
                "id=%s | error=%s",
                person.id,
                e,
            )

            return Response(
                {
                    "error": "실종자 정보 수정 중 오류가 발생했습니다.",
                    "detail": str(e),
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

        # =========================================================
        # 16. 저장된 최신 값 다시 불러오기
        # =========================================================

        person.refresh_from_db()

        logger.warning(
            "[edit_missing] 수정 완료 | "
            "id=%s | "
            "clothing=%r | "
            "etc_spfeatr=%r",
            person.id,
            person.clothing,
            person.etc_spfeatr,
        )

        # =========================================================
        # 17. 응답용 사진
        # =========================================================

        photo_items = []

        for path in (
                person.image_urls
                or []
        ):
            photo_items.append(
                {
                    "url": media_url(
                        path,
                        request
                    ),

                    "path": path,

                    "is_ai_generated": (
                            path
                            in (
                                    person.ai_image_urls
                                    or []
                            )
                    ),
                }
            )

        # =========================================================
        # 18. 응답
        # =========================================================

        return Response(
            {
                "message":
                    "실종자 정보 수정 완료",

                "id":
                    person.id,

                "msspsn_idntfccd":
                    person.msspsn_idntfccd,

                "name":
                    person.name,

                "gender":
                    person.gender,

                "age_at_missing":
                    person.age_at_missing,

                "occurred_at":
                    person.occurred_at,

                "occurred_location":
                    person.occurred_location,

                "category":
                    person.category,

                "height":
                    person.height,

                "weight":
                    person.weight,

                "body_type":
                    person.body_type,

                "face_type":
                    person.face_type,

                "hair_color":
                    person.hair_color,

                "hair_style":
                    person.hair_style,

                "clothing":
                    person.clothing,

                "etc_spfeatr":
                    person.etc_spfeatr,

                "photo_count":
                    len(
                        person.image_urls
                        or []
                    ),

                "photos":
                    photo_items,
            },
            status=status.HTTP_200_OK
        )


    @action(detail=True, methods=["patch"], url_path="status", permission_classes=[IsAdmin])
    def update_status(self, request, pk=None):
        person = get_object_or_404(MissingPerson, pk=pk)

        status_value = request.data.get("status")


        if not status_value:
            return Response({"error": "status 필요"}, status=400)

        # 🔥 허용 상태 정의
        ALLOWED = [
            MissingPerson.Status.MISSING,
            MissingPerson.Status.FOUND
        ]

        if status_value not in ALLOWED:
            return Response({"error": "잘못된 status"}, status=400)

        person.status = status_value
        person.save(update_fields=["status"])

        # 🔥 로그 추가 추천
        Log.objects.create(
            user=getattr(request.user, "person", None),
            action=f"실종자 상태 변경 → {status_value}",
            target_type="MissingPerson",
            target_id=person.id
        )
        return Response({
            "message": "상태 변경 완료",
            "status": person.status
        })

    @action(detail=False, methods=["get"], url_path="found", permission_classes=[IsAdmin])
    def found_list(self, request):
        qs = MissingPerson.objects.filter(
            status=MissingPerson.Status.FOUND
        ).order_by("-updated_at")

        serializer = MissingPersonListSerializer(qs, many=True)
        return Response(serializer.data)

class ReportViewSet(viewsets.ViewSet):
    def _save_report_photos_parallel(
            self,
            case,
            upload_items,
    ):
        """
        신고 사진 Cloudinary 병렬 업로드.

        upload_items:
        [
            {
                "file": UploadedFile,
                "photo_type": TipPhoto.PhotoType.SUBJECT,
            },
            ...
        ]

        DB 저장은 메인 스레드에서 처리하고,
        Cloudinary 업로드만 병렬 처리한다.
        """

        if not upload_items:
            return []

        start = time.perf_counter()

        image_field = TipPhoto._meta.get_field("image")
        storage = image_field.storage

        tasks = []

        # =====================================================
        # 1. 저장 경로 미리 생성
        # =====================================================
        for index, item in enumerate(upload_items):
            image_file = item["file"]
            photo_type = item["photo_type"]

            temp_photo = TipPhoto(
                case=case,
                photo_type=photo_type,
                is_ai_generated=False,
            )

            original_name = image_file.name or f"photo_{index}.jpg"

            # 같은 이름 충돌 방지
            unique_name = (
                f"{case.id}_"
                f"{photo_type}_"
                f"{uuid.uuid4().hex[:8]}_"
                f"{original_name}"
            )

            upload_name = image_field.generate_filename(
                temp_photo,
                unique_name,
            )

            tasks.append({
                "file": image_file,
                "photo_type": photo_type,
                "upload_name": upload_name,
            })

        # =====================================================
        # 2. Cloudinary 업로드 함수
        # =====================================================
        def upload_one(task):
            image_file = task["file"]

            try:
                image_file.seek(0)
            except Exception:
                pass

            saved_name = storage.save(
                task["upload_name"],
                image_file,
            )

            return {
                "saved_name": saved_name,
                "photo_type": task["photo_type"],
            }

        uploaded_results = []
        upload_errors = []

        max_workers = min(
            6,
            len(tasks),
        )

        # =====================================================
        # 3. 병렬 Cloudinary 업로드
        # =====================================================
        with ThreadPoolExecutor(
                max_workers=max_workers
        ) as executor:

            future_map = {
                executor.submit(
                    upload_one,
                    task
                ): task
                for task in tasks
            }

            for future in as_completed(
                    future_map
            ):
                task = future_map[future]

                try:
                    result = future.result()
                    uploaded_results.append(
                        result
                    )

                except Exception as e:
                    upload_errors.append(
                        {
                            "task": task,
                            "error": e,
                        }
                    )

        # =====================================================
        # 4. 하나라도 실패하면 업로드된 것 정리
        # =====================================================
        if upload_errors:

            for result in uploaded_results:
                try:
                    storage.delete(
                        result["saved_name"]
                    )
                except Exception:
                    pass

            raise RuntimeError(
                "신고 사진 업로드 중 오류가 발생했습니다: "
                f"{upload_errors[0]['error']}"
            )

        # =====================================================
        # 5. DB 저장은 메인 스레드에서
        # =====================================================
        photo_objects = [
            TipPhoto(
                case=case,
                image=result["saved_name"],
                photo_type=result["photo_type"],
                is_ai_generated=False,
            )
            for result in uploaded_results
        ]

        TipPhoto.objects.bulk_create(
            photo_objects
        )

        elapsed = (
                time.perf_counter()
                - start
        )

        logger.warning(
            "[register_missing] "
            "병렬 사진 저장 완료 | "
            "count=%s | %.2f초",
            len(photo_objects),
            elapsed,
        )

        return photo_objects

    # =========================================================
    # 예방등록 사진 -> 신고 사진 병렬 복사
    # =========================================================
    def _copy_prevention_photos_parallel(
            self,
            case,
            copy_items,
    ):
        """
        PreventionPhoto를 TipPhoto로 병렬 복사.

        copy_items:
        [
            {
                "source_photo": PreventionPhoto,
                "photo_type": TipPhoto.PhotoType.SUBJECT
            },
            ...
        ]

        Cloudinary 읽기 + Cloudinary 저장을 병렬 처리.
        DB 저장은 메인 스레드에서 bulk_create.
        """

        if not copy_items:
            return []

        start = time.perf_counter()

        image_field = TipPhoto._meta.get_field("image")
        storage = image_field.storage

        def copy_one(item):

            source_photo = item["source_photo"]
            target_photo_type = item["photo_type"]

            if (
                    not source_photo
                    or not source_photo.image
            ):
                return None

            source_photo.image.open("rb")

            try:
                content = source_photo.image.read()

            finally:
                try:
                    source_photo.image.close()
                except Exception:
                    pass

            original_name = (
                source_photo.image.name
                .split("/")[-1]
            )

            temp_photo = TipPhoto(
                case=case,
                photo_type=target_photo_type,
                is_ai_generated=False,
            )

            unique_name = (
                f"{case.id}_"
                f"{target_photo_type}_"
                f"{uuid.uuid4().hex[:10]}_"
                f"{original_name}"
            )

            generated_name = image_field.generate_filename(
                temp_photo,
                unique_name,
            )

            saved_name = storage.save(
                generated_name,
                ContentFile(
                    content,
                    name=original_name,
                ),
            )

            return {
                "saved_name": saved_name,
                "photo_type": target_photo_type,
            }

        copied_results = []

        max_workers = min(
            6,
            len(copy_items),
        )

        try:

            with ThreadPoolExecutor(
                    max_workers=max_workers
            ) as executor:

                futures = [
                    executor.submit(
                        copy_one,
                        item,
                    )
                    for item in copy_items
                ]

                for future in as_completed(futures):

                    result = future.result()

                    if result:
                        copied_results.append(
                            result
                        )

        except Exception:

            for result in copied_results:
                try:
                    storage.delete(
                        result["saved_name"]
                    )
                except Exception:
                    pass

            raise

        photo_objects = [
            TipPhoto(
                case=case,
                image=result["saved_name"],
                photo_type=result["photo_type"],
                is_ai_generated=False,
            )
            for result in copied_results
        ]

        if photo_objects:
            TipPhoto.objects.bulk_create(
                photo_objects
            )

        logger.warning(
            "[register_missing] 예방등록 사진 병렬 복사 완료 | "
            "case_id=%s | count=%s | %.2f초",
            case.id,
            len(photo_objects),
            time.perf_counter() - start,
        )

        return photo_objects

    # 제보 생성
    @action(detail=False, methods=["post"], url_path="tip", permission_classes=[AllowAny])
    def create_tip(self, request):
        print("\n\n========== [create_tip] API 호출 시작 ==========")
        print("요청 사용자:", request.user)
        print("요청 사용자 인증 여부:", request.user.is_authenticated)
        print("요청 method:", request.method)
        print("요청 path:", request.path)
        print("Content-Type:", request.content_type)
        print("Request DATA:", request.data)
        print("Request FILES:", request.FILES)
        print("FILES keys:", list(request.FILES.keys()))
        print("photo 존재 여부:", "photo" in request.FILES)
        print("================================================\n")

        serializer = CitizenTipSerializer(data=request.data)

        print("---------- [1] serializer 검증 시작 ----------")
        serializer.is_valid(raise_exception=True)
        print("serializer 검증 성공")
        print("validated_data:", serializer.validated_data)
        print("---------------------------------------------\n")

        data = serializer.validated_data

        # ------------------------------
        # 1️⃣ 실종자 FK 연결
        # ------------------------------
        print("---------- [2] 실종자 FK 연결 확인 ----------")
        missing = None

        # 프론트에서 어떤 이름으로 보내도 받을 수 있게 처리
        missing_seq = (
                data.get("missing_seq")
                or data.get("missing_person_seq")
                or request.data.get("missing_seq")
                or request.data.get("missing_person_seq")
        )

        missing_person_id = (
                data.get("missing_person_id")
                or request.data.get("missing_person_id")
        )

        if missing_seq:
            missing = MissingPerson.objects.filter(
                msspsn_idntfccd=missing_seq
            ).first()

        elif missing_person_id:
            missing = MissingPerson.objects.filter(
                id=missing_person_id
            ).first()

        print("missing_seq:", missing_seq)
        print("missing_person_id:", missing_person_id)
        print("linked missing:", missing)
        print("linked missing id:", getattr(missing, "id", None))
        print("--------------------------------------------\n")

        # ------------------------------
        # 2️⃣ 신고자 처리
        # 로그인 사용자: 기존 유저 정보 자동 사용
        # 비회원 사용자: 직접 입력한 신고자 정보 사용
        # ------------------------------
        print("---------- [3] 신고자 확인 ----------")

        is_logged_in = request.user and request.user.is_authenticated

        reporter = None
        reporter_name = None
        reporter_phone = None

        print("is_logged_in:", is_logged_in)
        print("request.user:", request.user)

        if is_logged_in:
            reporter = getattr(request.user, "person", None)

            if not reporter:
                return Response({
                    "error": "로그인 사용자와 연결된 Person 정보가 없습니다."
                }, status=400)

            # ⚠️ Person 모델 필드명에 맞게 필요 시 수정
            reporter_name = getattr(reporter, "name", None) or getattr(request.user, "email", "")
            reporter_phone = getattr(reporter, "phone", None) or data.get("reporter_phone", "")

            print("로그인 사용자 제보")
            print("reporter:", reporter)
            print("reporter.id:", getattr(reporter, "id", None))
            print("자동 reporter_name:", reporter_name)
            print("자동 reporter_phone:", reporter_phone)

        else:
            reporter_name = data.get("reporter_name")
            reporter_phone = data.get("reporter_phone")

            print("비회원 제보")
            print("입력 reporter_name:", reporter_name)
            print("입력 reporter_phone:", reporter_phone)

            if not reporter_name:
                return Response({
                    "error": "비회원 제보는 신고자 이름이 필요합니다."
                }, status=400)

            if not reporter_phone:
                return Response({
                    "error": "비회원 제보는 신고자 전화번호가 필요합니다."
                }, status=400)

        print("------------------------------------\n")

        # ------------------------------
        # 3️⃣ payload 생성
        # ------------------------------
        print("---------- [4] payload 생성 ----------")

        payload = dict(data)
        payload.pop("photo", None)

        # 로그인/비회원 분기 결과를 payload에 저장
        payload["reporter_name"] = reporter_name
        payload["reporter_phone"] = reporter_phone
        payload["is_guest_report"] = not is_logged_in

        # 연결 실종자 정보도 참고용으로 저장
        payload["missing_seq"] = missing_seq
        payload["missing_person_id"] = missing.id if missing else None
        payload["linked_missing_seq"] = missing.msspsn_idntfccd if missing else None
        payload["linked_missing_name"] = missing.name if missing else None
        print("payload 생성 직후:", payload)
        print("--------------------------------------\n")

        # ------------------------------
        # 4️⃣ datetime → string 변환
        # ------------------------------
        print("---------- [5] datetime 변환 ----------")
        from datetime import datetime

        for k, v in payload.items():
            if isinstance(v, datetime):
                print(f"datetime 변환 대상: {k} = {v}")
                payload[k] = v.isoformat()

        print("datetime 변환 후 payload:", payload)
        print("--------------------------------------\n")

        # ------------------------------
        # 5️⃣ Case 생성
        # ------------------------------
        print("---------- [6] Case 생성 시작 ----------")
        print("missing_person:", missing)
        print("reported_missing_name:", data["missing_name"])
        print("reporter:", reporter)
        print("type_code:", Case.TypeCode.TIP)
        print("occr_date:", data["found_datetime"])
        print("occr_location:", data["found_location"])
        print("payload:", payload)

        case = Case.objects.create(
            missing_person=missing,
            reported_missing_name=data["missing_name"],
            reporter=reporter,
            type_code=Case.TypeCode.TIP,
            status=Case.Status.RECEIVED,
            occr_date=data["found_datetime"],
            occr_location=data["found_location"],
            description="시민 제보",
            payload=payload
        )

        print("Case 생성 완료")
        print("case.id:", case.id)
        print("case.status:", case.status)
        print("--------------------------------------\n")

        # ------------------------------
        # 6️⃣ Feature 저장
        # ------------------------------
        print("---------- [7] Feature 생성 시작 ----------")

        feature = Feature.objects.create(
            case=case,
            physical=data["physical"],
            clothing=data["clothing"],
            health=data.get("health", ""),
            behavior=data.get("behavior", ""),
            etc=data.get("etc", ""),
            ai_source=Feature.AISource.MANUAL,
            confidence=0.0
        )

        print("Feature 생성 완료")
        print("feature.id:", feature.id)
        print("------------------------------------------\n")

        # ------------------------------
        # 7️⃣ 다중 사진 저장
        # ------------------------------
        print("---------- [8] 사진 저장 시작 ----------")

        photos = request.FILES.getlist("photo")

        print("업로드 이미지 개수:", len(photos))

        if len(photos) == 0:
            print("첨부된 제보 사진 없음 → 사진 저장 생략")
        else:
            for idx, photo_file in enumerate(photos, start=1):
                print(f"[사진 {idx}] name:", photo_file.name)
                print(f"[사진 {idx}] size:", photo_file.size)
                print(
                    f"[사진 {idx}] content_type:",
                    getattr(photo_file, "content_type", None)
                )

                tip_photo = TipPhoto.objects.create(
                    case=case,
                    image=photo_file,
                    photo_type=TipPhoto.PhotoType.SUBJECT,
                    is_ai_generated=False,
                )

                print(
                    f"[사진 {idx}] TipPhoto 생성 완료 id:",
                    tip_photo.id
                )
        print("--------------------------------------\n")
        # ------------------------------
        # 8️⃣ 로그 기록
        # 로그인 사용자만 user 저장
        # ------------------------------
        print("---------- [9] Log 생성 ----------")

        if is_logged_in and reporter:
            log = Log.objects.create(
                user=reporter,
                action="시민 제보 생성",
                target_type="Case",
                target_id=case.id
            )

            print("Log 생성 완료")
            print("log.id:", log.id)
            print("log.user:", log.user)
            print("log.target_id:", log.target_id)
        else:
            print("비회원 제보이므로 Log.user 저장 생략")
            # 만약 Log.user가 null 허용이면 아래처럼 저장 가능
            # log = Log.objects.create(
            #     user=None,
            #     action="비회원 시민 제보 생성",
            #     target_type="Case",
            #     target_id=case.id
            # )

        print("----------------------------------\n")

        # ------------------------------
        # 9️⃣ 응답
        # ------------------------------
        response_data = {
            "message": "시민 제보가 접수되었습니다.",
            "case_id": case.id,
            "missing_person_id": missing.id if missing else None,
            "missing_person_seq": missing.msspsn_idntfccd if missing else None,
            "missing_person_name": missing.name if missing else None,
            "linked_missing_seq": missing.msspsn_idntfccd if missing else None,
            "is_guest_report": not is_logged_in,
            "reporter_name": reporter_name,
            "uploaded_images": len(photos),
        }

        print("---------- [10] 최종 응답 ----------")
        print("response_data:", response_data)
        print("========== [create_tip] API 호출 종료 ==========\n\n")

        return Response(response_data, status=201)
    # 신고
    @action(
        detail=False,
        methods=["post"],
        url_path="register-missing",
        permission_classes=[AllowAny]
    )
    def register_missing(self, request):

        total_start = time.perf_counter()

        print(
            "\n\n========== [register_missing] API 호출 시작 =========="
        )

        print(
            "요청 사용자:",
            request.user
        )

        print(
            "요청 사용자 인증 여부:",
            request.user.is_authenticated
        )

        print(
            "photo 개수:",
            len(
                request.FILES.getlist(
                    "photo"
                )
            )
        )

        # =====================================================
        # 1. 요청 데이터 검증
        # =====================================================

        serializer = RegisterMissingSerializer(
            data=request.data
        )

        serializer.is_valid(
            raise_exception=True
        )

        data = serializer.validated_data

        prevention_registration_id = (
            data.get(
                "prevention_registration_id"
            )
        )

        # =====================================================
        # 2. 유사 신고 체크
        # =====================================================

        similar_start = time.perf_counter()

        similar_cases = find_similar_cases(
            name=data.get("name"),
            location=data.get(
                "occurred_location"
            ),
            occurred_at=data.get(
                "occurred_at"
            ),
        )

        logger.warning(
            "[register_missing] 유사 신고 확인 %.3f초",
            time.perf_counter()
            - similar_start,
        )

        if similar_cases:
            return Response(
                {
                    "error":
                        "유사한 신고가 존재합니다.",

                    "duplicate":
                        True,

                    "similar_cases":
                        similar_cases,
                },
                status=status.HTTP_409_CONFLICT,
            )

        # =====================================================
        # 3. 카테고리 매핑
        # =====================================================

        raw_category = (
            data.get(
                "category",
                "",
            )
        )

        normalized = raw_category.replace(
            " ",
            ""
        )

        mapped_category = CATEGORY_MAP.get(
            normalized,
            raw_category,
        )

        # =====================================================
        # 4. 신고자 처리
        # =====================================================

        is_logged_in = bool(
            request.user
            and request.user.is_authenticated
        )

        reporter = None
        reporter_name = None
        reporter_phone = None

        reporter_resident_front = (
            data.get(
                "reporter_resident_front",
                "",
            )
        )

        reporter_resident_back = (
            data.get(
                "reporter_resident_back",
                "",
            )
        )

        if is_logged_in:

            reporter = getattr(
                request.user,
                "person",
                None,
            )

            if not reporter:
                return Response(
                    {
                        "error":
                            "로그인 사용자와 연결된 Person 정보가 없습니다."
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

            reporter_name = (
                    getattr(
                        reporter,
                        "name",
                        None,
                    )
                    or getattr(
                request.user,
                "email",
                "",
            )
            )

            reporter_phone = (
                    getattr(
                        reporter,
                        "phone",
                        None,
                    )
                    or data.get(
                "reporter_phone",
                "",
            )
            )

        else:

            reporter_name = data.get(
                "reporter_name"
            )

            reporter_phone = data.get(
                "reporter_phone"
            )

            if not reporter_name:
                return Response(
                    {
                        "error":
                            "비회원 신고는 신고자 이름이 필요합니다."
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

            if not reporter_phone:
                return Response(
                    {
                        "error":
                            "비회원 신고는 신고자 전화번호가 필요합니다."
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

        # =====================================================
        # 5. 피보호자 연결
        # =====================================================

        person_id = request.data.get(
            "person_id"
        )

        person = None

        if person_id:
            person = (
                Person.objects
                .filter(
                    id=person_id
                )
                .first()
            )

        # =====================================================
        # 5-1. 예방등록 조회
        #
        # Case를 만들기 전에 확인해서
        # 권한 오류 시 불필요한 Case 생성 방지
        # =====================================================

        prevention = None

        if prevention_registration_id:

            prevention = (
                PreventionRegistration.objects
                .filter(
                    id=prevention_registration_id,
                    is_active=True,
                )
                .prefetch_related(
                    "photos"
                )
                .first()
            )

            if (
                    prevention
                    and is_logged_in
                    and prevention.owner_id
                    != reporter.id
            ):
                return Response(
                    {
                        "error":
                            "본인의 피보호자 예방등록만 신고에 사용할 수 있습니다."
                    },
                    status=status.HTTP_403_FORBIDDEN,
                )

        # =====================================================
        # 6. Payload 생성
        # =====================================================

        payload = dict(data)

        # JSONField에 파일 자체는 저장하지 않음
        payload.pop(
            "photo",
            None
        )

        payload[
            "reporter_name"
        ] = reporter_name

        payload[
            "reporter_phone"
        ] = reporter_phone

        payload[
            "reporter_resident_front"
        ] = reporter_resident_front

        payload[
            "reporter_resident_back"
        ] = reporter_resident_back

        payload[
            "category"
        ] = mapped_category

        payload[
            "is_guest_report"
        ] = not is_logged_in

        # =====================================================
        # 7. datetime -> 문자열
        # =====================================================

        from datetime import datetime

        for key, value in list(
                payload.items()
        ):

            if isinstance(
                    value,
                    datetime
            ):
                payload[
                    key
                ] = value.isoformat()

        # =====================================================
        # 8. AI 분류
        #
        # 기존 응답/데이터 구조 유지.
        # 등록 시 동기 AI 호출하지 않음.
        # =====================================================

        payload[
            "description_ai_segments"
        ] = []

        # =====================================================
        # 9. 완전 중복 신고 체크
        #
        # 기존 응답 구조 그대로 유지
        # =====================================================

        duplicate_exists = (
            Case.objects
            .filter(
                reported_missing_name=data.get(
                    "name"
                ),
                occr_date=data.get(
                    "occurred_at"
                ),
            )
            .exists()
        )

        if duplicate_exists:
            return Response(
                {
                    "error":
                        "이미 등록된 신고"
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        # =====================================================
        # 10. 키 / 몸무게 문자열 처리
        # =====================================================

        if payload.get(
                "height"
        ) not in [
            None,
            "",
        ]:
            payload["height"] = str(
                payload["height"]
            )

        if payload.get(
                "weight"
        ) not in [
            None,
            "",
        ]:
            payload["weight"] = str(
                payload["weight"]
            )

        # =====================================================
        # 11. Case 생성
        # =====================================================

        case_start = time.perf_counter()

        case = Case.objects.create(
            type_code=(
                Case.TypeCode.MISSING
            ),

            status=(
                Case.Status.RECEIVED
            ),

            reporter=reporter,

            person=person,

            description=data.get(
                "description",
                "시민 실종자 등록 요청",
            ),

            occr_date=data.get(
                "occurred_at"
            ),

            occr_location=data.get(
                "occurred_location"
            ),

            payload=payload,

            reported_missing_name=data.get(
                "name"
            ),
        )

        logger.warning(
            "[register_missing] Case 생성 %.3f초",
            time.perf_counter()
            - case_start,
        )

        # =====================================================
        # 12. 직접 업로드 사진 준비
        #
        # 프론트 파라미터 이름 그대로 유지
        # =====================================================

        photos = request.FILES.getlist(
            "photo"
        )

        parent1_face_photo = (
            request.FILES.get(
                "parent1_face_photo"
            )
        )

        parent2_face_photo = (
            request.FILES.get(
                "parent2_face_photo"
            )
        )

        direct_upload_items = []

        # -------------------------------------------------
        # 대상자 사진
        # -------------------------------------------------

        for file in photos:
            direct_upload_items.append({
                "file":
                    file,

                "photo_type":
                    TipPhoto.PhotoType.SUBJECT,
            })

        # -------------------------------------------------
        # 부모사진 1
        # -------------------------------------------------

        if parent1_face_photo:
            direct_upload_items.append({
                "file":
                    parent1_face_photo,

                "photo_type":
                    TipPhoto.PhotoType.PARENT1_FACE,
            })

        # -------------------------------------------------
        # 부모사진 2
        # -------------------------------------------------

        if parent2_face_photo:
            direct_upload_items.append({
                "file":
                    parent2_face_photo,

                "photo_type":
                    TipPhoto.PhotoType.PARENT2_FACE,
            })

        # =====================================================
        # 13. 예방등록 사진 준비
        #
        # prefetch된 photos를 메모리에서만 분류.
        # .filter()를 반복해서 DB 재조회하지 않음.
        # =====================================================

        prevention_copy_items = []

        if prevention:

            prevention_photos = [
                p
                for p
                in prevention.photos.all()
                if p.image
            ]

            # ---------------------------------------------
            # 대상자 사진
            #
            # 프론트가 photo를 직접 안 보낸 경우만
            # 예방등록 사진 복사
            # ---------------------------------------------

            if not photos:

                subject_types = {
                    "face",
                    "full_body",
                    "left_side",
                    "right_side",
                }

                for source_photo in prevention_photos:

                    if (
                            source_photo.photo_type
                            in subject_types
                    ):
                        prevention_copy_items.append({
                            "source_photo":
                                source_photo,

                            "photo_type":
                                TipPhoto.PhotoType.SUBJECT,
                        })

            # ---------------------------------------------
            # 부모사진 1
            # ---------------------------------------------

            if not parent1_face_photo:

                source_parent1 = next(
                    (
                        p
                        for p
                        in prevention_photos
                        if (
                            p.photo_type
                            == "parent1_face"
                    )
                    ),
                    None,
                )

                if source_parent1:
                    prevention_copy_items.append({
                        "source_photo":
                            source_parent1,

                        "photo_type":
                            TipPhoto.PhotoType.PARENT1_FACE,
                    })

            # ---------------------------------------------
            # 부모사진 2
            # ---------------------------------------------

            if not parent2_face_photo:

                source_parent2 = next(
                    (
                        p
                        for p
                        in prevention_photos
                        if (
                            p.photo_type
                            == "parent2_face"
                    )
                    ),
                    None,
                )

                if source_parent2:
                    prevention_copy_items.append({
                        "source_photo":
                            source_parent2,

                        "photo_type":
                            TipPhoto.PhotoType.PARENT2_FACE,
                    })

        # =====================================================
        # 14. 사진 저장
        #
        # 직접 업로드 사진:
        #   병렬 Cloudinary upload
        #
        # 예방등록 사진:
        #   병렬 download + upload
        # =====================================================

        photo_start = time.perf_counter()

        try:

            # 직접 올라온 사진
            if direct_upload_items:
                self._save_report_photos_parallel(
                    case=case,
                    upload_items=direct_upload_items,
                )

            # 예방등록 사진 복사
            if prevention_copy_items:
                self._copy_prevention_photos_parallel(
                    case=case,
                    copy_items=prevention_copy_items,
                )

        except Exception as e:

            logger.exception(
                "[register_missing] "
                "신고 사진 저장 실패 | "
                "case_id=%s | error=%s",
                case.id,
                e,
            )

            # -------------------------------------------------
            # 불완전 신고가 DB에 남지 않게 삭제
            # -------------------------------------------------

            try:
                case.delete()
            except Exception:
                pass

            return Response(
                {
                    "error":
                        "신고 사진 저장 중 오류가 발생했습니다."
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        photo_elapsed = (
                time.perf_counter()
                - photo_start
        )

        logger.warning(
            "[register_missing] "
            "전체 사진 처리 완료 | "
            "case_id=%s | "
            "직접사진=%s | "
            "예방등록복사=%s | "
            "%.2f초",
            case.id,
            len(direct_upload_items),
            len(prevention_copy_items),
            photo_elapsed,
        )

        # =====================================================
        # 15. 로그 기록
        # =====================================================

        if (
                is_logged_in
                and reporter
        ):
            Log.objects.create(
                user=reporter,
                action="실종자 신고 생성",
                target_type="Case",
                target_id=case.id,
            )

        # =====================================================
        # 16. 기존과 동일한 최종 응답
        #
        # ★ 프론트 계약 변경 금지
        # =====================================================

        response_data = {
            "message":
                "등록 요청이 접수되었습니다.",

            "case_id":
                case.id,

            "linked_person": (
                person.id
                if person
                else None
            ),

            # 기존 의미 그대로:
            # 프론트가 직접 photo 필드로 보낸 사진 수
            "uploaded_images":
                len(photos),

            "description_ai_segments":
                [],
        }

        total_elapsed = (
                time.perf_counter()
                - total_start
        )

        logger.warning(
            "[register_missing] 전체 처리 완료 | "
            "case_id=%s | total=%.2f초 | photos=%.2f초",
            case.id,
            total_elapsed,
            photo_elapsed,
        )

        print(
            "========== [register_missing] "
            f"API 호출 종료 / {total_elapsed:.2f}초 "
            "==========\n"
        )

        return Response(
            response_data,
            status=status.HTTP_201_CREATED,
        )
class PreventionRegistrationViewSet(viewsets.ModelViewSet):

    """
    실종 예방 등록 ViewSet

    사용자:
    POST   /dasibom/prevention-registrations/
    GET    /dasibom/prevention-registrations/
    GET    /dasibom/prevention-registrations/{id}/
    PATCH  /dasibom/prevention-registrations/{id}/
    PATCH  /dasibom/prevention-registrations/{id}/deactivate/

    관리자:
    GET    /dasibom/prevention-registrations/admin/
    PATCH  /dasibom/prevention-registrations/{id}/admin-status/
    DELETE /dasibom/prevention-registrations/{id}/delete/
    """

    permission_classes = [IsAuthenticated]

    photo_files_map = {
        "face_photo": "face",
        "full_body_photo": "full_body",
        "left_side_photo": "left_side",
        "right_side_photo": "right_side",

        # 부모님/가족 정면 사진 2장: 권장
        "parent1_face_photo": "parent1_face",
        "parent2_face_photo": "parent2_face",
    }

    # -------------------------------------------------
    # 공통 헬퍼
    # -------------------------------------------------
    def _is_admin(self, request):
        return getattr(request.user, "role", None) == "admin"

    def _generate_next_device_code(self):
        """
        기존 KIOSK_XXX 중 가장 큰 번호 다음 번호를 생성한다.

        예:
        KIOSK_001
        KIOSK_002
        → KIOSK_003
        """

        devices = Device.objects.filter(
            device_uid__startswith="KIOSK_"
        ).values_list("device_uid", flat=True)

        max_number = 0

        for device_uid in devices:
            try:
                number = int(device_uid.split("_")[-1])
                max_number = max(max_number, number)
            except (ValueError, IndexError):
                continue

        return f"KIOSK_{max_number + 1:03d}"
    def _status_label(self, status_value):
        labels = {
            PreventionRegistration.Status.RECEIVED: "접수중",
            PreventionRegistration.Status.REVIEWING: "확인중",
            PreventionRegistration.Status.COMPLETED: "등록 완료",
            PreventionRegistration.Status.REJECTED: "거절됨",
        }
        return labels.get(status_value, status_value)

    def _format_datetime_for_front(self, dt):
        """
        프론트 표시용 날짜 포맷.
        예: 2026-06-01T02:25:00Z -> 2026.06.01
        """
        if not dt:
            return None

        try:
            local_dt = timezone.localtime(dt)
            return local_dt.strftime("%Y.%m.%d")
        except Exception:
            return None

    def _build_photo_url(
            self,
            request,
            photo,
    ):
        if not photo or not photo.image:
            return None

        try:
            return media_url(
                photo.image.name,
                request,
            )
        except Exception:
            return None

    def _get_main_photo_url(self, request, registration):
        """
        프론트 카드 대표 이미지.
        1순위: face 사진
        2순위: 첫 번째 사진
        """

        photos = list(
            registration.photos.all()
        )

        if not photos:
            return None

        face_photo = next(
            (
                photo
                for photo in photos
                if photo.photo_type == "face"
            ),
            None
        )

        if face_photo:
            return self._build_photo_url(
                request,
                face_photo
            )

        return self._build_photo_url(
            request,
            photos[0]
        )
    def _get_photo_validation_summary(self, registration):
        """
        프론트 목록 카드에서 사용하는 사진 검증 요약.

        프론트 사용:
        summary['total']
        summary['valid']
        summary['warning']
        summary['invalid']
        summary['error']
        """
        photos = list(
            registration.photos.all()
        )

        summary = {
            "total": len(photos),
            "valid": 0,
            "warning": 0,
            "invalid": 0,
            "error": 0,
            "unchecked": 0,
        }

        for photo in photos:
            validation_status = photo.validation_status or "unchecked"

            if validation_status == "valid":
                summary["valid"] += 1
            elif validation_status == "warning":
                summary["warning"] += 1
            elif validation_status == "invalid":
                summary["invalid"] += 1
            elif validation_status == "error":
                summary["error"] += 1
            else:
                summary["unchecked"] += 1

        return summary

    def _get_photo_items(self, request, registration):
        """
        상세/디버깅용 사진 목록.
        수정페이지에서 사진별 상태 확인이 필요할 때 사용 가능.
        """
        items = []

        for photo in registration.photos.all():
            items.append({
                "id": photo.id,
                "photo_type": photo.photo_type,
                "image": (
                    photo.image.name
                    if photo.image
                    else None
                ),
                "url": self._build_photo_url(request, photo),
                "is_validated": photo.is_validated,
                "validation_status": photo.validation_status,
                "validation_message": photo.validation_message,
                "validation_confidence": photo.validation_confidence,
                "created_at": self._format_datetime_for_front(photo.created_at),
            })

        return items

    def _build_list_item(self, request, registration):
        """
        RegisterStatusTab 프론트 목록 카드에 맞춘 응답 구조.
        """
        owner = registration.owner
        reviewed_by = registration.reviewed_by

        owner_name = owner.name if owner else None
        owner_phone = owner.phone if owner else None

        return {
            "id": registration.id,
            "name": registration.name,
            "gender": registration.gender,
            "status": registration.status,
            "status_label": self._status_label(registration.status),
            "device_code": registration.device_code,
            "created_at": self._format_datetime_for_front(registration.created_at),
            "updated_at": self._format_datetime_for_front(registration.updated_at),

            "rejected_reason": registration.rejected_reason,
            "is_active": registration.is_active,

            # 프론트 카드용 필드
            "main_photo": self._get_main_photo_url(request, registration),
            "photo_validation_summary": self._get_photo_validation_summary(registration),

            # 관리자 목록에서 신청자 표시용
            "user_name": owner_name,
            "reporter_name": owner_name,
            "user_phone": owner_phone,
            "reporter_phone": owner_phone,

            # 보호자 정보
            "guardian_name": registration.guardian_name,
            "guardian_phone": registration.guardian_phone,

            # 관리자 검토 정보
            "reviewed_by": reviewed_by.id if reviewed_by else None,
            "reviewed_by_name": reviewed_by.name if reviewed_by else None,
            "reviewed_at": self._format_datetime_for_front(registration.reviewed_at),
        }

    def _build_detail_item(self, request, registration):
        """
        상세 조회용 응답.
        기존 Serializer 응답에 프론트에서 바로 쓰기 좋은 필드를 보강한다.
        """
        serializer = PreventionRegistrationSerializer(
            registration,
            context={"request": request}
        )

        data = dict(serializer.data)

        owner = registration.owner
        reviewed_by = registration.reviewed_by
        # 실제 연결된 피보호자의 배지 조회
        device = None

        if registration.linked_person:
            device = getattr(
                registration.linked_person,
                "badge",
                None
            )

        device_code = (
            device.device_uid
            if device
            else registration.device_code
        )
        data.update({
            "id": registration.id,
            "name": registration.name,
            "gender": registration.gender,
            "status": registration.status,
            "status_label": self._status_label(registration.status),

            "created_at": self._format_datetime_for_front(registration.created_at),
            "updated_at": self._format_datetime_for_front(registration.updated_at),

            "rejected_reason": registration.rejected_reason,
            "is_active": registration.is_active,

            "main_photo": self._get_main_photo_url(request, registration),
            "photo_validation_summary": self._get_photo_validation_summary(registration),
            "photo_items": self._get_photo_items(request, registration),
            "device_code": device_code,            "user_name": owner.name if owner else None,
            "reporter_name": owner.name if owner else None,
            "user_phone": owner.phone if owner else None,
            "reporter_phone": owner.phone if owner else None,

            "reviewed_by": reviewed_by.id if reviewed_by else None,
            "reviewed_by_name": reviewed_by.name if reviewed_by else None,
            "reviewed_at": self._format_datetime_for_front(registration.reviewed_at),
        })

        return data

    def get_queryset(self):
        user = self.request.user

        qs = (
            PreventionRegistration.objects
            .select_related("owner", "reviewed_by")
            .prefetch_related("photos")
            .order_by("-created_at")
        )

        # 관리자는 전체 조회 가능
        if getattr(user, "role", None) == "admin":
            return qs

        # 일반 사용자는 본인 것 + 활성화된 것만 조회
        return qs.filter(owner=user.person, is_active=True)

    def get_serializer_class(self):
        if self.action in ["list", "admin"]:
            return PreventionRegistrationListSerializer

        return PreventionRegistrationSerializer

    # -------------------------------------------------
    # 사용자 목록 조회
    # GET /dasibom/prevention-registrations/
    # -------------------------------------------------
    def list(self, request, *args, **kwargs):
        """
        RegisterStatusTab 프론트 목록 카드용 응답.

        프론트 사용 필드:
        - id
        - name
        - gender
        - status
        - created_at
        - main_photo
        - rejected_reason
        - photo_validation_summary
        - user_name
        - reporter_name
        """
        qs = self.get_queryset()

        data = [
            self._build_list_item(request, registration)
            for registration in qs
        ]

        return Response(data, status=status.HTTP_200_OK)

    # -------------------------------------------------
    # 상세 조회
    # GET /dasibom/prevention-registrations/{id}/
    # -------------------------------------------------
    def retrieve(self, request, *args, **kwargs):
        registration = self.get_object()

        return Response(
            self._build_detail_item(request, registration),
            status=status.HTTP_200_OK
        )

    # -------------------------------------------------
    # 사진 검증
    # -------------------------------------------------
    def _validate_uploaded_photos(self, files):
        validation_results = {}

        for file_key, photo_type in self.photo_files_map.items():
            image_file = files.get(file_key)

            if not image_file:
                continue

            validation_results[file_key] = {
                "is_valid": True,
                "status": "unchecked",
                "message": "사진 검증을 생략했습니다.",
                "confidence": None,
            }

        return validation_results

    def _save_uploaded_photos(
            self,
            registration,
            files,
            validation_results,
            replace=False
    ):
        """
        사진 파일은 Cloudinary에 병렬 업로드하고,
        모든 업로드가 성공한 뒤 DB에는 순차 저장한다.

        - 프론트/응답 구조 변경 없음
        - photo_type 변경 없음
        - validation_status 구조 변경 없음
        - replace=True 동작 유지
        """

        start_time = time.perf_counter()

        image_field = PreventionPhoto._meta.get_field("image")
        storage = image_field.storage

        upload_tasks = []

        # -------------------------------------------------
        # 1. 업로드할 사진 목록 준비
        # -------------------------------------------------
        for file_key, photo_type in self.photo_files_map.items():
            image_file = files.get(file_key)

            if not image_file:
                continue

            validation = validation_results.get(
                file_key,
                {
                    "status": "unchecked",
                    "message": "검증되지 않은 사진입니다.",
                    "confidence": None,
                }
            )

            # ImageField의 기존 upload_to 규칙 그대로 적용
            temp_instance = PreventionPhoto(
                registration=registration,
                photo_type=photo_type,
            )

            original_name = image_file.name

            upload_name = image_field.generate_filename(
                temp_instance,
                f"{photo_type}_{original_name}",
            )

            upload_tasks.append({
                "file_key": file_key,
                "photo_type": photo_type,
                "file": image_file,
                "upload_name": upload_name,
                "validation": validation,
            })

        if not upload_tasks:
            return

        print(
            f"🚀 병렬 사진 업로드 시작 "
            f"| registration_id={registration.id} "
            f"| count={len(upload_tasks)}"
        )

        # -------------------------------------------------
        # 2. Cloudinary 업로드 함수
        # -------------------------------------------------
        def upload_one(task):
            image_file = task["file"]

            # 파일 포인터 처음으로
            image_file.seek(0)

            saved_name = storage.save(
                task["upload_name"],
                image_file,
            )

            return {
                "file_key": task["file_key"],
                "photo_type": task["photo_type"],
                "saved_name": saved_name,
                "validation": task["validation"],
            }

        uploaded_results = []
        upload_errors = []

        # 사진은 최대 6장이므로 최대 6개 동시 처리
        max_workers = min(6, len(upload_tasks))

        # -------------------------------------------------
        # 3. Cloudinary 병렬 업로드
        # -------------------------------------------------
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_map = {
                executor.submit(upload_one, task): task
                for task in upload_tasks
            }

            for future in as_completed(future_map):
                task = future_map[future]

                try:
                    result = future.result()
                    uploaded_results.append(result)

                    print(
                        f"✅ 업로드 완료: "
                        f"{result['file_key']} "
                        f"→ {result['saved_name']}"
                    )

                except Exception as e:
                    upload_errors.append({
                        "task": task,
                        "error": e,
                    })

                    print(
                        f"❌ 업로드 실패: "
                        f"{task['file_key']} "
                        f"| {e}"
                    )

        # -------------------------------------------------
        # 4. 하나라도 실패했으면 이미 올라간 파일 정리 후 실패
        # -------------------------------------------------
        if upload_errors:
            print("❌ 일부 사진 업로드 실패 → 업로드된 파일 정리 시작")

            for result in uploaded_results:
                try:
                    storage.delete(result["saved_name"])
                except Exception as cleanup_error:
                    print(
                        f"⚠ 업로드 파일 정리 실패: "
                        f"{result['saved_name']} "
                        f"| {cleanup_error}"
                    )

            first_error = upload_errors[0]["error"]

            raise RuntimeError(
                f"사진 업로드 중 오류가 발생했습니다: {first_error}"
            )

        # -------------------------------------------------
        # 5. replace=True인 경우 기존 동일 타입 사진 삭제
        #
        # 새 파일 업로드가 전부 성공한 뒤 삭제하기 때문에
        # 업로드 실패 때문에 기존 사진까지 사라지는 상황 방지
        # -------------------------------------------------
        if replace:
            replace_types = [
                result["photo_type"]
                for result in uploaded_results
            ]

            PreventionPhoto.objects.filter(
                registration=registration,
                photo_type__in=replace_types,
            ).delete()

        # -------------------------------------------------
        # 6. DB 저장
        #
        # DB 작업은 스레드에서 하지 않음.
        # 현재 transaction.atomic() 안에서 정상 처리됨.
        # -------------------------------------------------
        photo_objects = []

        for result in uploaded_results:
            validation = result["validation"]

            photo_objects.append(
                PreventionPhoto(
                    registration=registration,
                    photo_type=result["photo_type"],

                    image=result["saved_name"],

                    is_validated=validation.get("status") in ("valid", "warning"),
                    validation_status=validation.get(
                        "status",
                        "unchecked"
                    ),
                    validation_message=validation.get(
                        "message"
                    ),
                    validation_confidence=validation.get(
                        "confidence"
                    ),
                )
            )

        PreventionPhoto.objects.bulk_create(photo_objects)

        elapsed = time.perf_counter() - start_time

        print(
            f"✅ 병렬 사진 저장 완료 "
            f"| count={len(photo_objects)} "
            f"| 소요시간={elapsed:.2f}초"
        )    # -------------------------------------------------
    # 생성
    # -------------------------------------------------
    def create(self, request, *args, **kwargs):
        """
        실종 예방 등록 생성 + 사진 자동 검증
        생성 직후 status = received

        디버깅 강화 버전:
        - request.data 전체 출력
        - request.FILES 전체 출력
        - serializer.errors 출력
        - 사진 검증 결과/실패 원인 출력
        - 저장 실패 원인 출력
        """

        print("\n\n========== [PreventionRegistration create] API 호출 시작 ==========")
        print("[0] 요청 기본 정보")
        print("request.user:", request.user)
        print("request.user.is_authenticated:", request.user.is_authenticated)
        print("request.user.role:", getattr(request.user, "role", None))
        print("request.user.person:", getattr(request.user, "person", None))
        print("request.method:", request.method)
        print("request.path:", request.path)
        print("content_type:", request.content_type)
        print("===============================================================\n")

        # -------------------------------------------------
        # 1. 원본 request.data 확인
        # -------------------------------------------------
        print("---------- [1] 원본 request.data ----------")
        print("request.data type:", type(request.data))
        print("request.data:", request.data)

        try:
            print("request.data keys:", list(request.data.keys()))
            for key in request.data.keys():
                try:
                    print(f"DATA[{key}] =", request.data.get(key))
                except Exception as e:
                    print(f"DATA[{key}] 출력 실패:", e)
        except Exception as e:
            print("request.data keys 출력 실패:", e)

        print("------------------------------------------\n")

        # -------------------------------------------------
        # 2. request.FILES 확인
        # -------------------------------------------------
        print("---------- [2] request.FILES ----------")
        print("request.FILES type:", type(request.FILES))
        print("request.FILES:", request.FILES)
        print("request.FILES keys:", list(request.FILES.keys()))

        for file_key in request.FILES.keys():
            try:
                files = request.FILES.getlist(file_key)
            except Exception:
                files = [request.FILES.get(file_key)]

            print(f"FILES[{file_key}] count:", len(files))

            for idx, file in enumerate(files, start=1):
                print(f"  - {file_key}[{idx}].name:", getattr(file, "name", None))
                print(f"  - {file_key}[{idx}].size:", getattr(file, "size", None))
                print(f"  - {file_key}[{idx}].content_type:", getattr(file, "content_type", None))

        print("---------------------------------------\n")

        # -------------------------------------------------
        # 3. 프론트 요청 데이터 복사 후 누락 필드 보완
        # -------------------------------------------------
        print("---------- [3] request.data 복사 및 기본값 보완 ----------")

        data = {}

        for key in request.data.keys():
            # 파일과 프론트 사진 검증 결과는 serializer 데이터에서 제외
            if key not in request.FILES and not key.endswith("_validation_status"):
                data[key] = request.data.get(key)
        # 프론트는 _isAgreed, _isVerified를 내부 상태로만 검사하고
        # privacy_agreed / phone_verified를 request.fields에 안 넣을 수 있음
        if "privacy_agreed" not in data:
            data["privacy_agreed"] = True
            print("privacy_agreed 미전송 → True로 보완")
        else:
            print("privacy_agreed 수신:", data.get("privacy_agreed"))

        if "phone_verified" not in data:
            data["phone_verified"] = True
            print("phone_verified 미전송 → True로 보완")
        else:
            print("phone_verified 수신:", data.get("phone_verified"))

        person = getattr(request.user, "person", None)

        if person:
            print("로그인 person 정보 있음:", person)
            print("person.name:", getattr(person, "name", None))
            print("person.phone:", getattr(person, "phone", None))

            if not data.get("guardian_name"):
                data["guardian_name"] = getattr(person, "name", "")
                print("guardian_name 비어 있음 → person.name으로 보완:", data["guardian_name"])

            if not data.get("guardian_phone"):
                data["guardian_phone"] = getattr(person, "phone", "")
                print("guardian_phone 비어 있음 → person.phone으로 보완:", data["guardian_phone"])
        else:
            print("로그인 user에 연결된 person 없음")

        print("보완 후 data:", data)
        print("보완 후 data keys:", list(data.keys()))

        for key in data.keys():
            try:
                print(f"FINAL_DATA[{key}] =", data.get(key))
            except Exception as e:
                print(f"FINAL_DATA[{key}] 출력 실패:", e)

        print("-------------------------------------------------------\n")

        # -------------------------------------------------
        # 4. Serializer 검증
        # -------------------------------------------------
        print("---------- [4] serializer 검증 시작 ----------")

        serializer = self.get_serializer(data=data)

        if not serializer.is_valid():
            print("❌ [PreventionRegistration serializer 검증 실패]")
            print("serializer.errors:", serializer.errors)

            try:
                print("serializer.errors JSON:", json.dumps(serializer.errors, ensure_ascii=False, default=str))
            except Exception as e:
                print("serializer.errors JSON 변환 실패:", e)

            print("========== [PreventionRegistration create] 400 종료 - serializer 검증 실패 ==========\n\n")

            return Response(
                {
                    "error": "입력값 검증에 실패했습니다.",
                    "detail": serializer.errors,
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        print("✅ [PreventionRegistration serializer 검증 성공]")
        print("validated_data:", serializer.validated_data)

        try:
            print(
                "validated_data JSON:",
                json.dumps(serializer.validated_data, ensure_ascii=False, default=str)
            )
        except Exception as e:
            print("validated_data JSON 변환 실패:", e)

        print("---------------------------------------------\n")

        # -------------------------------------------------
        # 5. 프론트 ML Kit 사진 검증 결과 수신
        # -------------------------------------------------
        print("---------- [5] 프론트 사진 검증 결과 수신 ----------")

        validation_results = {}

        print("전달된 validation status:")
        for key in request.data.keys():
            if key.endswith("_validation_status"):
                print(f"  {key} = {request.data.get(key)}")

        for file_key, photo_type in self.photo_files_map.items():
            image_file = request.FILES.get(file_key)

            if not image_file:
                continue

            status_key = f"{file_key}_validation_status"
            frontend_status = request.data.get(status_key)

            if frontend_status:
                frontend_status = str(frontend_status).strip().lower()

            # 프론트 정책
            # valid   → 정상 통과
            # warning → 사용자가 '그래도 사용' 선택
            # 미전송   → 등록은 허용하되 unchecked
            if frontend_status == "valid":
                validation_results[file_key] = {
                    "is_valid": True,
                    "status": "valid",
                    "message": "ML Kit 사진 검증을 통과했습니다.",
                    "confidence": None,
                }

            elif frontend_status == "warning":
                validation_results[file_key] = {
                    "is_valid": True,
                    "status": "warning",
                    "message": "사진 기준과 다를 수 있으나 사용자가 등록을 선택했습니다.",
                    "confidence": None,
                }

            else:
                validation_results[file_key] = {
                    "is_valid": False,
                    "status": "unchecked",
                    "message": "사진 검증 결과가 전달되지 않았습니다.",
                    "confidence": None,
                }

            print(
                f"{file_key}: "
                f"받은값={frontend_status}, "
                f"저장상태={validation_results[file_key]['status']}"
            )

        print("validation_results:", validation_results)
        print("-----------------------------------------------\n")
        # -------------------------------------------------
        # 6. 저장
        # -------------------------------------------------
        print("---------- [6] DB 저장 시작 ----------")

        try:
            with transaction.atomic():
                print("serializer.save() 호출 직전")
                print("owner:", request.user.person)
                print("status:", PreventionRegistration.Status.RECEIVED)
                print("is_active:", True)

                registration = serializer.save(
                    owner=request.user.person,
                    status=PreventionRegistration.Status.RECEIVED,
                    is_active=True,
                )

                print("✅ PreventionRegistration 생성 완료")
                print("registration.id:", registration.id)
                print("registration.name:", registration.name)
                print("registration.gender:", registration.gender)
                print("registration.status:", registration.status)
                print("registration.owner:", registration.owner)
                print("registration.guardian_name:", registration.guardian_name)
                print("registration.guardian_phone:", registration.guardian_phone)

                print("사진 저장 시작")
                self._save_uploaded_photos(
                    registration=registration,
                    files=request.FILES,
                    validation_results=validation_results,
                    replace=False
                )
                print("✅ 사진 저장 완료")
                print("registration.photos.count():", registration.photos.count())

                print("Log 생성 시작")
                log = Log.objects.create(
                    user=getattr(request.user, "person", None),
                    action="실종 예방 등록 생성",
                    target_type="PreventionRegistration",
                    target_id=registration.id,
                )
                print("✅ Log 생성 완료")
                print("log.id:", log.id)
                print("log.user:", log.user)
                print("log.target_type:", log.target_type)
                print("log.target_id:", log.target_id)

        except Exception as e:
            print("❌ [PreventionRegistration 저장 실패]")
            print("error:", str(e))
            print("========== [PreventionRegistration create] 500 종료 - DB 저장 실패 ==========\n\n")

            return Response(
                {
                    "error": "실종 예방 등록 저장 중 오류가 발생했습니다.",
                    "detail": str(e),
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

        # -------------------------------------------------
        # 7. 최종 응답
        # -------------------------------------------------
        print("---------- [7] 최종 응답 생성 ----------")

        response_data = self._build_detail_item(request, registration)

        print("response_data:", response_data)

        try:
            print("response_data JSON:", json.dumps(response_data, ensure_ascii=False, default=str))
        except Exception as e:
            print("response_data JSON 변환 실패:", e)

        print("========== [PreventionRegistration create] API 호출 종료 ==========\n\n")

        return Response(
            response_data,
            status=status.HTTP_201_CREATED
        )    # -------------------------------------------------
    # 수정
    # -------------------------------------------------
    def update(self, request, *args, **kwargs):
        """
        실종 예방 등록 수정

        일반 회원:
        - 본인 등록 건만 수정 가능
        - received / completed 상태에서 수정 가능

        관리자:
        - 모든 상태에서 수정 가능

        사진 수정:
        - 기존 사진 삭제:
            delete_photos = JSON 문자열 "[1,2,3]"
            또는 리스트 형태 지원

        - 새 사진 추가/교체:
            face_photo
            full_body_photo
            left_side_photo
            right_side_photo
            parent1_face_photo
            parent2_face_photo

        같은 photo_type의 새 사진이 들어오면
        기존 사진을 새 사진으로 교체한다.
        """

        # =========================================================
        # 0. 기본 설정
        # =========================================================
        partial = kwargs.pop("partial", False)

        registration = self.get_object()

        # =========================================================
        # 1. 권한 확인
        # =========================================================
        is_admin = self._is_admin(request)

        user_person = getattr(
            request.user,
            "person",
            None
        )

        is_owner = (
                user_person is not None
                and registration.owner == user_person
        )

        if not (is_admin or is_owner):
            return Response(
                {
                    "error": "본인 또는 관리자만 수정할 수 있습니다."
                },
                status=status.HTTP_403_FORBIDDEN
            )

        # =========================================================
        # 2. 상태별 수정 권한
        #
        # 일반 사용자:
        # received  -> 가능
        # reviewing -> 불가
        # completed -> 가능
        # rejected  -> 불가
        #
        # 관리자:
        # 모든 상태 가능
        # =========================================================
        if not is_admin:

            allowed_statuses = [
                PreventionRegistration.Status.RECEIVED,
                PreventionRegistration.Status.COMPLETED,
            ]

            if registration.status not in allowed_statuses:
                return Response(
                    {
                        "error": (
                            "접수중(received) 또는 "
                            "등록완료(completed) 상태인 경우만 "
                            "본인이 수정할 수 있습니다."
                        )
                    },
                    status=status.HTTP_400_BAD_REQUEST
                )

        # =========================================================
        # 3. 일반 데이터 Serializer 검증
        # =========================================================
        serializer = self.get_serializer(
            registration,
            data=request.data,
            partial=partial
        )

        serializer.is_valid(
            raise_exception=True
        )

        # =========================================================
        # 4. 새로 업로드된 사진 검증
        # =========================================================
        try:
            validation_results = (
                self._validate_uploaded_photos(
                    request.FILES
                )
            )

        except ValueError as e:
            return Response(
                {
                    "error": str(e),
                    "message": "사진 검증에 실패했습니다."
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        # =========================================================
        # 5. 기존 사진 삭제 ID 파싱
        #
        # 지원:
        #
        # delete_photos = "[1,2,3]"
        #
        # delete_photos = [1,2,3]
        #
        # multipart:
        # delete_photos = ["[1,2,3]"]
        # =========================================================
        delete_photo_ids = []

        if "delete_photos" in request.data:

            try:
                # multipart QueryDict인 경우
                if hasattr(
                        request.data,
                        "getlist"
                ):
                    raw_delete = (
                        request.data.getlist(
                            "delete_photos"
                        )
                    )

                    # ["[1,2,3]"]
                    if (
                            len(raw_delete) == 1
                            and isinstance(
                        raw_delete[0],
                        str
                    )
                    ):
                        raw_value = (
                            raw_delete[0].strip()
                        )

                        if raw_value.startswith("["):
                            try:
                                raw_delete = json.loads(
                                    raw_value
                                )
                            except Exception:
                                raw_delete = [
                                    raw_value
                                ]

                        elif "," in raw_value:
                            raw_delete = [
                                value.strip()
                                for value
                                in raw_value.split(",")
                                if value.strip()
                            ]

                else:
                    raw_delete = (
                        request.data.get(
                            "delete_photos",
                            []
                        )
                    )

                # 일반 문자열 처리
                if isinstance(
                        raw_delete,
                        str
                ):
                    raw_delete = raw_delete.strip()

                    if raw_delete.startswith("["):
                        raw_delete = json.loads(
                            raw_delete
                        )

                    elif "," in raw_delete:
                        raw_delete = [
                            value.strip()
                            for value
                            in raw_delete.split(",")
                            if value.strip()
                        ]

                    elif raw_delete:
                        raw_delete = [
                            raw_delete
                        ]

                    else:
                        raw_delete = []

                # 리스트가 아닌 값도 리스트화
                if not isinstance(
                        raw_delete,
                        list
                ):
                    raw_delete = [
                        raw_delete
                    ]

                # int 변환
                for photo_id in raw_delete:

                    try:
                        photo_id = int(
                            photo_id
                        )

                    except (
                            TypeError,
                            ValueError,
                    ):
                        continue

                    # 중복 ID 제거
                    if (
                            photo_id
                            not in delete_photo_ids
                    ):
                        delete_photo_ids.append(
                            photo_id
                        )

            except Exception as e:
                logger.warning(
                    "[PreventionRegistration update] "
                    f"delete_photos 파싱 실패: {e}"
                )

                return Response(
                    {
                        "error": (
                            "delete_photos 형식이 "
                            "올바르지 않습니다."
                        )
                    },
                    status=status.HTTP_400_BAD_REQUEST
                )

        # =========================================================
        # 6. DB 수정
        # =========================================================
        try:
            with transaction.atomic():

                # -------------------------------------------------
                # 6-1. 일반 필드 저장
                # -------------------------------------------------
                registration = serializer.save()

                # -------------------------------------------------
                # 6-2. 기존 사진 삭제
                #
                # 반드시 현재 registration 소속 사진만 삭제
                # 다른 예방등록 사진 ID가 넘어와도 삭제되지 않음
                # -------------------------------------------------
                if delete_photo_ids:
                    delete_qs = (
                        registration.photos.filter(
                            id__in=delete_photo_ids
                        )
                    )

                    logger.info(
                        "[PreventionRegistration update] "
                        "사진 삭제 | registration_id=%s | ids=%s",
                        registration.id,
                        list(
                            delete_qs.values_list(
                                "id",
                                flat=True
                            )
                        ),
                    )

                    delete_qs.delete()

                # -------------------------------------------------
                # 6-3. 새 사진 저장 / 같은 타입 교체
                #
                # 프론트에서:
                #
                # face_photo
                # full_body_photo
                # left_side_photo
                # right_side_photo
                # parent1_face_photo
                # parent2_face_photo
                #
                # 형식으로 전송
                #
                # replace=True:
                # 새로 들어온 photo_type에 대해서만
                # 기존 동일 타입 사진을 교체
                # -------------------------------------------------
                if request.FILES:
                    self._save_uploaded_photos(
                        registration=registration,
                        files=request.FILES,
                        validation_results=(
                            validation_results
                        ),
                        replace=True
                    )

                # -------------------------------------------------
                # 6-4. 로그 저장
                # -------------------------------------------------
                Log.objects.create(
                    user=user_person,
                    action="실종 예방 등록 수정",
                    target_type=(
                        "PreventionRegistration"
                    ),
                    target_id=registration.id,
                )

        except Exception as e:
            logger.exception(
                "[PreventionRegistration update] "
                "수정 실패 | registration_id=%s | error=%s",
                registration.id,
                e,
            )

            return Response(
                {
                    "error": "실종 예방 등록 수정 중 오류가 발생했습니다.",
                    "detail": str(e),
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

        # =========================================================
        # 7. 최신 DB 데이터 다시 조회
        #
        # 사진 삭제/추가 직후라 기존 related cache가 남는 것 방지
        # =========================================================
        registration.refresh_from_db()

        # prefetch cache가 존재하는 경우 제거
        if hasattr(
                registration,
                "_prefetched_objects_cache"
        ):
            registration._prefetched_objects_cache = {}

        # =========================================================
        # 8. 응답
        # =========================================================
        return Response(
            self._build_detail_item(
                request,
                registration
            ),
            status=status.HTTP_200_OK
        )
    def partial_update(self, request, *args, **kwargs):
        """
        PATCH 요청 처리
        """
        kwargs["partial"] = True
        return self.update(request, *args, **kwargs)

    # -------------------------------------------------
    # 사용자 비활성화
    # -------------------------------------------------
    @action(detail=True, methods=["patch"], url_path="deactivate")
    def deactivate(self, request, pk=None):
        """
        사용자가 본인 예방등록을 비활성화한다.
        일반 회원은 received 상태에서만 가능.
        관리자는 모든 상태 가능.
        """

        registration = self.get_object()

        is_admin = self._is_admin(request)
        is_owner = registration.owner == request.user.person

        if not (is_admin or is_owner):
            return Response(
                {"error": "본인 또는 관리자만 비활성화할 수 있습니다."},
                status=status.HTTP_403_FORBIDDEN
            )

        if not is_admin and registration.status != PreventionRegistration.Status.RECEIVED:
            return Response(
                {"error": "접수중(received) 상태인 경우만 본인이 삭제할 수 있습니다."},
                status=status.HTTP_400_BAD_REQUEST
            )

        registration.is_active = False
        registration.save(update_fields=["is_active"])

        Log.objects.create(
            user=getattr(request.user, "person", None),
            action="실종 예방 등록 비활성화",
            target_type="PreventionRegistration",
            target_id=registration.id,
        )

        return Response({
            "message": "실종 예방 등록이 비활성화되었습니다.",
            "id": registration.id,
            "status": registration.status,
            "status_label": self._status_label(registration.status),
            "is_active": registration.is_active,
        })

    # -------------------------------------------------
    # 관리자 전체 목록
    # -------------------------------------------------
    @action(detail=False, methods=["get"], url_path="admin", permission_classes=[IsAdmin])
    def admin(self, request):
        """
        GET /dasibom/prevention-registrations/admin/

        관리자용 예방등록 목록 조회

        Query Params:
        - status: received | reviewing | completed | rejected
        - keyword: 대상자 이름 / 보호자 이름 / 전화번호 / 주소 검색
        - is_active: true | false
        """

        qs = (
            PreventionRegistration.objects
            .select_related("owner", "reviewed_by")
            .prefetch_related("photos")
            .all()
            .order_by("-created_at")
        )

        status_param = request.GET.get("status")
        if status_param:
            qs = qs.filter(status=status_param)

        keyword = request.GET.get("keyword")
        if keyword:
            qs = qs.filter(
                Q(name__icontains=keyword)
                | Q(guardian_name__icontains=keyword)
                | Q(guardian_phone__icontains=keyword)
                | Q(phone__icontains=keyword)
                | Q(address__icontains=keyword)
            )

        is_active_param = request.GET.get("is_active")
        if is_active_param is not None:
            if str(is_active_param).lower() == "true":
                qs = qs.filter(is_active=True)
            elif str(is_active_param).lower() == "false":
                qs = qs.filter(is_active=False)

        data = [
            self._build_list_item(request, registration)
            for registration in qs
        ]

        return Response(data, status=status.HTTP_200_OK)

    # -------------------------------------------------
    # 관리자 상태 변경
    # -------------------------------------------------
    @action(detail=True, methods=["patch"], url_path="admin-status", permission_classes=[IsAdmin])
    def admin_status(self, request, pk=None):
        """
        PATCH /dasibom/prevention-registrations/{id}/admin-status/

        상태 전환:
        received  -> reviewing / rejected
        reviewing -> completed / rejected
        completed -> reviewing
        rejected  -> reviewing

        completed 전환 시:
        - Person 피보호자 생성/연결
        - Guardian 관계 생성
        - Device 연결
        """

        registration = get_object_or_404(PreventionRegistration, pk=pk)

        new_status = request.data.get("status")
        rejected_reason = request.data.get("rejected_reason")

        allowed_statuses = [
            PreventionRegistration.Status.RECEIVED,
            PreventionRegistration.Status.REVIEWING,
            PreventionRegistration.Status.COMPLETED,
            PreventionRegistration.Status.REJECTED,
        ]

        allowed_transitions = {
            PreventionRegistration.Status.RECEIVED: [
                PreventionRegistration.Status.REVIEWING,
                PreventionRegistration.Status.REJECTED,
            ],
            PreventionRegistration.Status.REVIEWING: [
                PreventionRegistration.Status.COMPLETED,
                PreventionRegistration.Status.REJECTED,
            ],
            PreventionRegistration.Status.COMPLETED: [
                PreventionRegistration.Status.REVIEWING,
            ],
            PreventionRegistration.Status.REJECTED: [
                PreventionRegistration.Status.REVIEWING,
            ],
        }

        if not new_status:
            return Response({"error": "status 값이 필요합니다."}, status=400)

        if new_status not in allowed_statuses:
            return Response({
                "error": "유효하지 않은 상태값입니다.",
                "allowed": allowed_statuses,
            }, status=400)

        current_status = registration.status

        if current_status == new_status:
            return Response({"error": f"이미 '{new_status}' 상태입니다."}, status=400)

        if current_status not in allowed_transitions:
            return Response({"error": f"현재 상태값이 올바르지 않습니다: {current_status}"}, status=400)

        if new_status not in allowed_transitions[current_status]:
            return Response({
                "error": "허용되지 않은 상태 전환입니다.",
                "current_status": current_status,
                "allowed_next": allowed_transitions[current_status],
            }, status=400)

        linked_person_id = None
        linked_person_name = None
        device_code = None
        device_connected = False
        guardian_created = False

        with transaction.atomic():
            registration.status = new_status
            registration.reviewed_by = getattr(request.user, "person", None)
            registration.reviewed_at = timezone.now()

            if new_status == PreventionRegistration.Status.REJECTED:
                registration.rejected_reason = rejected_reason or "관리자에 의해 거절되었습니다."

            if current_status == PreventionRegistration.Status.REJECTED and new_status == PreventionRegistration.Status.REVIEWING:
                registration.rejected_reason = None

            if new_status == PreventionRegistration.Status.COMPLETED:
                print("🔥 예방등록 completed 분기 진입")
                print("registration.id:", registration.id)
                print("registration.name:", registration.name)
                print("registration.owner:", registration.owner)

                person = getattr(registration, "linked_person", None)

                if person is None:
                    sex = Person.Sex.UNKNOWN

                    if registration.gender == "남자":
                        sex = Person.Sex.MALE
                    elif registration.gender == "여자":
                        sex = Person.Sex.FEMALE

                    person = Person.objects.create(
                        name=registration.name,
                        sex=sex,
                        phone=registration.phone,
                        address=registration.address,
                        health_info=registration.health_info,
                    )

                    registration.linked_person = person

                linked_person_id = person.id
                linked_person_name = person.name

                guardian, guardian_created = Guardian.objects.get_or_create(
                    guardian=registration.owner,
                    ward=person,
                    defaults={"relation": "피보호자"}
                )
                owner_user = UserAuth.objects.filter(
                    person=registration.owner
                ).first()

                if owner_user and owner_user.role != UserAuth.Role.ADMIN:
                    owner_user.role = UserAuth.Role.GUARDIAN
                    owner_user.save(update_fields=["role"])
                # ---------------------------------------------
                # 예방등록 완료 시 배지 자동 발급
                # ---------------------------------------------
                if registration.device_code:
                    # 이미 발급된 배지가 있으면 기존 번호 유지
                    device_code = registration.device_code

                else:
                    # 처음 완료되는 경우 다음 배지 번호 자동 생성
                    device_code = self._generate_next_device_code()
                    registration.device_code = device_code

                Device.objects.update_or_create(
                    device_uid=device_code,
                    defaults={
                        "person": person,
                        "status": Device.Status.ACTIVE,
                    }
                )

                device_connected = True

            registration.save()

            Log.objects.create(
                user=getattr(request.user, "person", None),
                action=f"실종 예방 등록 상태 변경: {current_status} → {new_status}",
                target_type="PreventionRegistration",
                target_id=registration.id,
            )

        return Response({
            "message": "상태 변경 완료",
            "id": registration.id,
            "old_status": current_status,
            "new_status": registration.status,
            "status_label": self._status_label(registration.status),
            "rejected_reason": registration.rejected_reason,
            "reviewed_by": registration.reviewed_by.id if registration.reviewed_by else None,
            "reviewed_by_name": registration.reviewed_by.name if registration.reviewed_by else None,
            "reviewed_at": self._format_datetime_for_front(registration.reviewed_at),

            "linked_person_id": linked_person_id,
            "linked_person_name": linked_person_name,
            "guardian_created": guardian_created,
            "device_code": device_code,
            "device_connected": device_connected,
        }, status=200)
        #-------------------------------------------------
    # 관리자 삭제
    # -------------------------------------------------
    @action(detail=True, methods=["delete"], url_path="delete", permission_classes=[IsAdmin])
    def delete_registration(self, request, pk=None):
        """
        DELETE /dasibom/prevention-registrations/{id}/delete/
        관리자 전용 하드 삭제
        """

        registration = get_object_or_404(PreventionRegistration, pk=pk)
        registration_id = registration.id

        registration.delete()

        Log.objects.create(
            user=getattr(request.user, "person", None),
            action="실종 예방 등록 삭제",
            target_type="PreventionRegistration",
            target_id=registration_id,
        )

        return Response(
            {
                "message": "실종 예방 등록 삭제 완료",
                "id": registration_id,
            },
            status=status.HTTP_200_OK
        )
class EmergencyReportAPIView(APIView):
    """
    긴급신고 API

    POST /dasibom/emergency/
    """

    permission_classes = [AllowAny]

    def post(self, request):
        serializer = EmergencyReportSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        device_code = serializer.validated_data["device_code"]
        reported_at = serializer.validated_data.get("timestamp") or timezone.now()

        # 하드에서 보내는 device_code 값을 Device.device_uid와 매칭
        device = Device.objects.filter(device_uid=device_code).first()

        emergency = EmergencyReport.objects.create(
            device=device,
            device_code=device_code,
            reported_at=reported_at,
        )

        log = Log.objects.create(
            user=None,
            action=f"긴급신고 접수: {device_code}",
            target_type="EmergencyReport",
            target_id=emergency.id,
        )

        # Log 모델 시간 필드 처리
        log_time = getattr(log, "timestamp", None) or timezone.now()

        # WebSocket 실시간 알림 전송 데이터
        emergency_log_data = {
            "id": log.id,
            "timestamp": timezone.localtime(log_time).isoformat(),
            "actionType": "emergencyReceived",
            "targetName": emergency.device_code,
            "caseId": f"EMG-{emergency.id:03d}",
            "fromStatus": None,
            "toStatus": None,
            "adminName": "시스템",
            "rawAction": log.action,
            "targetType": "EmergencyReport",
            "targetId": emergency.id,

            # 프론트 호환용: 기존 deviceId도 유지하고, 새 deviceCode도 같이 내려줌
            "deviceId": emergency.device_code,
            "deviceCode": emergency.device_code,

            "reportedAt": timezone.localtime(emergency.reported_at).isoformat()
            if emergency.reported_at else None,
        }

        # WebSocket 실시간 알림 전송
        try:
            channel_layer = get_channel_layer()

            async_to_sync(channel_layer.group_send)(
                "emergency_alerts",
                {
                    "type": "emergency.message",
                    "message": "긴급신고가 접수되었습니다.",
                    "data": emergency_log_data,
                }
            )

        except Exception as e:
            logger.warning(f"긴급신고 WebSocket 전송 실패 device_code={device_code}: {e}")

        return Response(
            {
                "status": "success",
                "message": "긴급신고가 접수되었습니다.",
                "device_code": device_code,
                "emergency_id": emergency.id,
            },
            status=status.HTTP_201_CREATED
        )
class DeviceLocationAPIView(APIView):
    """
    현재위치공유 API

    POST /dasibom/location/
    """

    permission_classes = [AllowAny]

    def post(self, request):
        print("========== [DeviceLocationAPIView 호출됨] ==========")
        print("method:", request.method)
        print("path:", request.path)
        print("content_type:", request.content_type)
        print("data:", request.data)
        print("===================================================")

        serializer = DeviceLocationLogSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        device_code = serializer.validated_data["device_code"]
        lat = serializer.validated_data["lat"]
        lng = serializer.validated_data["lng"]
        shared_at = serializer.validated_data.get("timestamp") or timezone.now()

        # 1. 기기 조회
        device = Device.objects.filter(device_uid=device_code).select_related("person").first()

        # 2. 위치 로그 저장
        location_log = DeviceLocationLog.objects.create(
            device=device,
            device_code=device_code,
            lat=lat,
            lng=lng,
            shared_at=shared_at,
        )

        # 3. 피보호자 / 보호자 정보 찾기
        ward = device.person if device else None
        ward_name = ward.name if ward else None

        guardian_relation = None
        guardian_name = None

        if ward:
            guardian_relation = Guardian.objects.filter(
                ward=ward
            ).select_related("guardian").first()

            if guardian_relation and guardian_relation.guardian:
                guardian_name = guardian_relation.guardian.name

        # 4. 관리자 로그 메시지 생성
        if ward_name and guardian_name:
            action_message = (
                f"현재위치공유 수신: {device_code} 키오스크에서 "
                f"{ward_name}님의 위치를 {guardian_name} 보호자에게 전송"
            )
        elif ward_name:
            action_message = (
                f"현재위치공유 수신: {device_code} 키오스크에서 "
                f"{ward_name}님의 위치를 보호자에게 전송"
            )
        else:
            action_message = (
                f"현재위치공유 수신: {device_code} 키오스크에서 보호자에게 위치 전송"
            )

        # 5. 관리자 로그 저장
        Log.objects.create(
            user=None,
            action=action_message,
            target_type="DeviceLocationLog",
            target_id=location_log.id,
        )

        return Response(
            {
                "status": "success",
                "message": "위치가 공유되었습니다.",
                "device_code": device_code,
                "lat": lat,
                "lng": lng,
                "shared_at": timezone.localtime(shared_at).isoformat()
                if shared_at else None,
                "ward_name": ward_name,
                "guardian_name": guardian_name,
            },
            status=status.HTTP_201_CREATED
        )
class GPSLocationAPIView(APIView):
    """
    ESP32 GPS 좌표 저장 API

    POST /dasibom/gps/

    device_code별 최신 GPS 좌표 1개만 저장하고,
    저장 직후 WebSocket으로 보호자 페이지에 실시간 위치를 전송한다.
    """

    permission_classes = [AllowAny]

    def post(self, request):
        print("========== [GPSLocationAPIView POST 호출됨] ==========")
        print("method:", request.method)
        print("path:", request.path)
        print("content_type:", request.content_type)
        print("data:", request.data)
        print("====================================================")

        serializer = GPSLocationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        device_code = serializer.validated_data["device_code"]
        lat = serializer.validated_data["lat"]
        lng = serializer.validated_data["lng"]
        measured_at = serializer.validated_data.get("timestamp") or timezone.now()

        device = Device.objects.filter(device_uid=device_code).first()

        gps, created = GPSLocation.objects.update_or_create(
            device_code=device_code,
            defaults={
                "device": device,
                "lat": lat,
                "lng": lng,
                "timestamp": measured_at,
            }
        )
        # =====================================================
        # 기기별 GPS 위치 이력 저장
        # - 최초 GPS는 바로 저장
        # - 이후 해당 device_code의 마지막 기록으로부터
        #   2시간 이상 지났을 때만 새 로그 생성
        # =====================================================

        last_history = (
            GPSLocationHistory.objects
            .filter(device_code=device_code)
            .order_by("-timestamp")
            .first()
        )

        should_save_history = False

        if last_history is None:
            should_save_history = True

        elif measured_at >= last_history.timestamp + timedelta(hours=2):
            should_save_history = True

        if should_save_history:
            history = GPSLocationHistory.objects.create(
                device=device,
                device_code=device_code,
                lat=lat,
                lng=lng,
                timestamp=measured_at,
            )

            print(
                f"[GPS HISTORY 저장] "
                f"id={history.id} "
                f"device={device_code} "
                f"time={history.timestamp}",
                flush=True,
            )
        timestamp = gps.timestamp.isoformat()
        if timestamp.endswith("+00:00"):
            timestamp = timestamp.replace("+00:00", "Z")

        gps_data = {
            "device_code": gps.device_code,
            "lat": gps.lat,
            "lng": gps.lng,
            "timestamp": timestamp,
        }

        print("GPS 저장 완료")
        print("created:", created)
        print("device_code:", gps.device_code)
        print("lat:", gps.lat)
        print("lng:", gps.lng)

        # WebSocket 실시간 위치 전송
        try:
            channel_layer = get_channel_layer()

            async_to_sync(channel_layer.group_send)(
                f"gps_location_{device_code}",
                {
                    "type": "gps.location",
                    "message": "GPS 위치가 갱신되었습니다.",
                    "data": gps_data,
                }
            )

            print("GPS WebSocket 전송 완료")
            print("group:", f"gps_location_{device_code}")

        except Exception as e:
            print("GPS WebSocket 전송 실패:", e)
            logger.warning(f"GPS WebSocket 전송 실패 device_code={device_code}: {e}")

        return Response(
            {
                "status": "success",
                "message": "GPS 데이터가 저장되었습니다.",
                "data": gps_data,
            },
            status=status.HTTP_201_CREATED
        )
class GPSLatestAPIView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        badge_uid = request.query_params.get("badge_uid")
        device_code = request.query_params.get("device_code")

        # -------------------------------------------------
        # badge_uid가 들어온 경우 Device → device_code 변환
        # -------------------------------------------------
        if badge_uid:
            uid = (
                str(badge_uid)
                .strip()
                .lower()
                .replace(":", "")
                .replace("-", "")
            )

            device = Device.objects.filter(
                badge_uid=uid
            ).first()

            if device is None:
                return Response(
                    {
                        "status": "error",
                        "message": "등록되지 않은 뱃지입니다."
                    },
                    status=status.HTTP_404_NOT_FOUND
                )

            device_code = device.device_uid

        # -------------------------------------------------
        # badge_uid / device_code 둘 다 없는 경우
        # -------------------------------------------------
        if not device_code:
            return Response(
                {
                    "status": "error",
                    "message": "device_code 또는 badge_uid 가 필요합니다."
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        # -------------------------------------------------
        # 해당 기기의 최신 GPS 조회
        # -------------------------------------------------
        gps = GPSLocation.objects.filter(
            device_code=device_code
        ).first()

        if not gps:
            return Response(
                {
                    "status": "error",
                    "message": "GPS 데이터가 없습니다."
                },
                status=status.HTTP_404_NOT_FOUND
            )

        # -------------------------------------------------
        # 기존 UTC timestamp 응답 유지
        # -------------------------------------------------
        timestamp = gps.timestamp.isoformat()

        if timestamp.endswith("+00:00"):
            timestamp = timestamp.replace(
                "+00:00",
                "Z"
            )

        return Response(
            {
                "device_code": gps.device_code,
                "lat": gps.lat,
                "lng": gps.lng,
                "timestamp": timestamp
            },
            status=status.HTTP_200_OK
        )
class GPSHistoryAPIView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        guardian_person = request.user.person

        # 로그인 보호자에게 연결된 피보호자
        ward_ids = Guardian.objects.filter(
            guardian=guardian_person
        ).values_list(
            "ward_id",
            flat=True
        )

        # 피보호자에게 연결된 Device
        devices = Device.objects.filter(
            person_id__in=ward_ids
        ).select_related("person")

        device_map = {
            device.device_uid: device
            for device in devices
        }

        if not device_map:
            return Response([])

        histories = (
            GPSLocationHistory.objects
            .filter(
                device_code__in=device_map.keys()
            )
            .order_by("-timestamp")
        )

        result = []

        for history in histories:
            device = device_map.get(
                history.device_code
            )

            ward = (
                device.person
                if device
                else None
            )

            result.append({
                "id": history.id,
                "device_code": history.device_code,

                "ward_id": (
                    ward.id
                    if ward
                    else None
                ),

                "ward_name": (
                    ward.name
                    if ward
                    else None
                ),

                "lat": history.lat,
                "lng": history.lng,

                "timestamp": (
                    timezone.localtime(
                        history.timestamp
                    ).isoformat()
                    if history.timestamp
                    else None
                ),
            })

        return Response(result)
class NotificationListAPIView(APIView):
    """
    일반 회원 / 보호자 알림 목록 조회 API

    GET /dasibom/notifications/

    프론트 NotificationPage에 맞춘 응답 구조:
    [
        {
            "id": "case-101",
            "type": "missing_report" | "citizen_tip" | "prevention",
            "notification_type": "...",
            "target_type": "Case" | "PreventionRegistration",
            "target_id": 1,
            "title": "실종 신고 알림",
            "message": "홍길동님의 실종 신고 상태가 확인중(으)로 변경되었습니다.",
            "content": "...",
            "body": "...",
            "is_read": false,
            "created_at": "2026-06-02T12:00:00+09:00",
            "timestamp": "2026-06-02T12:00:00+09:00"
        }
    ]

    포함 알림:
    - 내가 등록한 제보/신고 접수 완료
    - 내가 등록한 제보/신고 상태 변경
    - 내가 등록한 실종 예방 등록 접수 완료
    - 내가 등록한 실종 예방 등록 상태 변경
    - 거절 사유가 있는 경우 message에 포함
    - 비활성화/삭제처럼 사용자 데이터에 영향 있는 이벤트

    제외 알림:
    - 관리자 단순 조회
    - 내부 로그성 수정 기록
    - 관리자 전용 처리 이력

    보호자 위치 로그는 프론트에서 별도 API인
    GET /dasibom/guardian/tag-logs/
    를 이미 호출하므로 여기서는 내려주지 않는다.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        person = getattr(request.user, "person", None)

        if not person:
            return Response([], status=status.HTTP_200_OK)

        STATUS_LABEL = {
            "received": "접수중",
            "reviewing": "확인중",
            "completed": "완료",
            "rejected": "거절",
            "missing": "실종",
            "found": "발견",
        }

        def format_time(dt):
            if not dt:
                return None

            try:
                return timezone.localtime(dt).isoformat()
            except Exception:
                return None

        def get_status_label(value):
            if not value:
                return ""

            value = str(value).strip()
            return STATUS_LABEL.get(value, value)

        def parse_status_change(action):
            """
            예:
            '제보/신고 상태 변경: received → reviewing'
            '실종 예방 등록 상태 변경: reviewing → completed'
            """
            if not action or "→" not in action:
                return None, None

            try:
                status_part = action.split(":")[-1].strip()
                from_status, to_status = status_part.split("→")
                return from_status.strip(), to_status.strip()
            except Exception:
                return None, None

        def normalize_action(action):
            return str(action or "").strip()

        def is_user_visible_action(action):
            """
            사용자 알림에 보여줄 로그만 통과.
            내부 수정/조회성 로그는 제외.
            """
            action = normalize_action(action)

            visible_keywords = [
                "생성",
                "접수",
                "상태 변경",
                "삭제",
                "비활성화",
            ]

            hidden_keywords = [
                "조회",
                "상세 조회",
                "관리자 조회",
                "수정",
                "AI 몽타주",
                "몽타주",
            ]

            if any(keyword in action for keyword in hidden_keywords):
                # 단, 비활성화/삭제/상태 변경은 사용자 영향 이벤트라 유지
                if not any(keyword in action for keyword in ["상태 변경", "삭제", "비활성화"]):
                    return False

            return any(keyword in action for keyword in visible_keywords)

        def build_case_notification(log, case):
            action = normalize_action(log.action)
            payload = case.payload or {}

            if not is_user_visible_action(action):
                return None

            if case.type_code == Case.TypeCode.TIP:
                noti_type = "citizen_tip"
                title = "시민 제보 알림"
                label = "시민 제보"
            elif case.type_code == Case.TypeCode.MISSING:
                noti_type = "missing_report"
                title = "실종 신고 알림"
                label = "실종 신고"
            else:
                return None

            target_name = (
                case.reported_missing_name
                or payload.get("name")
                or payload.get("missing_name")
                or payload.get("reported_missing_name")
                or "대상자"
            )

            raw_from, raw_to = parse_status_change(action)
            current_status = raw_to or case.status
            current_status_label = get_status_label(current_status)

            rejected_reason = (
                payload.get("rejected_reason")
                or payload.get("reject_reason")
                or getattr(case, "rejected_reason", None)
                or ""
            )

            if "생성" in action or "접수" in action:
                message = f"{target_name}님의 {label}가 정상 접수되었습니다."

            elif "상태 변경" in action:
                message = f"{target_name}님의 {label} 상태가 {current_status_label}(으)로 변경되었습니다."

                if current_status == Case.Status.REJECTED and rejected_reason:
                    message += f" 거절 사유: {rejected_reason}"

            elif "삭제" in action:
                message = f"{target_name}님의 {label}가 삭제되었습니다."

            else:
                return None

            created_at = format_time(log.timestamp)

            return {
                "id": f"case-{log.id}",
                "log_id": log.id,

                # 프론트가 읽는 핵심 필드
                "type": noti_type,
                "notification_type": noti_type,
                "target_type": "Case",
                "target_id": case.id,
                "case_id": case.id,

                "title": title,
                "message": message,
                "content": message,
                "body": message,

                # 프론트 fallback용 부가 필드
                "target_name": target_name,
                "name": target_name,
                "reported_missing_name": case.reported_missing_name,

                "status": current_status,
                "status_label": current_status_label,
                "from_status": raw_from,
                "from_status_label": get_status_label(raw_from),
                "to_status": raw_to,
                "to_status_label": get_status_label(raw_to),

                "rejected_reason": rejected_reason,

                "is_read": False,
                "created_at": created_at,
                "timestamp": created_at,
            }

        def build_prevention_notification(log, registration):
            action = normalize_action(log.action)

            if not is_user_visible_action(action):
                return None

            target_name = registration.name or "예방등록 대상자"

            raw_from, raw_to = parse_status_change(action)
            current_status = raw_to or registration.status
            current_status_label = get_status_label(current_status)

            rejected_reason = registration.rejected_reason or ""

            title = "사전예방등록 알림"
            noti_type = "prevention"

            if "생성" in action or "접수" in action:
                message = f"{target_name}님의 사전예방등록이 접수되었습니다."

            elif "상태 변경" in action:
                message = f"{target_name}님의 사전예방등록 상태가 {current_status_label}(으)로 변경되었습니다."

                if current_status == PreventionRegistration.Status.REJECTED and rejected_reason:
                    message += f" 거절 사유: {rejected_reason}"

            elif "비활성화" in action:
                message = f"{target_name}님의 사전예방등록이 비활성화되었습니다."

            elif "삭제" in action:
                message = f"{target_name}님의 사전예방등록이 삭제되었습니다."

            else:
                return None

            created_at = format_time(log.timestamp)

            return {
                "id": f"prevention-{log.id}",
                "log_id": log.id,

                # 프론트가 읽는 핵심 필드
                "type": noti_type,
                "notification_type": noti_type,
                "target_type": "PreventionRegistration",
                "target_id": registration.id,
                "registration_id": registration.id,

                "title": title,
                "message": message,
                "content": message,
                "body": message,

                # 프론트 fallback용 부가 필드
                "target_name": target_name,
                "name": target_name,

                "status": current_status,
                "status_label": current_status_label,
                "from_status": raw_from,
                "from_status_label": get_status_label(raw_from),
                "to_status": raw_to,
                "to_status_label": get_status_label(raw_to),

                "rejected_reason": rejected_reason,

                "is_read": False,
                "created_at": created_at,
                "timestamp": created_at,
            }

        results = []

        # =================================================
        # 1. 내가 등록한 제보/신고 알림
        # =================================================
        my_cases = (
            Case.objects
            .filter(reporter=person)
            .select_related("reporter", "missing_person")
            .prefetch_related("photos", "features")
        )

        my_case_map = {
            case.id: case
            for case in my_cases
        }

        my_case_ids = list(my_case_map.keys())

        if my_case_ids:
            case_logs = (
                Log.objects
                .filter(
                    target_type="Case",
                    target_id__in=my_case_ids
                )
                .filter(
                    Q(action__icontains="생성")
                    | Q(action__icontains="접수")
                    | Q(action__icontains="상태 변경")
                    | Q(action__icontains="삭제")
                )
                .order_by("-timestamp")
            )

            for log in case_logs:
                case = my_case_map.get(log.target_id)

                if not case:
                    continue

                item = build_case_notification(log, case)

                if item:
                    results.append(item)

        # =================================================
        # 2. 내가 등록한 실종 예방 등록 알림
        # =================================================
        my_registrations = (
            PreventionRegistration.objects
            .filter(owner=person)
            .select_related("owner", "reviewed_by")
        )

        my_registration_map = {
            registration.id: registration
            for registration in my_registrations
        }

        my_registration_ids = list(my_registration_map.keys())

        if my_registration_ids:
            prevention_logs = (
                Log.objects
                .filter(
                    target_type="PreventionRegistration",
                    target_id__in=my_registration_ids
                )
                .filter(
                    Q(action__icontains="생성")
                    | Q(action__icontains="접수")
                    | Q(action__icontains="상태 변경")
                    | Q(action__icontains="삭제")
                    | Q(action__icontains="비활성화")
                )
                .order_by("-timestamp")
            )

            for log in prevention_logs:
                registration = my_registration_map.get(log.target_id)

                if not registration:
                    continue

                item = build_prevention_notification(log, registration)

                if item:
                    results.append(item)

        # =================================================
        # 3. 최신순 정렬 + 100개 제한
        # =================================================
        unique = {}

        for item in results:
            unique[item["id"]] = item

        results = list(unique.values())

        results.sort(
            key=lambda item: item.get("timestamp") or "",
            reverse=True
        )

        return Response(results[:100], status=status.HTTP_200_OK)
class GuardianTagLogAPIView(APIView):
    """
    보호자 피보호자 위치 로그 조회 API

    GET /dasibom/guardian/tag-logs/

    보호자가 본인의 피보호자 NFC/태그 위치 로그를 조회한다.
    NotificationPage의 '위치 로그' 탭에서 사용.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        person = getattr(request.user, "person", None)

        if not person:
            return Response([], status=status.HTTP_200_OK)

        # 보호자 또는 관리자만 허용
        user_role = getattr(request.user, "role", None)

        if user_role not in ["guardian", "admin"]:
            return Response(
                {"error": "보호자만 위치 로그를 조회할 수 있습니다."},
                status=status.HTTP_403_FORBIDDEN
            )

        # -------------------------------------------------
        # 1. 보호자가 관리하는 피보호자 목록 조회
        # -------------------------------------------------
        if user_role == "admin":
            ward_ids = list(Person.objects.values_list("id", flat=True))
        else:
            guardians = Guardian.objects.filter(
                guardian=person
            ).select_related("ward")

            ward_ids = [
                g.ward_id
                for g in guardians
                if g.ward_id
            ]

        if not ward_ids:
            return Response([], status=status.HTTP_200_OK)

        # -------------------------------------------------
        # 2. NFC 태그 Interaction 로그 조회
        # -------------------------------------------------
        logs = (
            Interaction.objects
            .filter(
                to_person_id__in=ward_ids,
                type="nfc_tag"
            )
            .select_related("to_person")
            .order_by("-start_time")[:100]
        )

        results = []

        for log in logs:
            ward = log.to_person

            # 피보호자에 연결된 기기 조회
            device = Device.objects.filter(person=ward).first()

            device_code = None
            latest_gps = None

            if device:
                device_code = getattr(device, "device_uid", None)

                if device_code:
                    latest_gps = GPSLocation.objects.filter(
                        device_code=device_code
                    ).first()

            tagged_at = log.start_time or timezone.now()

            lat = latest_gps.lat if latest_gps else None
            lng = latest_gps.lng if latest_gps else None

            location_text = log.location or ""

            if not location_text and lat is not None and lng is not None:
                location_text = f"{lat}, {lng}"

            results.append({
                "id": log.id,

                # 프론트 title 후보
                "protected_name": ward.name if ward else "피보호자",
                "protected_person_name": ward.name if ward else "피보호자",
                "name": ward.name if ward else "피보호자",

                # 프론트 위치 후보
                "address": location_text,
                "location": location_text,
                "lat": lat,
                "lng": lng,

                # 기기/태그 정보
                "device_id": device_code or "",
                "device_code": device_code or "",
                "badge_id": "",

                # 시간 후보
                "tagged_at": format_datetime_for_front(tagged_at),
                "created_at": format_datetime_for_front(tagged_at),
                "timestamp": format_datetime_for_front(tagged_at),
            })

        return Response(results, status=status.HTTP_200_OK)