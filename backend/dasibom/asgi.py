"""
ASGI config for dasibom project.

HTTP 요청과 WebSocket 요청을 함께 처리하기 위한 ASGI 설정 파일입니다.
"""

import os

from django.core.asgi import get_asgi_application
from django.contrib.staticfiles.handlers import ASGIStaticFilesHandler

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "dasibom.settings")

# Django 기본 HTTP ASGI application
django_asgi_app = get_asgi_application()

# WebSocket 처리를 위한 Channels import
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack

import dasibomapp.routing

application = ProtocolTypeRouter({
    # 일반 HTTP API 요청 + static/admin CSS 처리
    "http": ASGIStaticFilesHandler(django_asgi_app),

    # WebSocket 요청 처리
    "websocket": AuthMiddlewareStack(
        URLRouter(
            dasibomapp.routing.websocket_urlpatterns
        )
    ),
})