from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.exceptions import AuthenticationFailed
from django.core.cache import cache
from .models import UserAuth
import logging

logger = logging.getLogger(__name__)


class CustomJWTAuthentication(JWTAuthentication):

    def authenticate(self, request):
        header = self.get_header(request)
        if header is None:
            logger.warning("헤더 없음")
            return None

        raw_token = self.get_raw_token(header)
        if raw_token is None:
            logger.warning("raw_token 없음")
            return None

        # 블랙리스트 체크
        token_str = raw_token.decode()
        if cache.get(f"blacklist_{token_str}"):
            logger.warning("블랙리스트 토큰")
            raise AuthenticationFailed("블랙리스트 토큰")

        try:
            validated_token = self.get_validated_token(raw_token)
        except Exception as e:
            logger.warning(f"토큰 검증 실패: {e}")
            raise

        user_id = validated_token.get("user_id")
        logger.warning(f"user_id: {user_id}")

        try:
            user = UserAuth.objects.get(id=user_id)
        except UserAuth.DoesNotExist:
            raise AuthenticationFailed("유저 없음")

        return (user, validated_token)