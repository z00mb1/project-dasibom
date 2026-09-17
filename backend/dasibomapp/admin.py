from django.contrib import admin
from django.contrib.auth.hashers import make_password

from dasibomapp.models import (
    Person,
    UserAuth,
    Guardian,
    MissingPerson,
    Device,
    Case,
    Feature,
    Montage,
    MontageInputPhoto,
    Interaction,
    Log,
    ProtectedPerson,
    PreventionRegistration,
    PreventionPhoto,
    EmergencyReport,
    DeviceLocationLog,
    GPSLocation,
)


admin.site.register(Person)
admin.site.register(Guardian)
admin.site.register(MissingPerson)
admin.site.register(Device)
admin.site.register(Case)
admin.site.register(Feature)
admin.site.register(Interaction)
admin.site.register(Log)


class MontageInputPhotoInline(admin.TabularInline):
    model = MontageInputPhoto
    extra = 0
    readonly_fields = ("image", "created_at", "updated_at")


@admin.register(Montage)
class MontageAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "case",
        "missing_person",
        "generated_by",
        "age_estimate",
        "confidence",
        "is_applied",
        "created_at",
    )

    list_filter = (
        "is_applied",
        "created_at",
        "updated_at",
    )

    search_fields = (
        "id",
        "case__reported_missing_name",
        "missing_person__name",
        "generated_by__name",
    )

    readonly_fields = (
        "created_at",
        "updated_at",
    )

    ordering = ("-created_at",)

    inlines = [MontageInputPhotoInline]


@admin.register(MontageInputPhoto)
class MontageInputPhotoAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "montage",
        "image",
        "created_at",
    )

    search_fields = (
        "id",
        "montage__id",
    )

    readonly_fields = (
        "created_at",
        "updated_at",
    )

    ordering = ("-created_at",)


@admin.register(ProtectedPerson)
class ProtectedPersonAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "name",
        "gender",
        "current_age",
        "category",
        "status",
        "occurred_location",
        "occurred_at",
        "crawled_at",
    )

    list_filter = (
        "gender",
        "category",
        "status",
        "nationality",
    )

    search_fields = (
        "name",
        "msspsn_idntfccd",
        "occurred_location",
        "clothing",
    )

    ordering = ("-occurred_at",)


class PreventionPhotoInline(admin.TabularInline):
    model = PreventionPhoto
    extra = 0

    fields = (
        "photo_type",
        "image",
        "is_validated",
        "validation_status",
        "validation_message",
        "validation_confidence",
        "created_at",
        "updated_at",
    )

    readonly_fields = (
        "created_at",
        "updated_at",
    )


@admin.register(PreventionRegistration)
class PreventionRegistrationAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "name",
        "gender",
        "status",
        "is_active",
        "guardian_name",
        "guardian_phone",
        "phone_verified",
        "privacy_agreed",
        "reviewed_by",
        "reviewed_at",
        "created_at",
    )

    list_filter = (
        "status",
        "gender",
        "is_active",
        "phone_verified",
        "privacy_agreed",
        "created_at",
        "reviewed_at",
    )

    search_fields = (
        "name",
        "phone",
        "address",
        "frequent_place",
        "guardian_name",
        "guardian_phone",
        "physical_feature",
        "health_info",
    )

    readonly_fields = (
        "created_at",
        "updated_at",
        "reviewed_at",
    )

    ordering = ("-created_at",)

    fieldsets = (
        ("등록 상태", {
            "fields": (
                "owner",
                "status",
                "is_active",
                "rejected_reason",
                "reviewed_by",
                "reviewed_at",
            )
        }),
        ("등록 대상자 기본 정보", {
            "fields": (
                "name",
                "gender",
                "rrn_front",
                "rrn_back",
                "phone",
                "address",
                "frequent_place",
                "note",
            )
        }),
        ("신체 정보", {
            "fields": (
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
            )
        }),
        ("보호자 정보", {
            "fields": (
                "guardian_name",
                "guardian_rrn_front",
                "guardian_rrn_back",
                "guardian_phone",
                "privacy_agreed",
                "phone_verified",
            )
        }),
        ("시간 정보", {
            "fields": (
                "created_at",
                "updated_at",
            )
        }),
    )

    inlines = [PreventionPhotoInline]


@admin.register(PreventionPhoto)
class PreventionPhotoAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "registration",
        "photo_type",
        "image",
        "is_validated",
        "validation_status",
        "validation_confidence",
        "created_at",
    )

    list_filter = (
        "photo_type",
        "is_validated",
        "validation_status",
        "created_at",
    )

    search_fields = (
        "id",
        "registration__name",
        "registration__guardian_name",
        "registration__guardian_phone",
    )

    readonly_fields = (
        "created_at",
        "updated_at",
    )

    ordering = ("-created_at",)


@admin.register(EmergencyReport)
class EmergencyReportAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "device_code",
        "device",
        "reported_at",
        "created_at",
    )

    list_filter = (
        "reported_at",
        "created_at",
    )

    search_fields = (
        "device_code",
        "device__id",
    )

    readonly_fields = (
        "created_at",
        "updated_at",
    )

    ordering = ("-created_at",)


@admin.register(DeviceLocationLog)
class DeviceLocationLogAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "device_code",
        "device",
        "lat",
        "lng",
        "shared_at",
        "created_at",
    )

    list_filter = (
        "shared_at",
        "created_at",
    )

    search_fields = (
        "device_code",
        "device__id",
    )

    readonly_fields = (
        "created_at",
        "updated_at",
    )

    ordering = ("-created_at",)


@admin.register(GPSLocation)
class GPSLocationAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "device_code",
        "device",
        "lat",
        "lng",
        "timestamp",
        "updated_at",
    )

    list_filter = (
        "timestamp",
        "updated_at",
    )

    search_fields = (
        "device_code",
        "device__id",
        "device__device_uid",
    )

    readonly_fields = (
        "updated_at",
    )

    ordering = ("-updated_at",)


@admin.register(UserAuth)
class UserAuthAdmin(admin.ModelAdmin):

    def save_model(self, request, obj, form, change):
        if obj.password and not obj.password.startswith("pbkdf2_"):
            obj.password = make_password(obj.password)

        super().save_model(request, obj, form, change)