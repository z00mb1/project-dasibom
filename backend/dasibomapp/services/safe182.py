import requests
from datetime import datetime
from django.conf import settings
from dasibomapp.models import MissingPerson, MissingPersonPhoto
from dasibomapp.services.image_utils import base64_to_image

SAFE182_URL = "https://www.safe182.go.kr/api/lcm/findChildList.do"


def parse_yyyymmdd(value):
    try:
        return datetime.strptime(value, "%Y%m%d").date()
    except Exception:
        return None


def sync_safe182_missing_persons(page=1, page_size=100):
    """
    Safe182 OpenAPI (JSON) → MissingPerson + MissingPersonPhoto 동기화
    - Base64 사진은 즉시 ImageField로 변환하여 저장
    """

    payload = {
        "esntlId": settings.SAFE182_USER_ID,
        "authKey": settings.SAFE182_API_KEY,
        "rowSize": page_size,
        "page": page,
    }

    response = requests.post(SAFE182_URL, data=payload, timeout=10)
    response.raise_for_status()

    data = response.json()
    rows = data.get("list", [])

    results = {"created": 0, "updated": 0}

    for row in rows:
        # Safe182 고유 PK가 없어서 seq 직접 구성
        seq = f"safe182-{row.get('rnum')}-{row.get('occrde')}"

        defaults = {
            "name": row.get("nm"),
            "gender": (
                "male" if row.get("sexdstnDscd") == "남자"
                else "female" if row.get("sexdstnDscd") == "여자"
                else "unknown"
            ),
            "age": row.get("age"),
            "current_age": int(row["ageNow"]) if row.get("ageNow") else None,
            "missing_date": parse_yyyymmdd(row.get("occrde")),
            "address": row.get("occrAdres"),
            "detail": row.get("etcSpfeatr"),
            "status": row.get("writngTrgetDscd"),
            "source": "safe182",
        }

        person, created = MissingPerson.objects.update_or_create(
            seq=seq,
            defaults=defaults,
        )

        results["created" if created else "updated"] += 1

        # -------------------------------------------------
        # 📸 사진 처리 (Base64 → ImageField 실제 저장)
        # -------------------------------------------------
        photo_base64 = row.get("tknphotoFile")
        if photo_base64:
            image_file = base64_to_image(photo_base64, prefix=seq)

            if image_file:
                # 사진 row 확보 (DB)
                photo, _ = MissingPersonPhoto.objects.get_or_create(
                    person=person,
                    is_main=True,
                )

                # ⚠️ 실제 파일 저장 (이게 핵심)
                photo.image.save(
                    image_file.name,
                    image_file,
                    save=True
                )

    return results
