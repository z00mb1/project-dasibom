import os
from io import BytesIO
from pathlib import Path

import cloudinary
import cloudinary.uploader
import cloudinary.utils
import requests

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import Storage


def _normalize_name(name: str) -> str:
    """
    DB에는 항상 media 기준 상대경로만 유지.

    예:
        /media/missing_persons/123/0.jpg
        media/missing_persons/123/0.jpg
        missing_persons\\123\\0.jpg

    모두:
        missing_persons/123/0.jpg
    """
    if not name:
        return ""

    name = str(name).replace("\\", "/")

    if name.startswith("/media/"):
        name = name[len("/media/"):]

    elif name.startswith("media/"):
        name = name[len("media/"):]

    return name.lstrip("/")


def _cloudinary_info(name: str):
    """
    DB 상대경로를 Cloudinary public_id + format으로 변환.

    missing_persons/123/0.jpg
        ↓
    public_id = missing_persons/123/0
    format = jpg
    """
    normalized = _normalize_name(name)

    path = Path(normalized)

    suffix = path.suffix.lower()

    if suffix:
        image_format = suffix.lstrip(".")
        public_id = path.with_suffix("").as_posix()
    else:
        image_format = None
        public_id = path.as_posix()

    if image_format == "jpeg":
        image_format = "jpg"

    return public_id, image_format


class UniversalMediaStorage(Storage):
    """
    local / cloudinary / both를 환경변수만으로 전환하는 Storage.

    MEDIA_WRITE_MODE
        local
        cloudinary
        both

    MEDIA_READ_MODE
        local
        cloudinary
    """

    def __init__(self, *args, **kwargs):
        super().__init__()

    @property
    def write_mode(self):
        mode = os.getenv(
            "MEDIA_WRITE_MODE",
            "local",
        ).lower().strip()

        if mode not in {
            "local",
            "cloudinary",
            "both",
        }:
            return "local"

        return mode

    @property
    def read_mode(self):
        mode = os.getenv(
            "MEDIA_READ_MODE",
            "local",
        ).lower().strip()

        if mode not in {
            "local",
            "cloudinary",
        }:
            return "local"

        return mode

    # --------------------------------------------------
    # 파일명 자동 변경 방지
    # --------------------------------------------------

    def get_available_name(
        self,
        name,
        max_length=None,
    ):
        """
        0.jpg → 0_abcd.jpg처럼 바뀌지 않고
        기존 경로 그대로 사용.
        """
        return _normalize_name(name)

    # --------------------------------------------------
    # 저장
    # --------------------------------------------------

    def _save(self, name, content):
        name = _normalize_name(name)

        try:
            content.seek(0)
        except Exception:
            pass

        data = content.read()

        # ==============================================
        # LOCAL
        # ==============================================

        if self.write_mode in {
            "local",
            "both",
        }:
            local_path = (
                Path(settings.MEDIA_ROOT)
                / name
            )

            local_path.parent.mkdir(
                parents=True,
                exist_ok=True,
            )

            with open(
                local_path,
                "wb",
            ) as f:
                f.write(data)

        # ==============================================
        # CLOUDINARY
        # ==============================================

        if self.write_mode in {
            "cloudinary",
            "both",
        }:
            public_id, image_format = (
                _cloudinary_info(name)
            )

            options = {
                "public_id": public_id,
                "overwrite": True,
                "resource_type": "image",
            }

            if image_format:
                options["format"] = image_format

            cloudinary.uploader.upload(
                data,
                **options,
            )

        return name

    # --------------------------------------------------
    # URL
    # --------------------------------------------------

    def url(self, name):
        if not name:
            return None

        name = str(name)

        # 이미 외부 URL이면 그대로
        if name.startswith(
            ("http://", "https://")
        ):
            return name

        name = _normalize_name(name)

        # ==============================================
        # CLOUDINARY URL
        # ==============================================

        if self.read_mode == "cloudinary":
            public_id, image_format = (
                _cloudinary_info(name)
            )

            options = {
                "secure": True,
                "resource_type": "image",
            }

            if image_format:
                options["format"] = image_format

            url, _ = (
                cloudinary.utils.cloudinary_url(
                    public_id,
                    **options,
                )
            )

            return url

        # ==============================================
        # LOCAL URL
        # ==============================================

        media_url = settings.MEDIA_URL.rstrip("/")

        return (
            f"{media_url}/{name}"
        )

    # --------------------------------------------------
    # 존재 여부
    # --------------------------------------------------

    def exists(self, name):
        name = _normalize_name(name)

        local_path = (
            Path(settings.MEDIA_ROOT)
            / name
        )

        if local_path.exists():
            return True

        # Cloudinary 존재 여부를 매번 API 조회하면
        # rate limit을 먹으므로 조회하지 않는다.
        return False

    # --------------------------------------------------
    # 파일 읽기
    # --------------------------------------------------

    def _open(
        self,
        name,
        mode="rb",
    ):
        name = _normalize_name(name)

        local_path = (
            Path(settings.MEDIA_ROOT)
            / name
        )

        # 로컬 파일이 있으면 로컬 우선
        if local_path.exists():
            return open(
                local_path,
                mode,
            )

        # 로컬에 없고 Cloudinary에만 있는 경우
        url = self.url(name)

        response = requests.get(
            url,
            timeout=30,
        )

        response.raise_for_status()

        return ContentFile(
            response.content,
            name=Path(name).name,
        )

    # --------------------------------------------------
    # 삭제
    # --------------------------------------------------

    def delete(self, name):
        name = _normalize_name(name)

        # LOCAL
        local_path = (
            Path(settings.MEDIA_ROOT)
            / name
        )

        if local_path.exists():
            try:
                local_path.unlink()
            except Exception:
                pass

        # CLOUDINARY
        public_id, _ = (
            _cloudinary_info(name)
        )

        try:
            cloudinary.uploader.destroy(
                public_id,
                resource_type="image",
                invalidate=True,
            )
        except Exception:
            pass

    # --------------------------------------------------
    # 크기
    # --------------------------------------------------

    def size(self, name):
        name = _normalize_name(name)

        local_path = (
            Path(settings.MEDIA_ROOT)
            / name
        )

        if local_path.exists():
            return local_path.stat().st_size

        return 0

def media_url(
    path,
    request=None,
):
    """
    어떤 저장소를 쓰든 API에서 사용할 URL을 생성.

    Cloudinary:
        https://res.cloudinary.com/...

    local:
        http://127.0.0.1:8000/media/...
        또는
        https://zrok주소/media/...
    """

    if not path:
        return None

    path = str(path)

    if path.startswith(
        ("http://", "https://")
    ):
        return path

    storage = UniversalMediaStorage()

    url = storage.url(path)

    # Cloudinary는 이미 절대 URL
    if url.startswith(
        ("http://", "https://")
    ):
        return url

    # local이면 request의 host를 붙임
    if request:
        return request.build_absolute_uri(url)

    return url