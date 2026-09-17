from rest_framework import serializers
from .models import *
import re
from django.utils.dateparse import parse_datetime
from django.utils import timezone
from dasibomapp.storage import media_url
from dasibomapp.services.risk_engine import categorize_missing_person
# ==========================================================
# serializers.py
# 연결된 views:
#   - PersonViewSet         → PersonSerializer
#   - UserAuthViewSet       → UserAuthSerializer
#   - GuardianViewSet       → GuardianSerializer
#   - CaseViewSet           → CaseSerializer, TipListSerializer, AdminTipSerializer
#   - ReportViewSet         → CitizenTipSerializer, RegisterMissingSerializer
#   - MissingPersonViewSet  → MissingPersonSerializer, MissingPersonListSerializer, MissingPersonCardSerializer
#   - ProtectedPersonViewSet→ ProtectedPersonCardSerializer, ProtectedPersonListSerializer, ProtectedPersonDetailSerializer
#   - AdminUserViewSet      → AdminUserSerializer
#   - LogViewSet            → LogSerializer
# ==========================================================
def split_feature_text(text):
    """
    etc_spfeatr처럼 여러 특징이 한 문장에 섞여 들어온 경우
    쉼표, 마침표, 줄바꿈 기준으로 나누는 전처리 함수.
    """
    if not text:
        return []

    parts = re.split(r"[,，.\n\r]+", text)

    return [part.strip() for part in parts if part.strip()]


def rule_based_category(text):
    """
    잘린 문장 조각을 키워드 기반으로 1차 분류한다.
    AI가 긴 복합문장을 하나의 카테고리로만 분류하는 문제를 보완하기 위한 로직.
    """
    if not text:
        return None

    physical_keywords = [
        "흉터", "점", "문신", "상처", "수술자국", "화상",
        "얼굴", "코", "입", "눈", "귀", "볼", "턱", "이마",
        "팔", "다리", "손", "발", "목",
        "키", "몸무게", "체격", "마름", "통통", "왜소", "건장"
    ]

    clothing_keywords = [
        "티", "티셔츠", "후드", "후드티", "반팔", "긴팔",
        "바지", "청바지", "치마", "원피스",
        "점퍼", "패딩", "코트", "자켓", "재킷",
        "운동화", "신발", "구두", "슬리퍼",
        "모자", "가방", "안경", "무테안경",
        "머리", "긴머리", "단발", "커트", "염색", "흑발", "백발"
    ]

    health_keywords = [
        "장애", "치매", "질환", "병", "복용", "약",
        "인지", "발달", "지적", "자폐", "정신", "건강"
    ]

    behavior_keywords = [
        "배회", "혼자", "두리번", "불안", "반복",
        "울음", "도망", "따라감", "소리"
    ]

    # 신체 특징 우선
    if any(keyword in text for keyword in physical_keywords):
        return "신체특징"

    if any(keyword in text for keyword in clothing_keywords):
        return "착의외형"

    if any(keyword in text for keyword in health_keywords):
        return "건강장애"

    if any(keyword in text for keyword in behavior_keywords):
        return "행동특성"

    return None


def apply_feature_text_to_buckets(text, physical, clothing_info, health, behavior, extra):
    """
    긴 특징 문장을 조각별로 분리한 뒤 각 카테고리 리스트에 추가한다.
    """
    parts = split_feature_text(text)

    for part in parts:
        category = rule_based_category(part)

        if category == "신체특징":
            physical.append(part)
        elif category == "착의외형":
            clothing_info.append(part)
        elif category == "건강장애":
            health.append(part)
        elif category == "행동특성":
            behavior.append(part)
        else:
            extra.append(part)

    return physical, clothing_info, health, behavior, extra
# ✅ 상태 코드 → 라벨 (단일 소스)
MISSING_STATUS_MAP = {
    "010": "정상아동 (18세 미만)",
    "020": "가출인",
    "040": "시설 보호 무연고자",
    "060": "지적장애인",
    "061": "지적장애인 (18세 미만)",
    "062": "지적장애인 (18세 이상)",
    "070": "치매 질환자",
    "080": "불상 (기타)",
}
def split_request_value(value):
    """
    프론트에서 문자열 또는 리스트로 넘어온 값을
    카테고리 배열 형태로 통일한다.

    예:
    "코 옆에 점, 왼쪽 팔 흉터"
    -> ["코 옆에 점", "왼쪽 팔 흉터"]

    ["코 옆에 점", "왼쪽 팔 흉터"]
    -> 그대로 정리
    """
    if not value:
        return []

    if isinstance(value, list):
        return [
            str(item).strip()
            for item in value
            if str(item).strip()
        ]

    return [
        item.strip()
        for item in str(value).replace("\n", ",").split(",")
        if item.strip()
    ]


def append_unique(bucket, value):
    """
    같은 값이 중복으로 들어가지 않도록 추가한다.
    """
    if value and value not in bucket:
        bucket.append(value)


def build_missing_report_categories(payload):
    """
    실종 신고 payload를 프론트 화면 카테고리 구조로 변환한다.

    기본 필드:
    - height, weight, body_type, face_type → 신체 특징
    - category, health, health_info → 건강·장애 정보
    - hair_color, hair_style, clothing → 착의·외형 정보
    - behavior → 성격·행동 특성
    - etc → 기타 참고 사항

    description:
    - payload["description_ai_segments"]가 있으면 AI 분류 결과 우선 사용
    - 없으면 기존 rule_based_category fallback 사용
    """
    payload = payload or {}

    physical = []
    behavior = []
    health = []
    clothing = []
    extra = []

    def add_unique(bucket, value):
        if value and value not in bucket:
            bucket.append(value)

    # -------------------------------------------------
    # 1. 기본 신체 특징
    # -------------------------------------------------
    for item in split_request_value(payload.get("physical")):
        add_unique(physical, item)

    if payload.get("height"):
        add_unique(physical, f"키 {payload.get('height')}")

    if payload.get("weight"):
        add_unique(physical, f"몸무게 {payload.get('weight')}")

    if payload.get("body_type"):
        add_unique(physical, f"체격 {payload.get('body_type')}")

    if payload.get("face_type"):
        add_unique(physical, f"얼굴형 {payload.get('face_type')}")

    # -------------------------------------------------
    # 2. 명시적 행동 특성
    # -------------------------------------------------
    for item in split_request_value(payload.get("behavior")):
        add_unique(behavior, item)

    # -------------------------------------------------
    # 3. 건강·장애 정보
    # -------------------------------------------------
    for item in split_request_value(payload.get("health")):
        add_unique(health, item)

    if payload.get("category"):
        add_unique(health, payload.get("category"))

    for item in split_request_value(payload.get("health_info")):
        add_unique(health, item)

    # -------------------------------------------------
    # 4. 기본 착의·외형 정보
    # -------------------------------------------------
    if payload.get("hair_color"):
        add_unique(clothing, f"두발색상 {payload.get('hair_color')}")

    if payload.get("hair_style"):
        add_unique(clothing, f"두발형태 {payload.get('hair_style')}")

    if payload.get("clothing"):
        add_unique(clothing, payload.get("clothing"))

    # -------------------------------------------------
    # 5. 명시적 기타 참고 사항
    # -------------------------------------------------
    for item in split_request_value(payload.get("etc")):
        add_unique(extra, item)

    # -------------------------------------------------
    # 6. description AI 분류 결과 우선 반영
    # -------------------------------------------------
    ai_segments = payload.get("description_ai_segments") or []

    if ai_segments:
        for item in ai_segments:
            if not isinstance(item, dict):
                continue

            text = item.get("text")
            category = item.get("category")

            if not text:
                continue

            # AI 결과값 기준 매핑
            if category == "신체특징":
                add_unique(physical, text)

            elif category == "착의외형":
                add_unique(clothing, text)

            elif category == "건강장애":
                add_unique(health, text)

            elif category == "행동특성":
                add_unique(behavior, text)

            else:
                add_unique(extra, text)

    # -------------------------------------------------
    # 7. AI 결과가 없으면 fallback으로 룰 기반 분류
    # -------------------------------------------------
    else:
        description = payload.get("description")

        if description:
            parts = split_feature_text(description)

            for part in parts:
                category = rule_based_category(part)

                if category == "신체특징":
                    add_unique(physical, part)

                elif category == "착의외형":
                    add_unique(clothing, part)

                elif category == "건강장애":
                    add_unique(health, part)

                elif category == "행동특성":
                    add_unique(behavior, part)

                else:
                    add_unique(extra, part)

    return {
        "신체 특징": physical,
        "성격·행동 특성": behavior,
        "건강·장애 정보": health,
        "착의·외형 정보": clothing,
        "기타 참고 사항": extra,
    }
class PersonSerializer(serializers.ModelSerializer):
    class Meta:
        model = Person
        fields = "__all__"
class TipPhotoSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()

    class Meta:
        model = TipPhoto
        fields = [
            "id",
            "image",
            "image_url",
            "uploaded_at",
            "is_ai_generated",
        ]

    def get_image_url(self, obj):
        if not obj.image:
            return None

        return media_url(
            obj.image.name,
            self.context.get("request"),
        )
class UserAuthSerializer(serializers.ModelSerializer):
    person = PersonSerializer(read_only=True)

    class Meta:
        model = UserAuth
        fields = "__all__"


class GuardianSerializer(serializers.ModelSerializer):
    class Meta:
        model = Guardian
        fields = "__all__"


class DeviceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Device
        fields = "__all__"


class CaseSerializer(serializers.ModelSerializer):
    photos = serializers.SerializerMethodField()
    photo_items = serializers.SerializerMethodField()

    class Meta:
        model = Case
        fields = "__all__"

    def get_photos(self, obj):
        request = self.context.get("request")
        result = []

        for p in obj.photos.all():
            if not p.image:
                continue

            result.append(
                media_url(
                    p.image.name,
                    request,
                )
            )

        return result

    def get_photo_items(self, obj):
        request = self.context.get("request")
        result = []

        for p in obj.photos.all():
            if not p.image:
                continue

            image_url = media_url(
                p.image.name,
                request,
            )

            result.append({
                "id": p.id,
                "url": image_url,

                # 기존 프론트 호환용
                "image": p.image.name,

                "photo_type": p.photo_type,

                "is_ai_generated": p.is_ai_generated,
                "uploaded_at": (
                    timezone.localtime(
                        p.uploaded_at
                    ).isoformat()
                    if p.uploaded_at
                    else None
                ),
            })

        return result


class PhoneVerificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Person
        fields = "__all__"


class FeatureSerializer(serializers.ModelSerializer):
    class Meta:
        model = Feature
        fields = "__all__"


class MontageSerializer(serializers.ModelSerializer):
    class Meta:
        model = Montage
        fields = "__all__"


class InteractionSerializer(serializers.ModelSerializer):
    class Meta:
        model = Interaction
        fields = "__all__"


class LogSerializer(serializers.ModelSerializer):
    class Meta:
        model = Log
        fields = "__all__"

class CitizenTipSerializer(serializers.Serializer):
    # 🔗 연결용 선택
    missing_seq = serializers.CharField(required=False, allow_blank=True)
    missing_person_seq = serializers.CharField(required=False, allow_blank=True, allow_null=True)
    missing_person_id = serializers.IntegerField(required=False, allow_null=True)
    # 실종자 정보
    missing_name = serializers.CharField(required=True)

    gender = serializers.ChoiceField(
        choices=["male", "female", "unknown"],
        required=True
    )

    found_datetime = serializers.DateTimeField(required=True)
    found_location = serializers.CharField(required=True)

    physical = serializers.CharField(required=True)
    clothing = serializers.CharField(required=True)

    # 선택 특성 정보
    health = serializers.CharField(required=False, allow_blank=True)
    behavior = serializers.CharField(required=False, allow_blank=True)
    etc = serializers.CharField(required=False, allow_blank=True)

    # 신고자 정보
    # 로그인 사용자는 자동으로 user.person 정보 사용
    # 비회원은 view에서 직접 필수 검증
    reporter_name = serializers.CharField(required=False, allow_blank=True)
    reporter_phone = serializers.CharField(required=False, allow_blank=True)

    # 사진은 serializer에서 검증하지 않고,
    # view에서 request.FILES.getlist("photo")로 선택 처리한다.
class TipListSerializer(serializers.ModelSerializer):
    photo_items = serializers.SerializerMethodField()
    photos = serializers.SerializerMethodField()
    physical = serializers.SerializerMethodField()
    clothing = serializers.SerializerMethodField()
    reporter_name = serializers.SerializerMethodField()
    reporter_phone = serializers.SerializerMethodField()
    missing_person_seq = serializers.SerializerMethodField()
    missing_profile_photo = serializers.SerializerMethodField()
    main_photo = serializers.SerializerMethodField()
    main_photo_source = serializers.SerializerMethodField()
    class Meta:
        model = Case
        fields = [
            "id",
            "reported_missing_name",
            "missing_person_seq",
            "occr_date",
            "occr_location",
            "status",
            "physical",
            "clothing",
            "reporter_name",
            "reporter_phone",
            "photos",
            "photo_items",
            "missing_profile_photo",
            "main_photo",
            "main_photo_source",
        ]

    def get_missing_profile_photo(self, obj):
        request = self.context.get("request")

        missing_person = getattr(
            obj,
            "missing_person",
            None,
        )

        if not missing_person:
            return None

        # photo ImageField가 따로 있는 경우
        photo = getattr(
            missing_person,
            "photo",
            None,
        )

        if photo:
            try:
                if photo.name:
                    return media_url(
                        photo.name,
                        request,
                    )
            except Exception:
                pass

        # image_urls 사용
        image_urls = (
                getattr(
                    missing_person,
                    "image_urls",
                    None,
                )
                or []
        )

        if not image_urls:
            return None

        return media_url(
            image_urls[0],
            request,
        )

    def _absolute_url(self, url):
        if not url:
            return None

        return media_url(
            url,
            self.context.get("request"),
        )

    def _get_first_missing_person_photo(self, obj):
        missing = obj.missing_person

        if not missing:
            return None

        request = self.context.get("request")

        image_urls = (
                getattr(
                    missing,
                    "image_urls",
                    None,
                )
                or []
        )

        if image_urls:
            return media_url(
                image_urls[0],
                request,
            )

        photo_field = getattr(
            missing,
            "photo",
            None,
        )

        if photo_field:
            try:
                if photo_field.name:
                    return media_url(
                        photo_field.name,
                        request,
                    )
            except Exception:
                pass

        return None

    def _get_first_tip_photo(self, obj):
        first_photo = obj.photos.first()

        if (
                first_photo
                and first_photo.image
        ):
            return media_url(
                first_photo.image.name,
                self.context.get("request"),
            )

        return None
    def get_main_photo(self, obj):
        # 1순위: 연결된 실종자 공식 사진
        missing_photo = self._get_first_missing_person_photo(obj)
        if missing_photo:
            return self._absolute_url(missing_photo)

        # 2순위: 제보자가 올린 사진
        tip_photo = self._get_first_tip_photo(obj)
        if tip_photo:
            return self._absolute_url(tip_photo)

        return None

    def get_main_photo_source(self, obj):
        if self._get_first_missing_person_photo(obj):
            return "missing_person_photo"

        if self._get_first_tip_photo(obj):
            return "tip_photo"

        return "none"

    def get_photos(self, obj):
        request = self.context.get("request")
        result = []

        for p in obj.photos.all():
            if not p.image:
                continue

            result.append(
                media_url(
                    p.image.name,
                    request,
                )
            )

        return result

    def get_photo_items(self, obj):
        request = self.context.get("request")
        result = []

        for p in obj.photos.all():
            if not p.image:
                continue

            image_url = media_url(
                p.image.name,
                request,
            )

            result.append({
                "id": p.id,
                "url": image_url,
                "image": p.image.name,
                "is_ai_generated": p.is_ai_generated,
                "uploaded_at": (
                    timezone.localtime(
                        p.uploaded_at
                    ).isoformat()
                    if p.uploaded_at
                    else None
                ),
            })

        return result
    def get_physical(self, obj):
        feature = obj.features.first()
        return feature.physical if feature else None

    def get_clothing(self, obj):
        feature = obj.features.first()
        return feature.clothing if feature else None

    def get_reporter_name(self, obj):
        if obj.reporter and obj.reporter.name:
            return obj.reporter.name
        return obj.payload.get("reporter_name") if obj.payload else None

    def get_reporter_phone(self, obj):
        if obj.reporter and obj.reporter.phone:
            return obj.reporter.phone
        return obj.payload.get("reporter_phone") if obj.payload else None
    def get_missing_person_seq(self, obj):
        return obj.missing_person.msspsn_idntfccd if obj.missing_person else None


class AdminTipSerializer(serializers.ModelSerializer):
    photo_items = serializers.SerializerMethodField()
    photos = serializers.SerializerMethodField()
    missing_profile_photo = serializers.SerializerMethodField()
    # ✅ 카드 대표 이미지
    main_photo = serializers.SerializerMethodField()
    main_photo_source = serializers.SerializerMethodField()

    physical = serializers.SerializerMethodField()
    clothing = serializers.SerializerMethodField()
    reporter_name = serializers.SerializerMethodField()
    reporter_phone = serializers.SerializerMethodField()
    missing_person_seq = serializers.SerializerMethodField()
    missing_person_name = serializers.SerializerMethodField()

    class Meta:
        model = Case
        fields = [
            "id",
            "created_at",
            "reported_missing_name",
            "missing_person_seq",
            "missing_person_name",
            "occr_date",
            "occr_location",
            "status",
            "missing_profile_photo",

            # ✅ 프론트 카드 메인 이미지용
            "main_photo",
            "main_photo_source",

            "physical",
            "clothing",
            "reporter_name",
            "reporter_phone",

            # ✅ 제보자가 올린 목격 사진 목록
            "photos",
            "photo_items",
        ]

    def get_missing_profile_photo(self, obj):
        request = self.context.get("request")

        missing_person = getattr(
            obj,
            "missing_person",
            None,
        )

        if not missing_person:
            return None

        photo = getattr(
            missing_person,
            "photo",
            None,
        )

        if photo:
            try:
                if photo.name:
                    return media_url(
                        photo.name,
                        request,
                    )
            except Exception:
                pass

        image_urls = (
                getattr(
                    missing_person,
                    "image_urls",
                    None,
                )
                or []
        )

        if not image_urls:
            return None

        return media_url(
            image_urls[0],
            request,
        )    # -------------------------------------------------
    # 공통 URL 변환
    # -------------------------------------------------
    def _absolute_url(self, url):
        if not url:
            return None

        return media_url(
            url,
            self.context.get("request"),
        )
    # -------------------------------------------------
    # 1순위: 기존 실종자 사진
    # -------------------------------------------------
    def _get_first_missing_person_photo(self, obj):
        missing = obj.missing_person

        if not missing:
            return None

        request = self.context.get("request")

        image_urls = (
                getattr(
                    missing,
                    "image_urls",
                    None,
                )
                or []
        )

        if image_urls:
            return media_url(
                image_urls[0],
                request,
            )

        photo_field = getattr(
            missing,
            "photo",
            None,
        )

        if photo_field:
            try:
                if photo_field.name:
                    return media_url(
                        photo_field.name,
                        request,
                    )
            except Exception:
                pass

        return None
    # -------------------------------------------------
    # 2순위: 제보자가 올린 사진
    # -------------------------------------------------
    def _get_first_tip_photo(self, obj):
        first_photo = obj.photos.first()

        if (
                first_photo
                and first_photo.image
        ):
            return media_url(
                first_photo.image.name,
                self.context.get("request"),
            )

        return None

    # -------------------------------------------------
    # 카드 대표 이미지
    # -------------------------------------------------
    def get_main_photo(self, obj):
        # ✅ 1순위: 연결된 실종자의 기존 사진
        missing_photo = self._get_first_missing_person_photo(obj)
        if missing_photo:
            return self._absolute_url(missing_photo)

        # ✅ 2순위: 제보자가 올린 사진
        tip_photo = self._get_first_tip_photo(obj)
        if tip_photo:
            return self._absolute_url(tip_photo)

        return None

    def get_main_photo_source(self, obj):
        if self._get_first_missing_person_photo(obj):
            return "missing_person_photo"

        if self._get_first_tip_photo(obj):
            return "tip_photo"

        return "none"

    # -------------------------------------------------
    # 제보자가 업로드한 사진 목록
    # -------------------------------------------------
    def get_photos(self, obj):
        request = self.context.get("request")
        result = []

        for p in obj.photos.all():
            if not p.image:
                continue

            result.append(
                media_url(
                    p.image.name,
                    request,
                )
            )

        return result

    def get_photo_items(self, obj):
        request = self.context.get("request")
        result = []

        for p in obj.photos.all():
            if not p.image:
                continue

            image_url = media_url(
                p.image.name,
                request,
            )

            result.append({
                "id": p.id,
                "url": image_url,
                "image": p.image.name,
                "is_ai_generated": p.is_ai_generated,
                "uploaded_at": (
                    timezone.localtime(
                        p.uploaded_at
                    ).isoformat()
                    if p.uploaded_at
                    else None
                ),
            })

        return result
    def get_physical(self, obj):
        feature = obj.features.first()
        return feature.physical if feature else None

    def get_clothing(self, obj):
        feature = obj.features.first()
        return feature.clothing if feature else None

    def get_reporter_name(self, obj):
        return obj.reporter.name if obj.reporter else None

    def get_reporter_phone(self, obj):
        return obj.reporter.phone if obj.reporter else None

    def get_missing_person_seq(self, obj):
        return obj.missing_person.msspsn_idntfccd if obj.missing_person else None

    def get_missing_person_name(self, obj):
        return obj.missing_person.name if obj.missing_person else None

class ProtectedPersonCardSerializer(serializers.ModelSerializer):
    """
    보호중이에요 카드 목록용
    - 분류 배지, 대표사진 1장, 이름, 성별, 나이, 등록일자
    """
    category_display = serializers.SerializerMethodField()
    photo = serializers.SerializerMethodField()
    gender_display = serializers.SerializerMethodField()
    registered_date = serializers.DateTimeField(source="crawled_at", format="%Y.%m.%d")

    class Meta:
        model = ProtectedPerson
        fields = [
            "id",
            "msspsn_idntfccd",
            "name",
            "gender_display",
            "current_age",
            "category_display",
            "photo",
            "registered_date",
        ]

    def get_category_display(self, obj):
        mapping = {
            "아동": "아동",
            "장애": "장애",
            "치매환자": "치매",
            "치매": "치매",
            "가출인": "기타",
        }

        # 🔥 핵심: 공백까지 제거
        if not obj.category or not obj.category.strip():
            return "기타"

        return mapping.get(obj.category, "기타")

    def get_photo(self, obj):
        if not obj.image_urls:
            return None

        return media_url(
            obj.image_urls[0],
            self.context.get("request"),
        )
    def get_gender_display(self, obj):
        mapping = {"남자": "남자", "여자": "여자"}
        return mapping.get(obj.gender, "미상")


class ProtectedPersonListSerializer(serializers.ModelSerializer):
    """목록용 - 핵심 필드"""
    category = serializers.SerializerMethodField()  # ← 추가

    class Meta:
        model = ProtectedPerson
        fields = [
            "id",
            "msspsn_idntfccd",
            "name",
            "gender",
            "category",
            "age_at_missing",
            "current_age",
            "occurred_at",
            "occurred_location",
            "image_urls",
            "status",
            "crawled_at",
        ]

    def get_category(self, obj):  # ← 추가
        if not obj.category:
            return "기타"
        return obj.category



class ProtectedPersonDetailSerializer(serializers.ModelSerializer):
    category_display = serializers.SerializerMethodField()
    gender_display   = serializers.SerializerMethodField()
    photos           = serializers.SerializerMethodField()
    occurred_display = serializers.SerializerMethodField()
    categories       = serializers.SerializerMethodField()

    class Meta:
        model = ProtectedPerson
        fields = [
            "id",
            "msspsn_idntfccd",
            "name",
            "gender_display",
            "age_at_missing",
            "current_age",
            "category_display",
            "occurred_display",
            "occurred_location",
            "photos",
            "categories",
            "status",
            "crawled_at",
        ]

    def get_category_display(self, obj):
        mapping = {
            "아동": "아동",
            "장애": "장애",
            "치매환자": "치매",
            "치매": "치매",
            "가출인": "기타",
        }

        # 🔥 핵심: 공백까지 제거
        if not obj.category or not obj.category.strip():
            return "기타"

        return mapping.get(obj.category, "기타")
    def get_gender_display(self, obj):
        return {"남자": "남자", "여자": "여자"}.get(obj.gender, "미상")

    def get_occurred_display(self, obj):
        """발생일시 → '0000년 00월 00일' 형식"""
        if not obj.occurred_at:
            return None
        return obj.occurred_at.strftime("%Y년 %m월 %d일")

    def get_photos(self, obj):
        if not obj.image_urls:
            return []

        request = self.context.get("request")

        return [
            media_url(
                path,
                request,
            )
            for path in obj.image_urls
            if path
        ]

    def get_categories(self, obj):
        # ── 룰베이스 기본 필드 ────────────────────────────────────────
        physical = []
        if obj.height:
            physical.append(f"키 {obj.height}")
        if obj.weight:
            physical.append(f"몸무게 {obj.weight}")
        if obj.body_type:
            physical.append(f"체격 {obj.body_type}")
        if obj.face_type:
            physical.append(f"얼굴형 {obj.face_type}")

        health = []
        if obj.category:
            health.append(obj.category)

        clothing_info = []
        if obj.hair_color:
            clothing_info.append(f"두발색상 {obj.hair_color}")
        if obj.hair_style:
            clothing_info.append(f"두발형태 {obj.hair_style}")
        if obj.clothing:
            clothing_info.append(obj.clothing)

        behavior = []
        extra = []

        # ✅ ProtectedPerson 모델에는 etc_spfeatr 필드가 없으므로 참조하지 않음
        # MissingPerson에는 etc_spfeatr가 있지만, ProtectedPerson에는 없음.
        # 따라서 보호중 상세에서는 기본 DB 필드만 categories로 구성한다.

        return {
            "신체 특징": physical,
            "성격·행동 특성": behavior,
            "건강·장애 정보": health,
            "착의·외형 정보": clothing_info,
            "기타 참고 사항": extra,
        }
# serializers.py 中 MissingPerson 관련 부분만 교체
# ─────────────────────────────────────────────────────────────────────────────
# 아래 3개 클래스로 기존 MissingPersonSerializer, MissingPersonCardSerializer,
# MissingPersonPhotoSerializer를 통째로 교체하세요.
# ─────────────────────────────────────────────────────────────────────────────



class MissingPersonSerializer(serializers.ModelSerializer):
    """
    '찾고 있어요' 상세용

    categories 구조:
        {
            "신체 특징":      [키, 몸무게, 체격, 얼굴형],
            "성격·행동 특성": [],
            "건강·장애 정보": [분류태그],
            "착의·외형 정보": [두발색상, 두발형태, 착의의상],
            "기타 참고 사항": [],
        }
    """

    category_display = serializers.SerializerMethodField()
    gender_display   = serializers.SerializerMethodField()
    occurred_display = serializers.SerializerMethodField()
    photos = serializers.SerializerMethodField()
    photo_items = serializers.SerializerMethodField()
    categories = serializers.SerializerMethodField()
    latest_montage = serializers.SerializerMethodField()

    def get_latest_montage(self, obj):
        request = self.context.get("request")

        montage = (
            obj.montages
            .order_by("-created_at")
            .first()
        )

        if not montage:
            return None

        result_img_url = None
        result_img_path = None

        if montage.result_img:
            result_img_path = (
                montage.result_img.name
            )

            result_img_url = media_url(
                result_img_path,
                request,
            )

        return {
            "id": montage.id,

            # 기존 호환용 경로
            "result_img": result_img_path,

            # 실제 표시용 URL
            "result_img_url": result_img_url,

            "created_at": (
                timezone.localtime(
                    montage.created_at
                ).isoformat()
            ),
        }
    class Meta:
        model = MissingPerson
        fields = [
            "id",
            "msspsn_idntfccd",
            "name",
            "gender_display",
            "age_at_missing",
            "current_age",
            "category_display",
            "nationality",
            "occurred_display",
            "occurred_location",
            "height",
            "weight",
            "body_type",
            "face_type",
            "hair_color",
            "hair_style",
            "clothing",
            "status",
            "photos",
            "photo_items",
            "categories",
            "crawled_at",
            "updated_at",
            "latest_montage",
        ]

    def get_category_display(self, obj):
        mapping = {
            "아동":    "아동",
            "장애":    "장애",
            "치매환자": "치매",
            "치매":    "치매",
            "가출인":  "기타",
        }
        if not obj.category:
            return "기타"
        return mapping.get(obj.category, "기타")

    def get_gender_display(self, obj):
        return {"남자": "남자", "여자": "여자"}.get(obj.gender, "미상")

    def get_occurred_display(self, obj):
        if not obj.occurred_at:
            return None
        return obj.occurred_at.strftime("%Y년 %m월 %d일")

    def get_photos(self, obj):
        if not obj.image_urls:
            return []

        request = self.context.get("request")

        return [
            media_url(
                path,
                request,
            )
            for path in obj.image_urls
            if path
        ]

    def get_photo_items(self, obj):
        if not obj.image_urls:
            return []

        request = self.context.get("request")
        ai_image_urls = obj.ai_image_urls or []

        result = []

        for path in obj.image_urls:
            if not path:
                continue

            result.append({
                "url": media_url(
                    path,
                    request,
                ),
                "path": path,
                "is_ai_generated": (
                        path in ai_image_urls
                ),
            })

        return result

    def get_categories(self, obj):
        """
        MissingPerson 상세 categories 생성

        처리 규칙
        1. DB 기본 필드에서 각 카테고리 생성
        2. 동일한 값은 중복 추가하지 않음
        3. clothing에 잘못 저장된 두발색상/두발형태는 제외
        4. clothing이 여러 줄인 경우 줄 단위로 분리
        5. etc_spfeatr의 라벨 데이터도 중복 제거
        6. 기존 Safe182 데이터 / AI 분류 데이터 호환 유지
        """

        # =========================================================
        # 0. 결과 배열
        # =========================================================
        physical = []
        health = []
        clothing_info = []
        behavior = []
        extra = []

        # =========================================================
        # 공통 중복 제거 함수
        # =========================================================
        def append_unique(bucket, value):
            if value is None:
                return

            value = str(value).strip()

            if not value:
                return

            if value not in bucket:
                bucket.append(value)

        # =========================================================
        # 착의 정보인지 / 머리 정보인지 판단
        # =========================================================
        def is_hair_info(value):
            if not value:
                return False

            value = str(value).strip()

            return (
                    value.startswith("두발색상")
                    or value.startswith("두발형태")
            )

        # =========================================================
        # clothing 문자열 처리
        #
        # 예:
        #
        # 두발색상 흑색
        # 두발형태 짧은머리(생머리)
        # 캐주얼차림
        # 두발색상 흑색
        #
        # ↓
        #
        # 캐주얼차림
        #
        # 만 clothing_info에 추가
        # =========================================================
        def add_clothing_value(value):
            if not value:
                return

            # 문자열 / 여러 줄 모두 대응
            lines = []

            if isinstance(value, (list, tuple)):
                raw_values = value
            else:
                raw_values = [value]

            for raw_value in raw_values:
                if raw_value is None:
                    continue

                # 줄바꿈 + 쉼표 대응
                split_values = re.split(
                    r"[\n\r,，]+",
                    str(raw_value)
                )

                for line in split_values:
                    line = line.strip()

                    if line:
                        lines.append(line)

            for line in lines:

                # 두발 정보는 hair_color / hair_style에서
                # 별도로 추가하므로 clothing에서는 제외
                if is_hair_info(line):
                    continue

                append_unique(
                    clothing_info,
                    line
                )

        # =========================================================
        # 1. 신체 특징
        # =========================================================
        if obj.height:
            append_unique(
                physical,
                f"키 {obj.height}"
            )

        if obj.weight:
            append_unique(
                physical,
                f"몸무게 {obj.weight}"
            )

        if obj.body_type:
            append_unique(
                physical,
                f"체격 {obj.body_type}"
            )

        if obj.face_type:
            append_unique(
                physical,
                f"얼굴형 {obj.face_type}"
            )

        # =========================================================
        # 2. 건강·장애 정보
        # =========================================================
        if obj.category:
            append_unique(
                health,
                obj.category
            )

        # =========================================================
        # 3. 착의·외형 정보
        #
        # 머리 정보는 전용 필드에서만 추가
        # =========================================================
        if obj.hair_color:
            append_unique(
                clothing_info,
                f"두발색상 {obj.hair_color}"
            )

        if obj.hair_style:
            append_unique(
                clothing_info,
                f"두발형태 {obj.hair_style}"
            )

        # 기존 DB clothing 데이터 정리해서 추가
        if obj.clothing:
            add_clothing_value(
                obj.clothing
            )

        # =========================================================
        # 4. 기타 특징 문장 처리
        # =========================================================
        etc_spfeatr = getattr(
            obj,
            "etc_spfeatr",
            None
        )

        if (
                etc_spfeatr
                and str(etc_spfeatr).strip()
        ):
            raw = str(
                etc_spfeatr
            ).strip()

            labeled_lines = [
                line.strip()
                for line in raw.splitlines()
                if line.strip()
            ]

            # -----------------------------------------------------
            # 라벨 형식 여부
            #
            # [신체 특징] ...
            # [건강·장애 정보] ...
            # [성격·행동 특성] ...
            # [착의·외형 정보] ...
            # [기타 참고 사항] ...
            # -----------------------------------------------------
            has_label = any(
                line.startswith("[신체 특징]")
                or line.startswith("[건강·장애 정보]")
                or line.startswith("[성격·행동 특성]")
                or line.startswith("[착의·외형 정보]")
                or line.startswith("[기타 참고 사항]")
                for line in labeled_lines
            )

            # =====================================================
            # 4-1. 라벨이 있는 신규 데이터
            # =====================================================
            if has_label:

                for line in labeled_lines:

                    # ---------------------------------------------
                    # 신체 특징
                    # ---------------------------------------------
                    if line.startswith(
                            "[신체 특징]"
                    ):
                        value = line.replace(
                            "[신체 특징]",
                            "",
                            1
                        ).strip()

                        append_unique(
                            physical,
                            value
                        )

                    # ---------------------------------------------
                    # 건강·장애 정보
                    # ---------------------------------------------
                    elif line.startswith(
                            "[건강·장애 정보]"
                    ):
                        value = line.replace(
                            "[건강·장애 정보]",
                            "",
                            1
                        ).strip()

                        append_unique(
                            health,
                            value
                        )

                    # ---------------------------------------------
                    # 성격·행동 특성
                    # ---------------------------------------------
                    elif line.startswith(
                            "[성격·행동 특성]"
                    ):
                        value = line.replace(
                            "[성격·행동 특성]",
                            "",
                            1
                        ).strip()

                        append_unique(
                            behavior,
                            value
                        )

                    # ---------------------------------------------
                    # 착의·외형 정보
                    # ---------------------------------------------
                    elif line.startswith(
                            "[착의·외형 정보]"
                    ):
                        value = line.replace(
                            "[착의·외형 정보]",
                            "",
                            1
                        ).strip()

                        # 두발 정보가 또 들어와도 중복 제외
                        if is_hair_info(value):
                            continue

                        add_clothing_value(
                            value
                        )

                    # ---------------------------------------------
                    # 기타 참고 사항
                    # ---------------------------------------------
                    elif line.startswith(
                            "[기타 참고 사항]"
                    ):
                        value = line.replace(
                            "[기타 참고 사항]",
                            "",
                            1
                        ).strip()

                        append_unique(
                            extra,
                            value
                        )

                    # ---------------------------------------------
                    # 알 수 없는 라벨 없는 줄
                    # ---------------------------------------------
                    else:
                        append_unique(
                            extra,
                            line
                        )

            # =====================================================
            # 4-2. 기존 Safe182 / 과거 데이터
            # =====================================================
            else:

                segments = (
                        getattr(
                            obj,
                            "etc_ai_segments",
                            None
                        )
                        or []
                )

                # -------------------------------------------------
                # AI 분류 결과가 있는 경우
                # -------------------------------------------------
                if segments:

                    for item in segments:

                        if not isinstance(
                                item,
                                dict
                        ):
                            continue

                        text = (
                                item.get("text")
                                or ""
                        ).strip()

                        category = (
                                item.get("category")
                                or ""
                        ).strip()

                        if not text:
                            continue

                        # 룰 기반 결과를 우선 적용
                        rule_cat = (
                            rule_based_category(
                                text
                            )
                        )

                        final_category = (
                                rule_cat
                                or category
                        )

                        # -----------------------------------------
                        # 신체 특징
                        # -----------------------------------------
                        if (
                                final_category
                                == "신체특징"
                        ):
                            append_unique(
                                physical,
                                text
                            )

                        # -----------------------------------------
                        # 착의·외형
                        # -----------------------------------------
                        elif (
                                final_category
                                == "착의외형"
                        ):

                            # 두발 정보라면 이미 기본 필드에서
                            # 추가했으므로 중복 제외
                            if is_hair_info(text):
                                continue

                            add_clothing_value(
                                text
                            )

                        # -----------------------------------------
                        # 건강·장애
                        # -----------------------------------------
                        elif (
                                final_category
                                == "건강장애"
                        ):
                            append_unique(
                                health,
                                text
                            )

                        # -----------------------------------------
                        # 행동
                        # -----------------------------------------
                        elif (
                                final_category
                                == "행동특성"
                        ):
                            append_unique(
                                behavior,
                                text
                            )

                        # -----------------------------------------
                        # 기타
                        # -----------------------------------------
                        else:
                            append_unique(
                                extra,
                                text
                            )

                # -------------------------------------------------
                # AI 분류도 없는 과거 데이터
                # -------------------------------------------------
                else:

                    parts = split_feature_text(
                        raw
                    )

                    for part in parts:

                        rule_cat = (
                            rule_based_category(
                                part
                            )
                        )

                        # -----------------------------------------
                        # 신체 특징
                        # -----------------------------------------
                        if (
                                rule_cat
                                == "신체특징"
                        ):
                            append_unique(
                                physical,
                                part
                            )

                        # -----------------------------------------
                        # 착의·외형
                        # -----------------------------------------
                        elif (
                                rule_cat
                                == "착의외형"
                        ):

                            if is_hair_info(part):
                                continue

                            add_clothing_value(
                                part
                            )

                        # -----------------------------------------
                        # 건강·장애
                        # -----------------------------------------
                        elif (
                                rule_cat
                                == "건강장애"
                        ):
                            append_unique(
                                health,
                                part
                            )

                        # -----------------------------------------
                        # 행동
                        # -----------------------------------------
                        elif (
                                rule_cat
                                == "행동특성"
                        ):
                            append_unique(
                                behavior,
                                part
                            )

                        # -----------------------------------------
                        # 기타
                        # -----------------------------------------
                        else:
                            append_unique(
                                extra,
                                part
                            )

        # =========================================================
        # 5. 최종 응답
        # =========================================================
        return {
            "신체 특징": physical,
            "성격·행동 특성": behavior,
            "건강·장애 정보": health,
            "착의·외형 정보": clothing_info,
            "기타 참고 사항": extra,
        }
class MissingPersonListSerializer(serializers.ModelSerializer):
    category = serializers.SerializerMethodField()

    class Meta:
        model = MissingPerson
        fields = [
            "id",
            "msspsn_idntfccd",
            "name",
            "gender",
            "category",
            "nationality",        # ← 추가
            "age_at_missing",
            "current_age",
            "occurred_at",
            "occurred_location",
            "height",             # ← 추가
            "weight",             # ← 추가
            "body_type",          # ← 추가
            "face_type",          # ← 추가
            "hair_color",         # ← 추가
            "hair_style",         # ← 추가
            "clothing",           # ← 추가
            "image_urls",
            "status",
            "crawled_at",
        ]

    def get_category(self, obj):
        return obj.category or "기타"

class MissingPersonCardSerializer(serializers.ModelSerializer):
    category_display = serializers.SerializerMethodField()
    photo = serializers.SerializerMethodField()
    photo_info = serializers.SerializerMethodField()
    photo_is_ai_generated = serializers.SerializerMethodField()
    gender_display = serializers.SerializerMethodField()
    registered_date = serializers.DateField(source="occurred_at")
    class Meta:
        model = MissingPerson
        fields = [
            "id",
            "msspsn_idntfccd",
            "name",
            "gender_display",
            "current_age",
            "category_display",

            # ✅ 기존 호환용: 문자열 URL
            "photo",

            # ✅ AI 태그용 추가 필드
            "photo_info",
            "photo_is_ai_generated",

            "registered_date",
        ]

    def get_category_display(self, obj):
        mapping = {
            "아동":    "아동",
            "장애":    "장애",
            "치매환자": "치매",
            "치매":    "치매",
            "가출인":  "기타",
        }
        if not obj.category:
            return "기타"
        return mapping.get(obj.category, "기타")

    def get_photo(self, obj):
        if not obj.image_urls:
            return None

        first = obj.image_urls[0]

        return media_url(
            first,
            self.context.get("request"),
        )
    def get_gender_display(self, obj):
        return {"남자": "남자", "여자": "여자"}.get(obj.gender, "미상")

    def get_photo_is_ai_generated(self, obj):
        if not obj.image_urls:
            return False

        first = obj.image_urls[0]
        ai_image_urls = obj.ai_image_urls or []

        return first in ai_image_urls

    def get_photo_info(self, obj):
        if not obj.image_urls:
            return None

        first = obj.image_urls[0]
        ai_image_urls = obj.ai_image_urls or []

        return {
            "url": media_url(
                first,
                self.context.get("request"),
            ),
            "path": first,
            "is_ai_generated": (
                    first in ai_image_urls
            ),
        }

class AdminUserSerializer(serializers.ModelSerializer):
    name = serializers.CharField(source="person.name", read_only=True)
    phone = serializers.CharField(source="person.phone", read_only=True)

    class Meta:
        model = UserAuth
        fields = ["id", "email", "role", "is_approved", "name", "phone"]


class RegisterMissingSerializer(serializers.Serializer):
    # 실종자 정보
    occurred_location = serializers.CharField(required=False, allow_blank=True)  # 발생장소
    name = serializers.CharField(required=True)
    prevention_registration_id = serializers.IntegerField(
        required=False,
        allow_null=True
    )
    age_at_missing = serializers.IntegerField(required=False, allow_null=True)
    gender = serializers.ChoiceField(choices=["male", "female"], required=False)
    resident_front = serializers.CharField(required=False, allow_blank=True)  # 주민번호 앞자리
    resident_back = serializers.CharField(required=False, allow_blank=True)   # 주민번호 뒷자리
    occurred_at = serializers.DateTimeField(required=False, allow_null=True)
    category = serializers.ChoiceField(
        choices=[
            "정상아동(18세 미만)", "지적장애인", "시설보호무연고자",
            "치매질환자", "지적 장애인(18세 미만)", "가출인",
            "지적장애인(18세 이상)", "불상(기타)"
        ],
        required=False, allow_blank=True
    )
    nationality = serializers.CharField(required=False, allow_blank=True)
    height = serializers.CharField(
        required=False,
        allow_blank=True,
    )

    weight = serializers.CharField(
        required=False,
        allow_blank=True,
    )
    body_type = serializers.ChoiceField(
        choices=["알 수 없음", "비만", "건장", "보통", "왜소", "특이체형", "기타"],
        required=False, allow_blank=True
    )
    face_type = serializers.ChoiceField(
        choices=["알 수 없음", "삼각형", "역삼각형", "계란형", "사각형", "둥근형", "갸름한형", "기타"],
        required=False, allow_blank=True
    )
    hair_color = serializers.ChoiceField(
        choices=["알 수 없음", "흑색", "백색", "반백", "갈색", "염색", "기타"],
        required=False, allow_blank=True
    )
    hair_style = serializers.ChoiceField(
        choices=["알 수 없음", "삭발", "대머리", "긴머리", "곱슬긴머리", "단발머리",
                 "커트머리", "곱슬단발머리", "가발", "스포츠형",
                 "짧은머리(생머리)", "긴머리(생머리)", "짧은머리(퍼머)",
                 "긴머리(퍼머)", "묶음머리", "기타"],
        required=False, allow_blank=True
    )
    clothing = serializers.ChoiceField(
        choices=["알 수 없음", "정장차림", "군복차림", "작업복차림", "운동복차림",
                 "가죽옷차림", "한복차림", "캐주얼차림", "속옷차림",
                 "투피스", "원피스", "교복차림", "불상", "기타"],
        required=False, allow_blank=True
    )
    description = serializers.CharField(required=False, allow_blank=True)  # 신고 내용
    # 카테고리형 추가 정보
    physical = serializers.CharField(required=False, allow_blank=True)
    health = serializers.CharField(required=False, allow_blank=True)
    behavior = serializers.CharField(required=False, allow_blank=True)
    etc = serializers.CharField(required=False, allow_blank=True)
    # 신고자 정보
    # 로그인 사용자는 자동으로 user.person 정보 사용
    # 비회원은 view에서 직접 필수 검증
    reporter_name = serializers.CharField(required=False, allow_blank=True)
    reporter_resident_front = serializers.CharField(required=False, allow_blank=True)
    reporter_resident_back = serializers.CharField(required=False, allow_blank=True)
    reporter_phone = serializers.CharField(required=False, allow_blank=True)
    # 사진
    photo = serializers.ListField(
        child=serializers.ImageField(),
        required=False
    )

class MissingPersonCategoryUpdateSerializer(serializers.Serializer):
    """
    프론트 categories 구조로 수정 받는 Serializer
    """

    신체_특징 = serializers.ListField(required=False)
    성격_행동_특성 = serializers.ListField(required=False)
    건강_장애_정보 = serializers.ListField(required=False)
    착의_외형_정보 = serializers.ListField(required=False)
    기타_참고_사항 = serializers.ListField(required=False)

    def update(self, instance, validated_data):
        # 🔥 신체 특징 파싱
        physical = validated_data.get("신체_특징", [])
        for item in physical:
            if "키" in item:
                instance.height = item.replace("키 ", "")
            elif "몸무게" in item:
                instance.weight = item.replace("몸무게 ", "")

        # 🔥 착의
        clothing = validated_data.get("착의_외형_정보")
        if clothing:
            instance.clothing = clothing[0]

        # 🔥 기타
        extra = validated_data.get("기타_참고_사항")
        if extra:
            instance.etc_spfeatr = "\n".join(extra)

        instance.save()
        return instance


class MyReportDetailSerializer(serializers.ModelSerializer):
    photo_items = serializers.SerializerMethodField()
    photos = serializers.SerializerMethodField()
    categories = serializers.SerializerMethodField()
    occurred_display = serializers.SerializerMethodField()

    class Meta:
        model = Case
        fields = [
            "id",
            "reported_missing_name",
            "status",
            "occurred_display",
            "occr_location",
            "photos",
            "categories",
            "created_at",
            "photo_items",
        ]

    def get_photos(self, obj):
        request = self.context.get("request")

        return [
            media_url(
                p.image.name,
                request,
            )
            for p in obj.photos.all()
            if p.image
        ]

    def get_photo_items(self, obj):
        request = self.context.get("request")
        result = []

        for p in obj.photos.all():
            if not p.image:
                continue

            result.append({
                "id": p.id,
                "url": media_url(
                    p.image.name,
                    request,
                ),
                "image": p.image.name,
                "is_ai_generated": p.is_ai_generated,
                "uploaded_at": (
                    timezone.localtime(
                        p.uploaded_at
                    ).isoformat()
                    if p.uploaded_at
                    else None
                ),
            })

        return result
    def get_occurred_display(self, obj):
        if not obj.occr_date:
            return None
        return obj.occr_date.strftime("%Y년 %m월 %d일")

    def get_categories(self, obj):
        payload = obj.payload or {}
        return build_missing_report_categories(payload)
class MyTipDetailSerializer(serializers.ModelSerializer):
    photo_items = serializers.SerializerMethodField()
    photos = serializers.SerializerMethodField()
    categories = serializers.SerializerMethodField()
    occurred_display = serializers.SerializerMethodField()

    class Meta:
        model = Case
        fields = [
            "id",
            "reported_missing_name",
            "status",
            "occurred_display",
            "occr_location",
            "photos",
            "categories",
            "created_at",
            "photo_items",
        ]

    def get_photos(self, obj):
        request = self.context.get("request")

        return [
            media_url(
                p.image.name,
                request,
            )
            for p in obj.photos.all()
            if p.image
        ]

    def get_photo_items(self, obj):
        request = self.context.get("request")
        result = []

        for p in obj.photos.all():
            if not p.image:
                continue

            result.append({
                "id": p.id,
                "url": media_url(
                    p.image.name,
                    request,
                ),
                "image": p.image.name,
                "is_ai_generated": p.is_ai_generated,
                "uploaded_at": (
                    timezone.localtime(
                        p.uploaded_at
                    ).isoformat()
                    if p.uploaded_at
                    else None
                ),
            })

        return result
    def get_occurred_display(self, obj):
        if not obj.occr_date:
            return None
        return obj.occr_date.strftime("%Y년 %m월 %d일")

    def get_categories(self, obj):
        feature = obj.features.first()

        physical = []
        clothing = []
        behavior = []
        health = []
        extra = []

        if feature:
            if feature.physical:
                physical.append(feature.physical)

            if feature.clothing:
                clothing.append(feature.clothing)

            if feature.behavior:
                behavior.append(feature.behavior)

            if feature.health:
                health.append(feature.health)

            if feature.etc:
                extra.append(feature.etc)

        return {
            "신체 특징": physical,
            "성격·행동 특성": behavior,
            "건강·장애 정보": health,
            "착의·외형 정보": clothing,
            "기타 참고 사항": extra,
        }


class CasePublicDetailSerializer(serializers.ModelSerializer):
    """
    일반 신고/제보 상세보기용
    - 내 신고/제보 전용 serializer와 분리
    - 신고/제보 type 포함
    - 카테고리 묶음 구조로 반환
    """
    photo_items = serializers.SerializerMethodField()
    type = serializers.SerializerMethodField()
    photos = serializers.SerializerMethodField()
    categories = serializers.SerializerMethodField()
    occurred_display = serializers.SerializerMethodField()
    reporter_name = serializers.SerializerMethodField()
    reporter_phone = serializers.SerializerMethodField()
    class Meta:
        model = Case
        fields = [
            "id",
            "type",
            "reported_missing_name",
            "status",
            "occurred_display",
            "occr_location",
            "photos",
            "categories",
            "created_at",
            "reporter_name",  # 추가
            "reporter_phone",
            "photo_items",
        ]

    def get_type(self, obj):
        mapping = {
            "report": "신고",
            "tip": "제보",
            "missing": "신고"
        }
        return mapping.get(obj.type_code, "기타")

    def get_photos(self, obj):
        request = self.context.get("request")

        return [
            media_url(
                p.image.name,
                request,
            )
            for p in obj.photos.all()
            if p.image
        ]

    def get_photo_items(self, obj):
        request = self.context.get("request")
        result = []

        for p in obj.photos.all():
            if not p.image:
                continue

            result.append({
                "id": p.id,
                "url": media_url(
                    p.image.name,
                    request,
                ),
                "image": p.image.name,
                "is_ai_generated": p.is_ai_generated,
                "uploaded_at": (
                    timezone.localtime(
                        p.uploaded_at
                    ).isoformat()
                    if p.uploaded_at
                    else None
                ),
            })

        return result
    def get_occurred_display(self, obj):
        if not obj.occr_date:
            return None
        return obj.occr_date.strftime("%Y년 %m월 %d일")

    def get_categories(self, obj):
        payload = obj.payload or {}
        feature = obj.features.first()

        # 신고 / 실종 등록 계열
        if obj.type_code == Case.TypeCode.MISSING:
            return build_missing_report_categories(payload)

        # 제보 계열
        physical = []
        behavior = []
        health = []
        clothing = []
        extra = []

        if obj.type_code == Case.TypeCode.TIP and feature:
            if feature.physical:
                append_unique(physical, feature.physical)

            if feature.behavior:
                append_unique(behavior, feature.behavior)

            if feature.health:
                append_unique(health, feature.health)

            if feature.clothing:
                append_unique(clothing, feature.clothing)

            if feature.etc:
                append_unique(extra, feature.etc)

        return {
            "신체 특징": physical,
            "성격·행동 특성": behavior,
            "건강·장애 정보": health,
            "착의·외형 정보": clothing,
            "기타 참고 사항": extra,
        }
    def get_reporter_name(self, obj):
        payload = obj.payload or {}

        # 1순위: payload에 저장된 이름
        if payload.get("reporter_name"):
            return payload.get("reporter_name")

        # 2순위: reporter 연결돼 있으면 person 이름
        if obj.reporter and hasattr(obj.reporter, "name"):
            return obj.reporter.name

        return None

    def get_reporter_phone(self, obj):
        payload = obj.payload or {}

        # 1순위: payload에 저장된 전화번호
        if payload.get("reporter_phone"):
            return payload.get("reporter_phone")

        # 2순위: reporter 연결돼 있으면 person 전화번호
        if obj.reporter and hasattr(obj.reporter, "phone"):
            return obj.reporter.phone

        return None

class MontageInputPhotoSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()

    class Meta:
        model = MontageInputPhoto
        fields = [
            "id",
            "image",
            "image_url",
            "created_at",
            "updated_at",
        ]

    def get_image_url(self, obj):
        if not obj.image:
            return None

        return media_url(
            obj.image.name,
            self.context.get("request"),
        )


class MontageSerializer(serializers.ModelSerializer):
    result_img_url = serializers.SerializerMethodField()
    input_photos = MontageInputPhotoSerializer(many=True, read_only=True)

    class Meta:
        model = Montage
        fields = [
            "id",
            "case",
            "missing_person",
            "generated_by",
            "result_img",
            "result_img_url",
            "age_estimate",
            "confidence",
            "is_applied",
            "input_photos",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "generated_by",
            "result_img",
            "result_img_url",
            "input_photos",
            "created_at",
            "updated_at",
        ]

    def get_result_img_url(self, obj):
        if not obj.result_img:
            return None

        return media_url(
            obj.result_img.name,
            self.context.get("request"),
        )
class PreventionPhotoSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()

    class Meta:
        model = PreventionPhoto
        fields = [
            "id",
            "photo_type",
            "image",
            "image_url",
            "is_validated",
            "validation_status",
            "validation_message",
            "validation_confidence",
            "created_at",
        ]
        read_only_fields = [
            "id",
            "image_url",
            "is_validated",
            "validation_status",
            "validation_message",
            "validation_confidence",
            "created_at",
        ]

    def get_image_url(self, obj):
        if not obj.image:
            return None

        return media_url(
            obj.image.name,
            self.context.get("request"),
        )

class PreventionRegistrationSerializer(serializers.ModelSerializer):
    photos = PreventionPhotoSerializer(many=True, read_only=True)
    status_label = serializers.SerializerMethodField()
    reviewed_by_name = serializers.SerializerMethodField()
    # 프론트에서 한글 라벨을 받을 수 있도록 직접 선언
    category = serializers.CharField(
        required=False,
        allow_blank=True,
    )
    category_label = serializers.CharField(
        source="get_category_display",
        read_only=True,
    )
    def validate_category(self, value):
        """
        프론트에서는 한글 라벨을 보내고,
        DB에는 코드값(010, 020, ...)으로 저장한다.
        코드값이 직접 들어와도 그대로 허용한다.
        """
        if not value:
            return ""

        value = str(value).strip()

        category_map = {
            "정상아동(18세 미만)": "010",
            "정상아동 (18세 미만)": "010",

            "가출인": "020",

            "시설보호무연고자": "040",
            "시설 보호 무연고자": "040",

            "지적장애인": "060",

            "지적 장애인(18세 미만)": "061",
            "지적장애인(18세 미만)": "061",
            "지적장애인 (18세 미만)": "061",

            "지적장애인(18세 이상)": "062",
            "지적 장애인(18세 이상)": "062",
            "지적장애인 (18세 이상)": "062",

            "치매질환자": "070",
            "치매 질환자": "070",

            "불상(기타)": "080",
            "불상 (기타)": "080",
        }

        # 이미 코드값으로 들어오면 그대로 저장
        if value in PreventionRegistration.Category.values:
            return value

        mapped_value = category_map.get(value)

        if mapped_value:
            return mapped_value

        raise serializers.ValidationError(
            "올바른 분류값이 아닙니다."
        )
    class Meta:
        model = PreventionRegistration
        fields = [
            "id",
            "owner",

            "status",
            "status_label",
            "rejected_reason",
            "reviewed_by",
            "reviewed_by_name",
            "reviewed_at",

            "name",
            "gender",
            "category",
            "category_label",
            "rrn_front",
            "rrn_back",
            "phone",
            "address",
            "frequent_place",
            "note",

            "height",
            "weight",
            "body_type",
            "face_type",
            "hair_color",
            "hair_style",
            "blood_type",
            "eye_color",

            "physical_feature",
            "health_info",

            "guardian_name",
            "guardian_rrn_front",
            "guardian_rrn_back",
            "guardian_phone",

            "privacy_agreed",
            "phone_verified",
            "is_active",

            "photos",
            "created_at",
            "updated_at",
            "device_code",
            "linked_person",
        ]
        read_only_fields = [
            "id",
            "owner",
            "status",
            "status_label",
            "rejected_reason",
            "reviewed_by",
            "reviewed_by_name",
            "reviewed_at",
            "photos",
            "created_at",
            "updated_at",
        ]

        # ✅ 프론트가 안 보내는 값은 백엔드에서 보완하기 위해 필수 해제
        extra_kwargs = {
            "gender": {"required": False, "allow_blank": True},
            "rrn_front": {"required": False, "allow_blank": True},
            "rrn_back": {"required": False, "allow_blank": True},
            "phone": {"required": False, "allow_blank": True},
            "address": {"required": False, "allow_blank": True},
            "frequent_place": {"required": False, "allow_blank": True},
            "note": {"required": False, "allow_blank": True},

            "height": {"required": False, "allow_blank": True},
            "weight": {"required": False, "allow_blank": True},
            "body_type": {"required": False, "allow_blank": True},
            "face_type": {"required": False, "allow_blank": True},
            "hair_color": {"required": False, "allow_blank": True},
            "hair_style": {"required": False, "allow_blank": True},
            "blood_type": {"required": False, "allow_blank": True},
            "eye_color": {"required": False, "allow_blank": True},

            "physical_feature": {"required": False, "allow_blank": True},
            "health_info": {"required": False, "allow_blank": True},

            "guardian_rrn_front": {"required": False, "allow_blank": True},
            "guardian_rrn_back": {"required": False, "allow_blank": True},

            "privacy_agreed": {"required": False},
            "phone_verified": {"required": False},
            "is_active": {"required": False},
        }

    def validate_gender(self, value):
        """
        프론트는 성별을 '남자' / '여자'로 보냄.
        백엔드 모델 choices가 male/female/unknown 구조여도 저장되도록 변환.
        """
        if not value:
            return "unknown"

        gender_map = {
            "남자": "male",
            "여자": "female",
            "기타": "unknown",
            "미상": "unknown",
            "male": "male",
            "female": "female",
            "unknown": "unknown",
        }

        return gender_map.get(str(value).strip(), "unknown")

    def validate(self, attrs):
        """
        프론트 RegisterFormTab 기준:
        - 약관 동의는 프론트에서 _isAgreed로 검사하지만 request.fields에는 안 보냄
        - 로그인 사용자는 _isVerified=true로 처리하지만 phone_verified도 안 보냄

        따라서 백엔드에서는 누락 시 true로 보완한다.
        """
        attrs["privacy_agreed"] = attrs.get("privacy_agreed", True)
        attrs["phone_verified"] = attrs.get("phone_verified", True)

        # 프론트에서 빈 문자열로 오는 값 정리
        optional_defaults = {
            "height": "알 수 없음",
            "weight": "알 수 없음",
            "body_type": "알 수 없음",
            "face_type": "알 수 없음",
            "hair_color": "알 수 없음",
            "hair_style": "알 수 없음",
            "blood_type": "알 수 없음",
            "eye_color": "알 수 없음",
        }

        for field, default_value in optional_defaults.items():
            if not attrs.get(field):
                attrs[field] = default_value

        return attrs

    def get_status_label(self, obj):
        return obj.get_status_display()

    def get_reviewed_by_name(self, obj):
        if obj.reviewed_by:
            return obj.reviewed_by.name
        return None

class PreventionRegistrationListSerializer(serializers.ModelSerializer):
    main_photo = serializers.SerializerMethodField()
    status_label = serializers.SerializerMethodField()
    photo_validation_summary = serializers.SerializerMethodField()
    category_label = serializers.CharField(
        source="get_category_display",
        read_only=True,
    )
    class Meta:
        model = PreventionRegistration
        fields = [
            "id",
            "name",
            "gender",
            "category",
            "category_label",
            "phone",
            "address",
            "guardian_name",
            "guardian_phone",

            "status",
            "status_label",
            "rejected_reason",

            "main_photo",
            "photo_validation_summary",

            "created_at",
            "updated_at",
            "is_active",
        ]

    def get_status_label(self, obj):
        return obj.get_status_display()

    def get_main_photo(self, obj):
        request = self.context.get("request")

        photo = (
                obj.photos
                .filter(photo_type="face")
                .first()
                or obj.photos.first()
        )

        if (
                not photo
                or not photo.image
        ):
            return None

        return media_url(
            photo.image.name,
            request,
        )
    def get_photo_validation_summary(self, obj):
        photos = list(obj.photos.all())

        return {
            "total": len(photos),
            "valid": len([p for p in photos if p.validation_status == "valid"]),
            "warning": len([p for p in photos if p.validation_status == "warning"]),
            "invalid": len([p for p in photos if p.validation_status == "invalid"]),
            "error": len([p for p in photos if p.validation_status == "error"]),
            "unchecked": len([p for p in photos if p.validation_status == "unchecked"]),
        }

class EmergencyReportSerializer(serializers.Serializer):
    device_code = serializers.CharField(max_length=100)
    timestamp = serializers.CharField(required=False, allow_blank=True)

    def validate_timestamp(self, value):
        if not value:
            return None

        parsed = parse_datetime(value)

        if parsed is None:
            raise serializers.ValidationError(
                "timestamp는 ISO 8601 형식이어야 합니다. 예: 2026-05-12T10:30:00.000Z"
            )

        return parsed


class DeviceLocationLogSerializer(serializers.Serializer):
    device_code = serializers.CharField(max_length=100)
    lat = serializers.FloatField()
    lng = serializers.FloatField()
    timestamp = serializers.CharField(required=False, allow_blank=True)

    def validate_lat(self, value):
        if value < -90 or value > 90:
            raise serializers.ValidationError("lat은 -90 이상 90 이하만 가능합니다.")
        return value

    def validate_lng(self, value):
        if value < -180 or value > 180:
            raise serializers.ValidationError("lng는 -180 이상 180 이하만 가능합니다.")
        return value

    def validate_timestamp(self, value):
        if not value:
            return None

        parsed = parse_datetime(value)

        if parsed is None:
            raise serializers.ValidationError(
                "timestamp는 ISO 8601 형식이어야 합니다. 예: 2026-05-12T10:30:00.000Z"
            )

        return parsed
class GPSLocationSerializer(serializers.Serializer):
    """
    ESP32에서 전달하는 GPS 좌표 검증용 Serializer
    """

    device_code = serializers.CharField(max_length=100)
    lat = serializers.FloatField()
    lng = serializers.FloatField()
    timestamp = serializers.DateTimeField(required=False)

    def validate_lat(self, value):
        if value < -90 or value > 90:
            raise serializers.ValidationError("lat은 -90 이상 90 이하만 가능합니다.")
        return value

    def validate_lng(self, value):
        if value < -180 or value > 180:
            raise serializers.ValidationError("lng는 -180 이상 180 이하만 가능합니다.")
        return value