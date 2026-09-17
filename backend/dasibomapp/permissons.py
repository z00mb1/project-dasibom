from rest_framework.permissions import BasePermission


class IsAuthenticatedUser(BasePermission):
    """로그인한 사용자만"""

    def has_permission(self, request, view):
        return (
            request.user
            and request.user.is_authenticated
        )


class IsAdmin(BasePermission):
    """관리자 전용"""

    def has_permission(self, request, view):
        return (
            request.user
            and request.user.is_authenticated
            and request.user.role == "admin"
        )


class IsGuardian(BasePermission):
    """보호자 전용"""

    def has_permission(self, request, view):
        return (
            request.user
            and request.user.is_authenticated
            and request.user.role == "guardian"
        )


class IsCitizen(BasePermission):
    """일반 시민 전용"""

    def has_permission(self, request, view):
        return (
            request.user
            and request.user.is_authenticated
            and request.user.role == "citizen"
        )


class IsNotGuest(BasePermission):
    """Guest만 차단"""

    def has_permission(self, request, view):
        return (
            request.user
            and request.user.is_authenticated
            and request.user.role != "guest"
        )