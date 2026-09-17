import os
from pathlib import Path

import cloudinary
import cloudinary.api
import cloudinary.uploader
from dotenv import load_dotenv


BASE_DIR = Path(__file__).resolve().parent
MEDIA_DIR = BASE_DIR / "media"

load_dotenv(BASE_DIR / ".env")

cloudinary.config(
    cloud_name=os.getenv("CLOUDINARY_CLOUD_NAME"),
    api_key=os.getenv("CLOUDINARY_API_KEY"),
    api_secret=os.getenv("CLOUDINARY_API_SECRET"),
    secure=True,
)

IMAGE_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
    ".gif",
}


# ======================================================
# 1. Cloudinary에 이미 존재하는 이미지 목록 한꺼번에 가져오기
# ======================================================

print("Cloudinary 기존 파일 목록 확인 중...")

existing_ids = set()
next_cursor = None

while True:
    params = {
        "resource_type": "image",
        "type": "upload",
        "max_results": 500,
    }

    if next_cursor:
        params["next_cursor"] = next_cursor

    result = cloudinary.api.resources(**params)

    for resource in result.get("resources", []):
        existing_ids.add(resource["public_id"])

    next_cursor = result.get("next_cursor")

    print(f"현재까지 확인된 Cloudinary 파일: {len(existing_ids)}개")

    if not next_cursor:
        break


print()
print(f"Cloudinary 기존 이미지 총 {len(existing_ids)}개 확인 완료")
print("media 복사를 시작합니다.")
print()


# ======================================================
# 2. 로컬 media 파일 복사
# ======================================================

success_count = 0
skip_count = 0
fail_count = 0


for file_path in MEDIA_DIR.rglob("*"):

    if not file_path.is_file():
        continue

    if file_path.suffix.lower() not in IMAGE_EXTENSIONS:
        continue

    relative_path = file_path.relative_to(MEDIA_DIR)

    # 예:
    # missing_persons/4540938/0.jpg
    # -> missing_persons/4540938/0
    public_id = relative_path.with_suffix("").as_posix()

    # Cloudinary 목록은 이미 메모리에 있으므로
    # 여기서는 API 호출 없이 검사
    if public_id in existing_ids:
        skip_count += 1
        print(f"[SKIP] {relative_path}")
        continue

    try:
        result = cloudinary.uploader.upload(
            str(file_path),
            public_id=public_id,
            overwrite=True,
            resource_type="image",
        )

        success_count += 1

        # 방금 올린 파일도 목록에 추가
        existing_ids.add(public_id)

        print(
            f"[OK] {relative_path} "
            f"-> {result.get('secure_url')}"
        )

    except Exception as e:
        fail_count += 1
        print(f"[FAIL] {relative_path} -> {e}")


print()
print("========== 복사 완료 ==========")
print(f"새로 업로드: {success_count}")
print(f"이미 있어서 건너뜀: {skip_count}")
print(f"실패: {fail_count}")