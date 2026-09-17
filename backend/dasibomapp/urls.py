# dasibomapp/urls.py

from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import *

from django.conf import settings
from django.conf.urls.static import static


router = DefaultRouter()

router.register(r"person", PersonViewSet)
router.register(r"userauth", UserAuthViewSet)
router.register(r"guardian", GuardianViewSet)
router.register(r"device", DeviceViewSet)
router.register(r"case", CaseViewSet)
router.register(r"feature", FeatureViewSet)
router.register(r"log", LogViewSet)
router.register(r"montage", MontageViewSet)
router.register(r"interaction", InteractionViewSet)

router.register(
    r"phoneauth",
    PhoneAuthViewSet,
    basename="phoneauth"
)

router.register(
    r"missingperson",
    MissingPersonViewSet,
    basename="missingperson"
)

router.register(
    r"protectedperson",
    ProtectedPersonViewSet,
    basename="protectedperson"
)

router.register(
    r"report",
    ReportViewSet,
    basename="report"
)

router.register(
    r"admin/users",
    AdminUserViewSet,
    basename="admin-users"
)

router.register(
    r"admin/logs",
    LogViewSet,
    basename="admin-logs"
)

router.register(
    r"prevention-registrations",
    PreventionRegistrationViewSet,
    basename="prevention-registration"
)


urlpatterns = [
    path(
        "facilities/",
        FacilityListAPIView.as_view()
    ),

    path(
        "ai/aging/",
        AIAgingAPIView.as_view(),
        name="ai-aging"
    ),

    # 하드웨어 / 키오스크 연동 API
    path(
        "emergency/",
        EmergencyReportAPIView.as_view(),
        name="emergency-report"
    ),

    path(
        "location/",
        DeviceLocationAPIView.as_view(),
        name="device-location"
    ),

    path(
        "gps/",
        GPSLocationAPIView.as_view(),
        name="gps-location"
    ),

    path(
        "gps/latest/",
        GPSLatestAPIView.as_view(),
        name="gps-latest"
    ),
    path(
        "gps/history/",
        GPSHistoryAPIView.as_view(),
        name="gps-history"
    ),

    path(
        "notifications/",
        NotificationListAPIView.as_view()
    ),

    path(
        "guardian/tag-logs/",
        GuardianTagLogAPIView.as_view()
    ),

    path(
        "ping/",
        PingAPIView.as_view(),
        name="ping"
    ),

    path(
        "",
        include(router.urls)
    ),
]


# ==============================
# Static
# ==============================

urlpatterns += static(
    settings.STATIC_URL,
    document_root=settings.STATIC_ROOT
)


# ==============================
# Local Media
# ==============================
#
# Cloudinary 조회 모드에서는
# /media/ URL을 Django가 직접 서빙할 필요 없음.
#
# local 모드일 때만
# /media/... → MEDIA_ROOT 연결
#
# MEDIA_READ_MODE=local
#   → zrok / 로컬 개발 서버에서 media 제공
#
# MEDIA_READ_MODE=cloudinary
#   → Cloudinary URL 사용
# ==============================

if getattr(
    settings,
    "MEDIA_READ_MODE",
    "local"
) == "local":

    urlpatterns += static(
        settings.MEDIA_URL,
        document_root=settings.MEDIA_ROOT
    )