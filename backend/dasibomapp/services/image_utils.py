import base64
from django.core.files.base import ContentFile
import uuid

def base64_to_image(base64_str, prefix="missing"):
    """
    Base64 문자열 → Django ImageFile
    """
    if not base64_str:
        return None

    # 혹시 header 붙어 있으면 제거
    if "," in base64_str:
        base64_str = base64_str.split(",")[1]

    try:
        decoded = base64.b64decode(base64_str)
    except Exception:
        return None

    filename = f"{prefix}_{uuid.uuid4().hex}.jpg"
    return ContentFile(decoded, name=filename)
