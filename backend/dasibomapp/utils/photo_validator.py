import os
import cv2
import numpy as np
from PIL import Image


MAX_IMAGE_SIZE = 10 * 1024 * 1024  # 10MB
MIN_WIDTH = 300
MIN_HEIGHT = 300
ALLOWED_EXTENSIONS = [".jpg", ".jpeg", ".png"]


def _base_result(status="warning", message="", confidence=None, is_valid=False):
    return {
        "is_valid": is_valid,
        "status": status,
        "message": message,
        "confidence": confidence,
    }


def _check_basic_image(image_file):
    """
    이미지 공통 기본 검증
    - 확장자 확인
    - 용량 확인
    - 이미지 파일 열림 여부 확인
    - 최소 해상도 확인
    """

    filename = getattr(image_file, "name", "")
    ext = os.path.splitext(filename)[1].lower()

    if ext not in ALLOWED_EXTENSIONS:
        return None, _base_result(
            status="invalid",
            message="jpg, jpeg, png 형식의 이미지만 등록할 수 있습니다.",
            confidence=0.0,
            is_valid=False,
        )

    if getattr(image_file, "size", 0) > MAX_IMAGE_SIZE:
        return None, _base_result(
            status="invalid",
            message="이미지 용량은 10MB 이하만 등록할 수 있습니다.",
            confidence=0.0,
            is_valid=False,
        )

    try:
        image_file.seek(0)
        pil_image = Image.open(image_file).convert("RGB")
        width, height = pil_image.size

        if width < MIN_WIDTH or height < MIN_HEIGHT:
            return None, _base_result(
                status="invalid",
                message="이미지 해상도가 너무 낮습니다. 최소 300x300 이상의 사진을 등록해주세요.",
                confidence=0.0,
                is_valid=False,
            )

        return pil_image, None

    except Exception:
        return None, _base_result(
            status="invalid",
            message="이미지 파일을 읽을 수 없습니다. 다른 사진을 등록해주세요.",
            confidence=0.0,
            is_valid=False,
        )


def _to_cv_gray(pil_image):
    """
    PIL 이미지를 OpenCV 얼굴 감지용 grayscale 이미지로 변환한다.
    """
    image_np = np.array(pil_image)
    gray = cv2.cvtColor(image_np, cv2.COLOR_RGB2GRAY)
    return gray


def _detect_frontal_faces(gray):
    """
    정면 얼굴 감지
    OpenCV 기본 Haar Cascade 사용
    """

    face_cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    )

    faces = face_cascade.detectMultiScale(
        gray,
        scaleFactor=1.1,
        minNeighbors=5,
        minSize=(80, 80)
    )

    return faces


def _detect_profile_faces(gray):
    """
    측면 얼굴 감지
    왼쪽/오른쪽 방향을 정확히 구분하기 어렵기 때문에
    원본 + 좌우반전 이미지를 모두 검사한다.
    """

    profile_cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_profileface.xml"
    )

    faces_original = profile_cascade.detectMultiScale(
        gray,
        scaleFactor=1.1,
        minNeighbors=5,
        minSize=(80, 80)
    )

    flipped_gray = cv2.flip(gray, 1)

    faces_flipped = profile_cascade.detectMultiScale(
        flipped_gray,
        scaleFactor=1.1,
        minNeighbors=5,
        minSize=(80, 80)
    )

    return faces_original, faces_flipped


def _validate_front_face_photo(image_file, frontal_count, is_parent_photo=False):
    """
    정면 얼굴 사진 검증 공통 함수

    사용 대상:
    - 등록 대상자 정면 사진: face
    - 부모님/가족 정면 사진 1: parent1_face
    - 부모님/가족 정면 사진 2: parent2_face
    """

    if frontal_count == 0:
        image_file.seek(0)

        if is_parent_photo:
            return _base_result(
                status="invalid",
                message="부모님 정면 얼굴이 감지되지 않았습니다. 얼굴이 잘 보이는 정면 사진을 등록해주세요.",
                confidence=0.0,
                is_valid=False,
            )

        return _base_result(
            status="invalid",
            message="정면 얼굴이 감지되지 않았습니다. 얼굴이 잘 보이는 정면 사진을 등록해주세요.",
            confidence=0.0,
            is_valid=False,
        )

    if frontal_count > 1:
        image_file.seek(0)

        if is_parent_photo:
            return _base_result(
                status="warning",
                message="여러 명의 얼굴이 감지되었습니다. 부모님 한 분만 나온 정면 사진이 권장됩니다.",
                confidence=0.5,
                is_valid=True,
            )

        return _base_result(
            status="warning",
            message="여러 명의 얼굴이 감지되었습니다. 등록 대상자 1명만 나온 사진이 권장됩니다.",
            confidence=0.5,
            is_valid=True,
        )

    image_file.seek(0)

    if is_parent_photo:
        return _base_result(
            status="valid",
            message="부모님 정면 얼굴 사진으로 확인되었습니다.",
            confidence=0.9,
            is_valid=True,
        )

    return _base_result(
        status="valid",
        message="정면 얼굴 사진으로 확인되었습니다.",
        confidence=0.9,
        is_valid=True,
    )


def validate_prevention_photo(image_file, expected_type):
    """
    실종 예방 등록 사진 검증 함수

    expected_type:
    - face: 등록 대상자 정면 사진
    - full_body: 등록 대상자 전신 사진
    - left_side: 등록 대상자 왼쪽 측면 사진
    - right_side: 등록 대상자 오른쪽 측면 사진
    - parent1_face: 부모님/가족 정면 사진 1
    - parent2_face: 부모님/가족 정면 사진 2

    반환:
    {
        "is_valid": bool,
        "status": "valid" | "warning" | "invalid" | "error",
        "message": str,
        "confidence": float | None
    }
    """

    try:
        pil_image, basic_error = _check_basic_image(image_file)

        if basic_error:
            image_file.seek(0)
            return basic_error

        width, height = pil_image.size
        gray = _to_cv_gray(pil_image)

        frontal_faces = _detect_frontal_faces(gray)
        profile_original, profile_flipped = _detect_profile_faces(gray)

        frontal_count = len(frontal_faces)
        profile_count = len(profile_original) + len(profile_flipped)

        # --------------------------------------------------
        # 1. 정면 사진 검증
        # - 등록 대상자 정면 사진
        # - 부모님/가족 정면 사진 1
        # - 부모님/가족 정면 사진 2
        # --------------------------------------------------
        if expected_type in ["face", "parent1_face", "parent2_face"]:
            is_parent_photo = expected_type in ["parent1_face", "parent2_face"]

            return _validate_front_face_photo(
                image_file=image_file,
                frontal_count=frontal_count,
                is_parent_photo=is_parent_photo,
            )

        # --------------------------------------------------
        # 2. 전신 사진 검증
        # - 최종발표용 간단 검증:
        #   세로형 이미지면 전신 사진일 가능성이 높다고 판단
        # --------------------------------------------------
        if expected_type == "full_body":
            ratio = height / width if width else 0

            if ratio >= 1.2:
                image_file.seek(0)
                return _base_result(
                    status="valid",
                    message="전신 사진으로 등록 가능한 세로형 이미지입니다.",
                    confidence=0.65,
                    is_valid=True,
                )

            image_file.seek(0)
            return _base_result(
                status="warning",
                message="전신 사진은 세로형 이미지가 권장됩니다. 관리자 확인이 필요합니다.",
                confidence=0.4,
                is_valid=True,
            )

        # --------------------------------------------------
        # 3. 측면 사진 검증
        # - 측면 얼굴이 감지되면 valid
        # - 정면 얼굴만 감지되면 warning
        # - 얼굴 방향이 애매하면 warning
        # --------------------------------------------------
        if expected_type in ["left_side", "right_side"]:
            if profile_count > 0:
                image_file.seek(0)
                return _base_result(
                    status="valid",
                    message="측면 얼굴 사진으로 판단됩니다.",
                    confidence=0.75,
                    is_valid=True,
                )

            if frontal_count > 0:
                image_file.seek(0)
                return _base_result(
                    status="warning",
                    message="정면 얼굴로 감지되었습니다. 측면 사진인지 관리자 확인이 필요합니다.",
                    confidence=0.45,
                    is_valid=True,
                )

            image_file.seek(0)
            return _base_result(
                status="warning",
                message="얼굴 방향을 명확히 판단하기 어렵습니다. 관리자 확인이 필요합니다.",
                confidence=0.3,
                is_valid=True,
            )

        image_file.seek(0)
        return _base_result(
            status="warning",
            message="알 수 없는 사진 유형입니다.",
            confidence=None,
            is_valid=True,
        )

    except Exception as e:
        image_file.seek(0)
        return _base_result(
            status="error",
            message=f"사진 검증 중 오류가 발생했습니다: {str(e)}",
            confidence=None,
            is_valid=False,
        )