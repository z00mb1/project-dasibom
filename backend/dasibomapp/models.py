
# Create your models here.
# models.py
from django.db import models
from django.core.validators import MinValueValidator, MaxValueValidator
from django.utils import timezone
def tip_photo_upload_path(instance, filename):
    return f"tip_photos/case_{instance.case_id}/{filename}"

# ---------- Common mixins ----------
class TimeStampedModel(models.Model):
    """auto_now_add / auto_now 일관 적용"""
    created_at = models.DateTimeField(auto_now_add=True, null=True)
    updated_at = models.DateTimeField(auto_now_add=True, null=True)

    class Meta:
        abstract = True


# ---------- Person ----------
class Person(TimeStampedModel):
    class Sex(models.TextChoices):
        MALE = "male", "male"
        FEMALE = "female", "female"
        UNKNOWN = "unknown", "unknown"

    name = models.CharField(max_length=255, null=True, blank=True, help_text="사용자 이름")
    sex = models.CharField(max_length=8, choices=Sex.choices, default=Sex.UNKNOWN)
    birth = models.DateField(null=True, blank=True, help_text="YYYY-MM-DD")
    phone = models.CharField(max_length=20, null=True, blank=True)
    address = models.CharField(max_length=200, null=True, blank=True)
    health_info = models.TextField(null=True, blank=True)

    def __str__(self):
        return f"{self.name or 'Person'}({self.pk})"

    class Meta:
        indexes = [
            models.Index(fields=["name"]),
            models.Index(fields=["phone"]),
        ]

# ---------- PhoneLog (전화번호 인증 요청 기록) ----------
class PhoneLog(models.Model):
    """
    하루 전체 인증번호 발송 횟수 제한(10회)을 위해 기록하는 로그 테이블.
    phone: 인증 요청에 사용된 전화번호 (기록용)
    date: YYYY-MM-DD (하루 단위 그룹 기준)
    """
    phone = models.CharField(max_length=20, null=False, blank=False)
    date = models.DateField(db_index=True)

    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.phone} @ {self.date}"

    class Meta:
        indexes = [
            models.Index(fields=["date"]),
        ]

# ---------- PhoneRequest (SMS 발송 대기 상태 기록) ----------
class PhoneRequest(models.Model):
    phone = models.CharField(max_length=20)
    created_at = models.DateTimeField(auto_now_add=True)
    confirmed = models.BooleanField(default=False)  # Firebase 전송 성공 여부

    def __str__(self):
        return f"{self.phone} ({'OK' if self.confirmed else 'PENDING'})"

    class Meta:
        indexes = [
            models.Index(fields=["phone"]),
            models.Index(fields=["created_at"]),
        ]

# ---------- UserAuth (계정/인증) ----------
class UserAuth(TimeStampedModel):
    """
    명세상 person_id(FK:Person), email UNIQUE, password(해시 저장, OAuth면 NULL)
    한 Person 당 하나의 UserAuth를 가정 → OneToOneField 사용
    """
    person = models.OneToOneField(Person, on_delete=models.CASCADE, related_name="auth")
    firebase_uid=models.CharField(max_length=128,unique=True, null=True, blank=True)
    class Role(models.TextChoices):
        ADMIN = "admin", "admin"
        GUARDIAN = "guardian", "guardian"
        CITIZEN = "citizen", "citizen"
        GUEST = "guest", "guest"

    kakao_id = models.CharField(max_length=50, unique=True, null=True, blank=True)
    email = models.EmailField(max_length=100, unique=True,null=True,blank=True)
    password = models.CharField(max_length=255, null=True, blank=True, help_text="해시 저장. OAuth 계정은 NULL 가능")
    is_approved = models.BooleanField(default=False)
    role = models.CharField(max_length=10, choices=Role.choices, default=Role.CITIZEN)
    device_id = models.CharField(max_length=100, null=True, blank=True, help_text="세션/디바이스 식별자")
    last_login = models.DateTimeField(null=True, blank=True)

    @property
    def is_authenticated(self):
        return True

    @property
    def is_anonymous(self):
        return False
    def __str__(self):
        return f"{self.email}"


# ---------- Guardian (보호자-피보호자 관계) ----------
class Guardian(TimeStampedModel):
    guardian = models.ForeignKey(
        Person,
        on_delete=models.CASCADE,
        related_name="ward_relations",
    )

    ward = models.ForeignKey(
        Person,
        on_delete=models.CASCADE,
        related_name="guardian_relations",
    )

    relation = models.CharField(
        max_length=30,
        null=True,
        blank=True,
    )

    def __str__(self):
        return (
            f"{self.guardian_id} -> "
            f"{self.ward_id} ({self.relation or ''})"
        )

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["guardian", "ward"],
                name="uniq_guardian_ward",
            )
        ]
        indexes = [
            models.Index(fields=["guardian"]),
            models.Index(fields=["ward"]),
        ]

class MissingPerson(models.Model):
    """
    안전Dream '찾고 있어요' 실종자 크롤링 데이터

    ProtectedPerson('보호하고 있어요')와 동일한 구조로 설계.
    - AI/규칙기반 파싱 필드 제거
    - 크롤링 원본 필드 기준으로 재설계
    - image_urls JSONField로 로컬 저장 경로 관리
    """

    class Source(models.TextChoices):
        SAFE182 = "safe182", "safe182"
        USER = "user", "user"

    source = models.CharField(
        max_length=20,
        choices=Source.choices,
        default=Source.SAFE182
    )
    # ── 식별자 ────────────────────────────────────────────────────────────────
    msspsn_idntfccd = models.CharField(
        max_length=20,
        unique=True,
        verbose_name="실종자식별코드",
        help_text="safe182 고유 식별코드 (예: 6096410)",
        default="",
    )

    # ── 기본 신상정보 ─────────────────────────────────────────────────────────
    name = models.CharField(max_length=50, verbose_name="이름", default="")
    gender = models.CharField(
        max_length=10,
        verbose_name="성별",
        choices=[("남자", "남자"), ("여자", "여자")],
        blank=True,
        default="",
    )
    category = models.CharField(
        max_length=20,
        verbose_name="분류",
        help_text="아동, 장애, 치매환자, 가출인 등 (span.info)",
        blank=True,
        default="",
    )
    nationality = models.CharField(
        max_length=20, verbose_name="국적", blank=True, default=""
    )

    # ── 나이 ──────────────────────────────────────────────────────────────────
    age_at_missing = models.IntegerField(
        verbose_name="당시나이(세)", null=True, blank=True
    )
    current_age = models.IntegerField(
        verbose_name="현재나이(세)", null=True, blank=True
    )

    # ── 발생정보 ──────────────────────────────────────────────────────────────
    occurred_at = models.DateField(verbose_name="발생일시", null=True, blank=True)
    occurred_location = models.CharField(
        max_length=200, verbose_name="발생장소", blank=True, default=""
    )

    # ── 신체정보 ──────────────────────────────────────────────────────────────
    height = models.CharField(max_length=10, verbose_name="키", blank=True, default="")
    weight = models.CharField(
        max_length=10, verbose_name="몸무게", blank=True, default=""
    )
    body_type = models.CharField(
        max_length=20, verbose_name="체격", blank=True, default=""
    )
    face_type = models.CharField(
        max_length=20, verbose_name="얼굴형", blank=True, default=""
    )
    hair_color = models.CharField(
        max_length=20, verbose_name="두발색상", blank=True, default=""
    )
    hair_style = models.CharField(
        max_length=50, verbose_name="두발형태", blank=True, default=""
    )
    clothing = models.CharField(
        max_length=200, verbose_name="착의의상", blank=True, default=""
    )

    # ── 진행상태 ──────────────────────────────────────────────────────────────
    class Status(models.TextChoices):
        MISSING = "missing", "실종중"
        FOUND = "found", "찾음"

    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.MISSING,
        verbose_name="진행상태"
    )

    # ── 이미지 ────────────────────────────────────────────────────────────────
    # 로컬 저장 상대경로 목록 (media/ 기준)
    # 예: ["missing_persons/6096410/0.jpg", "missing_persons/6096410/1.jpg"]
    image_urls = models.JSONField(
        verbose_name="이미지경로목록", default=list, blank=True
    )
    etc_spfeatr = models.TextField(
        verbose_name="추가특징",
        blank=True,
        default=""
    )
    # ── 크롤링 메타 ───────────────────────────────────────────────────────────
    crawled_at = models.DateTimeField(
        default=timezone.now, verbose_name="크롤링일시", editable=False
    )
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시", null=True)
    # 🔥 AI 분류 캐시 필드 추가 (ProtectedPerson과 동일한 방식)
    etc_ai_category = models.CharField(
        max_length=20,
        null=True,
        blank=True,
        help_text="AI 분류 결과: 신체특징 / 착의외형 / 건강장애 / 기타참고"
    )
    etc_ai_confidence = models.FloatField(
        null=True,
        blank=True,
        help_text="AI 분류 신뢰도 0.0~1.0"
    )
    etc_ai_segments = models.JSONField(default=list, blank=True)
    # ✅ 추가
    ai_image_urls = models.JSONField(default=list, blank=True)
    class Meta:
        db_table = "safe182_missing_person"
        verbose_name = "실종자"
        verbose_name_plural = "실종자 목록"
        ordering = ["-occurred_at"]
        indexes = [
            models.Index(fields=["msspsn_idntfccd"]),
            models.Index(fields=["status"]),
            models.Index(fields=["occurred_at"]),
            models.Index(fields=["category"]),
            models.Index(fields=["gender"]),
        ]

    def __str__(self):
        return f"{self.name}({self.current_age}세) - {self.msspsn_idntfccd}"
# ---------- Device ----------
class Device(TimeStampedModel):
    class Status(models.TextChoices):
        ACTIVE = "active", "active"
        INACTIVE = "inactive", "inactive"
        ERROR = "error", "error"
        DISCONNECTED = "disconnected", "disconnected"

    person = models.OneToOneField(
        Person,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="badge",
        help_text="연결된 피보호자",
    )

    device_uid = models.CharField(
        max_length=100,
        unique=True,
        help_text="하드웨어 고유 식별 코드",
    )

    def save(self, *args, **kwargs):
        if self.badge_uid:
            self.badge_uid = (
                str(self.badge_uid)
                .strip()
                .lower()
                .replace(":", "")
                .replace("-", "")
            )

        super().save(*args, **kwargs)
    badge_uid = models.CharField(
        max_length=32,
        unique=True,
        null=True,
        blank=True,
        db_index=True,
        help_text="키링에 붙은 NFC 스티커 UID (소문자 hex, 구분자 없음)",
    )
    status = models.CharField(
        max_length=12,
        choices=Status.choices,
        default=Status.INACTIVE,
        db_index=True,
    )

    battery = models.IntegerField(
        validators=[
            MinValueValidator(0),
            MaxValueValidator(100),
        ],
        default=100,
    )

    last_signal_time = models.DateTimeField(
        null=True,
        blank=True,
    )

    lat = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
    )

    lon = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
    )

    nfc_tag = models.BooleanField(default=False)

    signal_strength = models.IntegerField(
        null=True,
        blank=True,
    )

# ---------- Case (등록/신고/제보/AI 작업 통합) ----------
class Case(TimeStampedModel):

    missing_person = models.ForeignKey(
        MissingPerson,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="cases"
    )

    reported_missing_name = models.CharField(
        max_length=100,
        null=True,
        blank=True
    )

    class TypeCode(models.TextChoices):
        MISSING = "missing", "missing"
        REPORT = "report", "report"
        TIP = "tip", "tip"
        MONTAGE = "montage", "montage"  # 🔥 추가

    class Status(models.TextChoices):
        RECEIVED = "received", "접수중"
        REVIEWING = "reviewing", "확인중"
        COMPLETED = "completed", "완료"
        REJECTED="rejected","거부"

    person = models.ForeignKey(
        Person,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="related_cases"
    )

    reporter = models.ForeignKey(
        Person,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="reported_cases"
    )

    type_code = models.CharField(
        max_length=10,
        choices=TypeCode.choices,
        db_index=True
    )

    occr_date = models.DateTimeField(null=True, blank=True)
    occr_location = models.CharField(max_length=200, null=True, blank=True)

    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.RECEIVED,
        db_index=True
    )

    description = models.TextField()
    payload = models.JSONField(null=True, blank=True)
    def __str__(self):
        return f"Case#{self.pk}({self.type_code})"

# ---------- Feature (신체/행동 특이사항) ----------
class Feature(TimeStampedModel):
    class AISource(models.TextChoices):
        RULE = "rule", "rule"
        KOBERT = "kobert", "kobert"
        MANUAL = "manual", "manual"

    case = models.ForeignKey(Case, on_delete=models.CASCADE, related_name="features")
    clothing = models.TextField(null=True, blank=True)
    physical = models.TextField(null=True, blank=True)
    health = models.TextField(null=True, blank=True)
    behavior = models.TextField(null=True, blank=True)
    etc = models.TextField(null=True, blank=True)

    ai_source = models.CharField(max_length=10, choices=AISource.choices, default=AISource.MANUAL)
    confidence = models.FloatField(
        validators=[MinValueValidator(0.0), MaxValueValidator(1.0)],
        default=0.0,
        help_text="0.0~1.0 (명세에 % 기재 있으나 서비스단에서 변환 추천)"
    )

    def __str__(self):
        return f"Feature#{self.pk} of Case#{self.case_id}"


# ---------- Montage (AI 몽타주 결과) ----------
class Montage(TimeStampedModel):
    case = models.ForeignKey(
        "Case",
        on_delete=models.CASCADE,
        related_name="montages",
        null=True,
        blank=True
    )
    missing_person = models.ForeignKey(
        MissingPerson,
        on_delete=models.CASCADE,
        related_name="montages",
        null=True,  # 👈 일단 허용
        blank=True
    )

    generated_by = models.ForeignKey(
        Person,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="generated_montages"
    )

    result_img = models.ImageField(
        upload_to="montage/result/",
        null=True,
        blank=True
    )
    age_estimate = models.IntegerField(null=True, blank=True)

    confidence = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        null=True,
        blank=True,
        validators=[MinValueValidator(0), MaxValueValidator(100)]
    )

    is_applied = models.BooleanField(default=False)

    def __str__(self):
        return f"Montage#{self.pk} for {self.missing_person_id}"


# ---------- Montage Input Photos ----------
class MontageInputPhoto(TimeStampedModel):

    montage = models.ForeignKey(
        Montage,
        on_delete=models.CASCADE,
        related_name="input_photos"
    )

    image = models.ImageField(upload_to="montage/input/")

    def __str__(self):
        return f"InputPhoto#{self.pk} for Montage#{self.montage_id}"

# ---------- Interaction (통화/알림/NFC 이벤트) ----------
class Interaction(TimeStampedModel):
    class Type(models.TextChoices):
        VOICE_CALL = "voice_call", "voice_call"
        VIDEO_CALL = "video_call", "video_call"
        ALERT = "alert", "alert"
        NFC_TAG = "nfc_tag", "nfc_tag"

    class Result(models.TextChoices):
        SUCCESS = "success", "success"
        MISSED = "missed", "missed"
        FAILED = "failed", "failed"

    from_person = models.ForeignKey(Person, on_delete=models.SET_NULL, null=True, blank=True,
                                    related_name="outgoing_interactions")
    to_person = models.ForeignKey(Person, on_delete=models.SET_NULL, null=True, blank=True,
                                  related_name="incoming_interactions")
    type = models.CharField(max_length=12, choices=Type.choices, db_index=True)
    start_time = models.DateTimeField()
    end_time = models.DateTimeField(null=True, blank=True)
    location = models.CharField(max_length=200, null=True, blank=True)
    result = models.CharField(max_length=10, choices=Result.choices, null=True, blank=True)

    def __str__(self):
        return f"{self.type} {self.from_person_id}->{self.to_person_id}"

    class Meta:
        indexes = [
            models.Index(fields=["type", "start_time"]),
            models.Index(fields=["from_person", "to_person"]),
        ]


# ---------- Log (시스템 활동 로그) ----------
class Log(models.Model):
    class TargetType(models.TextChoices):
        CASE = "case", "case"
        USER = "user", "user"
        DEVICE = "device", "device"
        AI = "ai", "ai"
        SYSTEM = "system", "system"

    user = models.ForeignKey(Person, on_delete=models.SET_NULL, null=True, blank=True, related_name="logs")
    action = models.CharField(max_length=100)
    target_type = models.CharField(max_length=50)
    target_id = models.IntegerField(null=True, blank=True)
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True)

    def __str__(self):
        return f"[{self.timestamp}] {self.user_id} {self.action} -> {self.target_type}:{self.target_id}"

    class Meta:
        indexes = [
            models.Index(fields=["target_type", "target_id"]),
        ]

# models.py

class ProtectedPerson(models.Model):
    """안전Dream '보호하고 있어요' 보호중 실종자 정보"""
    class Source(models.TextChoices):
        SAFE182 = "safe182", "safe182"
        USER = "user", "user"

    source = models.CharField(
        max_length=20,
        choices=Source.choices,
        default=Source.SAFE182
    )
    class Status(models.TextChoices):
        PROTECTING = "protecting", "보호중"
        RETURNED = "returned", "인계완료"  # MissingPerson의 FOUND에 해당
    # 식별자
    msspsn_idntfccd = models.CharField(
        max_length=20,
        unique=True,
        verbose_name="실종자식별코드",
        help_text="safe182 고유 식별코드 (예: 5647061)",
        default="",
    )

    # 기본 신상정보
    name = models.CharField(max_length=50, verbose_name="이름", default="")
    gender = models.CharField(
        max_length=10,
        verbose_name="성별",
        choices=[("남자", "남자"), ("여자", "여자")],
        blank=True,
        default="",
    )
    category = models.CharField(
        max_length=50,
        verbose_name="분류",
        help_text="아동, 장애, 치매환자, 가출인 등",
        blank=True,
        default="",
    )
    nationality = models.CharField(max_length=20, verbose_name="국적", blank=True, default="")

    # 나이
    age_at_missing = models.IntegerField(verbose_name="당시나이(세)", null=True, blank=True)
    current_age = models.IntegerField(verbose_name="현재나이(세)", null=True, blank=True)

    # 발생정보
    occurred_at = models.DateField(verbose_name="발생일시", null=True, blank=True)
    occurred_location = models.CharField(max_length=200, verbose_name="발생장소", blank=True, default="")

    # 신체정보
    height = models.CharField(max_length=10, verbose_name="키", blank=True, default="")
    weight = models.CharField(max_length=10, verbose_name="몸무게", blank=True, default="")
    body_type = models.CharField(max_length=20, verbose_name="체격", blank=True, default="")
    face_type = models.CharField(max_length=20, verbose_name="얼굴형", blank=True, default="")
    hair_color = models.CharField(max_length=20, verbose_name="두발색상", blank=True, default="")
    hair_style = models.CharField(max_length=50, verbose_name="두발형태", blank=True, default="")
    clothing = models.CharField(max_length=200, verbose_name="착의의상", blank=True, default="")

    # 진행상태
    status = models.CharField(max_length=20, verbose_name="진행상태", blank=True, default="")

    # 이미지 URL 목록 (JSON 배열로 저장)
    image_urls = models.JSONField(verbose_name="이미지URL목록", default=list, blank=True)

    # 크롤링 메타
    crawled_at = models.DateTimeField(default=timezone.now, verbose_name="크롤링일시", editable=False)
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시")
    # 🔥 AI 분류 캐시 필드 추가
    etc_ai_category = models.CharField(
        max_length=20,
        null=True,
        blank=True,
        help_text="AI 분류 결과: 신체특징 / 착의외형 / 건강장애 / 기타참고"
    )
    etc_ai_confidence = models.FloatField(
        null=True,
        blank=True,
        help_text="AI 분류 신뢰도 0.0~1.0"
    )
    class Meta:
        db_table = "safe182_protected_person"
        verbose_name = "보호중 실종자"
        verbose_name_plural = "보호중 실종자 목록"
        ordering = ["-occurred_at"]

    def __str__(self):
        return f"{self.name}({self.current_age}세) - {self.msspsn_idntfccd}"

class ProtectedPersonPhoto(models.Model):
    person = models.ForeignKey(
        ProtectedPerson,
        on_delete=models.CASCADE,
        related_name="photos"
    )
    image_url = models.TextField()

    is_main = models.BooleanField(default=False)

class TipPhoto(models.Model):
    """
    신고 / 시민 제보 사진

    photo_type
    - subject       : 실종 대상자 / 제보 사진
    - parent1_face  : 가족 사진 1
    - parent2_face  : 가족 사진 2
    """

    class PhotoType(models.TextChoices):
        SUBJECT = "subject", "대상자 사진"
        PARENT1_FACE = "parent1_face", "가족 사진 1"
        PARENT2_FACE = "parent2_face", "가족 사진 2"

    case = models.ForeignKey(
        Case,
        on_delete=models.CASCADE,
        related_name="photos"
    )

    image = models.ImageField(
        upload_to=tip_photo_upload_path
    )

    uploaded_at = models.DateTimeField(
        auto_now_add=True
    )

    # AI로 생성된 이미지인지 여부
    is_ai_generated = models.BooleanField(
        default=False
    )

    # 사진 종류
    photo_type = models.CharField(
        max_length=20,
        choices=PhotoType.choices,
        default=PhotoType.SUBJECT,
        db_index=True,
        help_text=(
            "subject=대상자 사진, "
            "parent1_face=가족 사진 1, "
            "parent2_face=가족 사진 2"
        )
    )

    def __str__(self):
        return (
            f"TipPhoto "
            f"Case#{self.case_id} "
            f"[{self.photo_type}]"
        )

    class Meta:
        db_table = "dasibomapp_tip_photo"
        verbose_name = "신고/제보 사진"
        verbose_name_plural = "신고/제보 사진 목록"


class CaseReport(models.Model):
    case = models.ForeignKey(
        Case,
        on_delete=models.CASCADE,
        related_name="reports"
    )

    reporter = models.ForeignKey(
        Person,
        on_delete=models.SET_NULL,
        null=True,
        blank=True
    )

    reason = models.TextField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)

    resolved = models.BooleanField(default=False)

class PreventionRegistration(TimeStampedModel):
    """
    실종 예방 등록 정보
    """

    class Category(models.TextChoices):
        CHILD = "010", "정상아동 (18세 미만)"
        RUNAWAY = "020", "가출인"
        UNIDENTIFIED_FACILITY = "040", "시설 보호 무연고자"
        INTELLECTUAL_DISABLED = "060", "지적장애인"
        INTELLECTUAL_DISABLED_CHILD = "061", "지적장애인 (18세 미만)"
        INTELLECTUAL_DISABLED_ADULT = "062", "지적장애인 (18세 이상)"
        DEMENTIA = "070", "치매 질환자"
        OTHER = "080", "불상 (기타)"
    class Gender(models.TextChoices):
        MALE = "남자", "남자"
        FEMALE = "여자", "여자"
        UNKNOWN = "알 수 없음", "알 수 없음"

    linked_person = models.ForeignKey(
        Person,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="linked_prevention_registrations"
    )
    device_code = models.CharField(
        max_length=100,
        null=True,
        blank=True,
        help_text="피보호자에게 연결할 GPS/NFC 기기 코드"
    )
    # ✅ 추가: 제보/신고와 같은 상태 흐름
    class Status(models.TextChoices):
        RECEIVED = "received", "접수중"
        REVIEWING = "reviewing", "확인중"
        COMPLETED = "completed", "등록 완료"
        REJECTED = "rejected", "거절됨"

    owner = models.ForeignKey(
        Person,
        on_delete=models.CASCADE,
        related_name="prevention_registrations",
        help_text="등록한 사용자"
    )

    name = models.CharField(max_length=50)

    gender = models.CharField(
        max_length=20,
        choices=Gender.choices,
        default=Gender.UNKNOWN
    )
    category = models.CharField(
        max_length=3,
        choices=Category.choices,
        blank=True,
        default="",
        verbose_name="분류",
        help_text="아동, 장애, 치매환자, 가출인 등",
    )
    rrn_front = models.CharField(max_length=6, null=True, blank=True)
    rrn_back = models.CharField(max_length=7, null=True, blank=True)

    phone = models.CharField(max_length=20, null=True, blank=True)
    address = models.CharField(max_length=255, null=True, blank=True)
    frequent_place = models.CharField(max_length=255, null=True, blank=True)
    note = models.TextField(null=True, blank=True)

    height = models.CharField(max_length=30, default="알 수 없음")
    weight = models.CharField(max_length=30, default="알 수 없음")
    body_type = models.CharField(max_length=30, default="알 수 없음")
    face_type = models.CharField(max_length=30, default="알 수 없음")
    hair_color = models.CharField(max_length=30, default="알 수 없음")
    hair_style = models.CharField(max_length=30, default="알 수 없음")
    blood_type = models.CharField(max_length=30, default="알 수 없음")
    eye_color = models.CharField(max_length=30, default="알 수 없음")

    physical_feature = models.TextField(null=True, blank=True)
    health_info = models.TextField(null=True, blank=True)

    guardian_name = models.CharField(max_length=50)
    guardian_rrn_front = models.CharField(max_length=6, null=True, blank=True)
    guardian_rrn_back = models.CharField(max_length=7, null=True, blank=True)
    guardian_phone = models.CharField(max_length=20)

    privacy_agreed = models.BooleanField(default=False)
    phone_verified = models.BooleanField(default=False)

    # ✅ 추가: 상태 관리
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.RECEIVED,
        db_index=True,
    )

    # ✅ 추가: 거절 사유
    rejected_reason = models.TextField(null=True, blank=True)

    # ✅ 추가: 관리자 처리 정보
    reviewed_by = models.ForeignKey(
        Person,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="reviewed_prevention_registrations",
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)

    is_active = models.BooleanField(default=True)

    def __str__(self):
        return f"PreventionRegistration#{self.pk} - {self.name}"

    class Meta:
        indexes = [
            models.Index(fields=["owner"]),
            models.Index(fields=["status"]),
            models.Index(fields=["is_active"]),
            models.Index(fields=["created_at"]),
        ]
class PreventionPhoto(TimeStampedModel):
    class PhotoType(models.TextChoices):
        FACE = "face", "등록 대상자 정면 사진"
        FULL_BODY = "full_body", "등록 대상자 전신 사진"
        LEFT_SIDE = "left_side", "등록 대상자 왼쪽 측면 사진"
        RIGHT_SIDE = "right_side", "등록 대상자 오른쪽 측면 사진"
        PARENT1_FACE = "parent1_face", "부모님 정면 사진 1"
        PARENT2_FACE = "parent2_face", "부모님 정면 사진 2"

    registration = models.ForeignKey(
        PreventionRegistration,
        on_delete=models.CASCADE,
        related_name="photos"
    )

    photo_type = models.CharField(
        max_length=30,
        choices=PhotoType.choices
    )

    image = models.ImageField(upload_to="prevention/photos/")

    is_validated = models.BooleanField(default=False)

    validation_status = models.CharField(
        max_length=20,
        default="unchecked",
        help_text="unchecked / valid / warning / invalid / error"
    )

    validation_message = models.CharField(
        max_length=255,
        null=True,
        blank=True
    )

    validation_confidence = models.FloatField(
        null=True,
        blank=True
    )

    def __str__(self):
        return f"{self.photo_type} for prevention#{self.registration_id}"
class EmergencyReport(TimeStampedModel):
    """
    키오스크/하드웨어 긴급신고 기록
    """

    device = models.ForeignKey(
        "Device",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="emergency_reports",
        help_text="DB에 등록된 기기 정보"
    )

    device_code = models.CharField(
        max_length=100,
        db_index=True,
        help_text="하드웨어에서 전달한 기기 ID"
    )

    reported_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text="하드웨어에서 전달한 신고 발생 시각"
    )

    def __str__(self):
        return f"EmergencyReport({self.device_code})"

class DeviceLocationLog(TimeStampedModel):
    """
    키오스크/하드웨어 위치 공유 기록
    """

    device = models.ForeignKey(
        "Device",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="location_logs",
        help_text="DB에 등록된 기기 정보"
    )

    device_code = models.CharField(
        max_length=100,
        db_index=True,
        help_text="하드웨어에서 전달한 기기 ID"
    )

    lat = models.FloatField(help_text="위도")
    lng = models.FloatField(help_text="경도")

    shared_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text="하드웨어에서 전달한 위치 공유 시각"
    )

    def __str__(self):
        return f"DeviceLocationLog({self.device_code}, {self.lat}, {self.lng})"
class GPSLocation(models.Model):
    """
    ESP32 / 키오스크 기기별 최신 GPS 좌표 저장 모델

    device_id별로 최신 좌표 1개만 유지한다.
    같은 device_id로 POST 요청이 오면 기존 데이터를 덮어쓴다.
    """

    device = models.ForeignKey(
        "Device",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="gps_locations"
    )

    device_code = models.CharField(
        max_length=100,
        unique=True,
        db_index=True
    )

    lat = models.FloatField()
    lng = models.FloatField()

    timestamp = models.DateTimeField()

    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.device_id} - {self.lat}, {self.lng}"
class GPSLocationHistory(models.Model):
    """
    기기별 GPS 위치 이력

    GPSLocation은 최신 위치 1건만 유지하고,
    이 모델은 device_code별로 2시간 간격 위치를 누적 저장한다.
    """

    device = models.ForeignKey(
        "Device",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="gps_history"
    )

    device_code = models.CharField(
        max_length=100,
        db_index=True
    )

    lat = models.FloatField()
    lng = models.FloatField()

    timestamp = models.DateTimeField(
        db_index=True
    )

    created_at = models.DateTimeField(
        auto_now_add=True
    )

    def __str__(self):
        return (
            f"{self.device_code} - "
            f"{self.lat}, {self.lng} - "
            f"{self.timestamp}"
        )

    class Meta:
        ordering = ["-timestamp"]
        indexes = [
            models.Index(
                fields=["device_code", "timestamp"]
            ),
        ]

