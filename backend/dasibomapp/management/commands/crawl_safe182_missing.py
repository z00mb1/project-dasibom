"""
safe182.go.kr '찾고 있어요' 실종자 크롤러

사용법:
    python manage.py crawl_safe182_missing
    python manage.py crawl_safe182_missing --delay 1.5
    python manage.py crawl_safe182_missing --no-images
    python manage.py crawl_safe182_missing --update

이미지 저장 위치:
    MEDIA_WRITE_MODE=local
        → 로컬 media 폴더

    MEDIA_WRITE_MODE=cloudinary
        → Cloudinary

    MEDIA_WRITE_MODE=both
        → 로컬 media + Cloudinary
"""

import re
import time
import logging
import math

from datetime import datetime

import requests
from requests.exceptions import (
    RequestException,
    ChunkedEncodingError,
    ConnectionError,
    Timeout,
)

from bs4 import BeautifulSoup

from django.core.management.base import BaseCommand
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage


logger = logging.getLogger(__name__)


# ==========================================================
# Safe182 기본 URL
# ==========================================================

BASE_URL = "https://www.safe182.go.kr"

LIST_URL = (
    f"{BASE_URL}/home/lcm/lcmMssList.do"
)

DETAIL_URL = (
    f"{BASE_URL}/home/lcm/lcmMssGet.do"
)


# ==========================================================
# 크롤링 기본 설정
# ==========================================================

PER_PAGE = 10

REQUEST_DELAY = 1.0

MAX_RETRIES = 3


HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),

    "Referer": (
        f"{BASE_URL}/home/lcm/"
        f"lcmMssList.do?rptDscd=2"
    ),

    "Accept-Language": (
        "ko-KR,ko;q=0.9"
    ),

    "Accept": (
        "text/html,"
        "application/xhtml+xml,"
        "application/xml;q=0.9,"
        "*/*;q=0.8"
    ),

    "Connection": "close",
}


# ==========================================================
# 실종자 크롤러
# ==========================================================

class MissingPersonCrawler:

    def __init__(
        self,
        download_images=True,
    ):
        """
        download_images:
            True
                → 이미지 다운로드 및 default_storage 저장

            False
                → 이미지 다운로드 생략
        """

        self.session = requests.Session()

        self.session.headers.update(
            HEADERS
        )

        self.download_images = (
            download_images
        )


    # ======================================================
    # 재시도 대기
    # ======================================================

    def _sleep_before_retry(
        self,
        attempt: int,
    ):
        wait_seconds = (
            2 * attempt
        )

        logger.warning(
            f"{wait_seconds}초 후 "
            f"재시도합니다..."
        )

        time.sleep(
            wait_seconds
        )


    # ======================================================
    # 목록 페이지
    # ======================================================

    def fetch_list_page(
        self,
        page: int = 1,
    ) -> BeautifulSoup | None:

        params = {
            "rptDscd": "2",
            "pageIndex": str(page),
        }

        for attempt in range(
            1,
            MAX_RETRIES + 1,
        ):

            try:
                logger.info(
                    f"목록 페이지 요청: "
                    f"page={page}, "
                    f"attempt="
                    f"{attempt}/{MAX_RETRIES}"
                )

                resp = self.session.get(
                    LIST_URL,
                    params=params,
                    timeout=30,
                    headers=HEADERS,
                )

                resp.raise_for_status()

                return BeautifulSoup(
                    resp.text,
                    "html.parser",
                )

            except (
                ChunkedEncodingError,
                ConnectionError,
                Timeout,
                RequestException,
            ) as e:

                logger.warning(
                    f"목록 페이지 요청 실패: "
                    f"page={page}, "
                    f"attempt="
                    f"{attempt}/{MAX_RETRIES}, "
                    f"error={e}"
                )

                if attempt < MAX_RETRIES:
                    self._sleep_before_retry(
                        attempt
                    )
                    continue

                logger.error(
                    f"목록 페이지 최종 실패: "
                    f"page={page}"
                )

                return None


    # ======================================================
    # 전체 건수
    # ======================================================

    def parse_total_count(
        self,
        soup: BeautifulSoup,
    ) -> int:

        strong = soup.select_one(
            "p.item strong.main-color"
        )

        if not strong:
            return 0

        try:
            return int(
                re.sub(
                    r"[^\d]",
                    "",
                    strong.text,
                )
            )

        except ValueError:
            return 0


    # ======================================================
    # 목록 데이터 파싱
    # ======================================================

    def parse_list_items(
        self,
        soup: BeautifulSoup,
    ) -> list[dict]:

        items = []

        for li in soup.select(
            "ul > li.col-sm-4"
        ):

            link = li.select_one(
                "a.linkStyle3, dl dt a"
            )

            if not link:
                continue

            onclick = link.get(
                "onclick",
                "",
            )

            match = re.search(
                r"fn_getLcmMssGet\('(\d+)'\)",
                onclick,
            )

            if not match:
                continue

            item = {
                "msspsn_idntfccd":
                    match.group(1)
            }

            raw_title = (
                link.text.strip()
            )

            name_match = re.match(
                r"(.+?)\((\d+)세\)\s*"
                r"(남자|여자)?",
                raw_title,
            )

            if name_match:

                item["name"] = (
                    name_match
                    .group(1)
                    .strip()
                )

                item["current_age"] = int(
                    name_match.group(2)
                )

                item["gender"] = (
                    name_match.group(3)
                    or ""
                )

            else:

                item["name"] = (
                    raw_title
                )

                item["current_age"] = (
                    None
                )

                item["gender"] = ""

            tag = li.select_one(
                "span.info"
            )

            item["category"] = (
                tag.text.strip()
                if tag
                else ""
            )

            items.append(
                item
            )

        return items


    # ======================================================
    # 상세 페이지
    # ======================================================

    def fetch_detail(
        self,
        msspsn_idntfccd: str,
    ) -> dict | None:

        data = {
            "msspsnIdntfccd":
                msspsn_idntfccd
        }

        for attempt in range(
            1,
            MAX_RETRIES + 1,
        ):

            try:
                logger.info(
                    f"상세 페이지 요청: "
                    f"id={msspsn_idntfccd}, "
                    f"attempt="
                    f"{attempt}/{MAX_RETRIES}"
                )

                resp = self.session.post(
                    DETAIL_URL,
                    data=data,
                    timeout=30,
                    headers=HEADERS,
                )

                resp.raise_for_status()

                soup = BeautifulSoup(
                    resp.text,
                    "html.parser",
                )

                return self._parse_detail(
                    soup,
                    msspsn_idntfccd,
                )

            except (
                ChunkedEncodingError,
                ConnectionError,
                Timeout,
                RequestException,
            ) as e:

                logger.warning(
                    f"상세 페이지 요청 실패: "
                    f"id={msspsn_idntfccd}, "
                    f"attempt="
                    f"{attempt}/{MAX_RETRIES}, "
                    f"error={e}"
                )

                if attempt < MAX_RETRIES:
                    self._sleep_before_retry(
                        attempt
                    )
                    continue

                logger.error(
                    f"상세 페이지 최종 실패: "
                    f"id={msspsn_idntfccd}"
                )

                return None


    # ======================================================
    # 상세 내용 파싱
    # ======================================================

    def _parse_detail(
        self,
        soup: BeautifulSoup,
        msspsn_idntfccd: str,
    ) -> dict:

        result = {
            "msspsn_idntfccd":
                msspsn_idntfccd,
        }

        # --------------------------------------------------
        # 이름 / 나이 / 성별
        # --------------------------------------------------

        name_tag = soup.select_one(
            "span.name"
        )

        if name_tag:

            raw = name_tag.get_text(
                strip=True
            )

            m = re.match(
                r"(.+?)\((\d+)세\)\s*"
                r"(남자|여자)?",
                raw,
            )

            if m:

                result["name"] = (
                    m.group(1).strip()
                )

                result["current_age"] = (
                    int(m.group(2))
                )

                result["gender"] = (
                    m.group(3)
                    or ""
                )

        # --------------------------------------------------
        # 분류
        # --------------------------------------------------

        tag = soup.select_one(
            "span.info"
        )

        result["category"] = (
            tag.get_text(strip=True)
            if tag
            else ""
        )

        # --------------------------------------------------
        # 상세 필드
        # --------------------------------------------------

        field_map = {
            "당시나이": "_age_raw",
            "국적": "nationality",
            "발생일시": "_occurred_raw",
            "발생장소": "occurred_location",
            "키": "height",
            "몸무게": "weight",
            "체격": "body_type",
            "얼굴형": "face_type",
            "두발색상": "hair_color",
            "두발형태": "hair_style",
            "착의의상": "clothing",
            "진행상": "status",
            "진행상태": "status",
        }

        for tr in soup.select(
            "table.table-01 tbody tr"
        ):

            th = tr.select_one("th")
            td = tr.select_one("td")

            if not th or not td:
                continue

            key = th.get_text(
                strip=True
            )

            value = re.sub(
                r"\s+",
                " ",
                td.get_text(
                    strip=True
                ),
            )

            if key in field_map:
                result[
                    field_map[key]
                ] = value

        # --------------------------------------------------
        # 당시나이
        # --------------------------------------------------

        age_raw = result.pop(
            "_age_raw",
            "",
        )

        m = re.search(
            r"(\d+)세",
            age_raw,
        )

        result["age_at_missing"] = (
            int(m.group(1))
            if m
            else None
        )

        # --------------------------------------------------
        # 발생일시
        # --------------------------------------------------

        occ_raw = result.pop(
            "_occurred_raw",
            "",
        )

        result["occurred_at"] = (
            self._parse_date(
                occ_raw
            )
        )

        # 크롤링 결과의 status는
        # DB 저장 시 별도로 결정
        result.pop(
            "status",
            None,
        )

        # --------------------------------------------------
        # 이미지
        # --------------------------------------------------

        raw_image_urls = (
            self._collect_raw_image_urls(
                soup,
                msspsn_idntfccd,
            )
        )

        if (
            self.download_images
            and raw_image_urls
        ):
            result["image_urls"] = (
                self._download_images(
                    msspsn_idntfccd,
                    raw_image_urls,
                )
            )

        else:
            result["image_urls"] = (
                raw_image_urls
            )

        return result


    # ======================================================
    # 날짜 파싱
    # ======================================================

    def _parse_date(
        self,
        raw: str,
    ):

        m = re.search(
            r"(\d{4})년\s*"
            r"(\d{1,2})월\s*"
            r"(\d{1,2})일",
            raw,
        )

        if m:

            try:
                return datetime(
                    int(m.group(1)),
                    int(m.group(2)),
                    int(m.group(3)),
                ).date()

            except ValueError:
                pass

        return None


    # ======================================================
    # Safe182 원본 이미지 URL 수집
    # ======================================================

    def _collect_raw_image_urls(
        self,
        soup: BeautifulSoup,
        msspsn_idntfccd: str,
    ) -> list[str]:

        urls = []

        for img in soup.select(
            "ul.sub-thum img"
        ):

            src = img.get(
                "src",
                "",
            )

            idx_match = re.search(
                r"tknphoto[Ff]ile[Ii]dx=(\d+)",
                src,
            )

            if idx_match:

                idx = (
                    idx_match.group(1)
                )

                url = (
                    f"{BASE_URL}"
                    f"/home/lcm/"
                    f"blobImgListView.do"
                    f"?tknphotoFileIdx={idx}"
                    f"&p={msspsn_idntfccd}"
                )

                urls.append(
                    url
                )

        # 썸네일 목록이 없을 경우 메인 이미지 확인
        if not urls:

            main_img = soup.select_one(
                "p.main-thum img, "
                "img[name='tknImg']"
            )

            if main_img:

                src = main_img.get(
                    "src",
                    "",
                )

                if (
                    src
                    and "noImage"
                    not in src
                ):

                    urls.append(
                        BASE_URL + src
                        if src.startswith("/")
                        else src
                    )

        return urls


    # ======================================================
    # 이미지 다운로드 및 Universal Storage 저장
    # ======================================================

    def _download_images(
        self,
        msspsn_idntfccd: str,
        urls: list[str],
    ) -> list[str]:

        """
        Safe182 이미지를 다운로드한 뒤
        Django default_storage로 저장한다.

        따라서 저장 위치는 settings.py의
        UniversalMediaStorage가 결정한다.

        MEDIA_WRITE_MODE=local
            → 로컬만

        MEDIA_WRITE_MODE=cloudinary
            → Cloudinary만

        MEDIA_WRITE_MODE=both
            → 로컬 + Cloudinary

        반환값 예:
            [
                "missing_persons/6155646/0.jpg",
                "missing_persons/6155646/1.jpg",
            ]
        """

        saved_paths = []

        for idx, url in enumerate(
            urls
        ):

            downloaded = False

            for attempt in range(
                1,
                MAX_RETRIES + 1,
            ):

                try:
                    logger.info(
                        f"이미지 다운로드 요청: "
                        f"id={msspsn_idntfccd}, "
                        f"idx={idx}, "
                        f"attempt="
                        f"{attempt}/{MAX_RETRIES}"
                    )

                    resp = self.session.get(
                        url,
                        timeout=30,
                        headers=HEADERS,
                    )

                    resp.raise_for_status()

                    content_type = (
                        resp.headers.get(
                            "Content-Type",
                            "",
                        )
                    )

                    ext = self._get_ext(
                        content_type
                    )

                    # Safe182의 noImage가 gif인 경우
                    if ext == ".gif":

                        logger.debug(
                            f"이미지 없음(gif) "
                            f"스킵: {url}"
                        )

                        downloaded = True

                        break

                    filename = (
                        f"{idx}{ext}"
                    )

                    # DB에는 항상
                    # 상대경로만 저장
                    relative_path = (
                        f"missing_persons/"
                        f"{msspsn_idntfccd}/"
                        f"{filename}"
                    )

                    # ======================================
                    # 핵심
                    # ======================================
                    #
                    # 파일 저장 방식은 직접 open()하지 않고
                    # default_storage에 맡김
                    #
                    # UniversalMediaStorage가
                    # local/cloudinary/both를 결정
                    # ======================================

                    saved_path = (
                        default_storage.save(
                            relative_path,
                            ContentFile(
                                resp.content
                            ),
                        )
                    )

                    saved_paths.append(
                        saved_path
                    )

                    logger.info(
                        f"이미지 저장 완료: "
                        f"{saved_path}"
                    )

                    downloaded = True

                    break

                except (
                    ChunkedEncodingError,
                    ConnectionError,
                    Timeout,
                    RequestException,
                ) as e:

                    logger.warning(
                        f"이미지 다운로드 실패: "
                        f"id={msspsn_idntfccd}, "
                        f"url={url}, "
                        f"attempt="
                        f"{attempt}/{MAX_RETRIES}, "
                        f"error={e}"
                    )

                    if (
                        attempt
                        < MAX_RETRIES
                    ):

                        self._sleep_before_retry(
                            attempt
                        )

                        continue

                    logger.error(
                        f"이미지 다운로드 "
                        f"최종 실패: "
                        f"{url}"
                    )

                except Exception as e:

                    # Cloudinary 저장 등
                    # storage 단계의 오류
                    logger.exception(
                        f"이미지 저장 실패: "
                        f"id={msspsn_idntfccd}, "
                        f"url={url}, "
                        f"error={e}"
                    )

                    break

            if not downloaded:
                continue

        return saved_paths


    # ======================================================
    # Content-Type → 확장자
    # ======================================================

    def _get_ext(
        self,
        content_type: str,
    ) -> str:

        mapping = {
            "image/jpeg": ".jpg",
            "image/jpg": ".jpg",
            "image/png": ".png",
            "image/gif": ".gif",
            "image/webp": ".webp",
        }

        for mime, ext in (
            mapping.items()
        ):

            if mime in content_type:
                return ext

        return ".jpg"


    # ======================================================
    # 전체 크롤링
    # ======================================================

    def crawl_all(
        self,
        delay: float = REQUEST_DELAY,
    ):
        """
        전체 목록 페이지를 순회한다.

        안전장치:
        - 1페이지 실패 → 전체 중단
        - 중간 목록 페이지 실패 → 전체 중단
        - 상세 페이지 일부 실패 → 해당 사람만 스킵
        """

        soup = (
            self.fetch_list_page(1)
        )

        if soup is None:

            raise RuntimeError(
                "1페이지 목록 요청 실패 — "
                "전체 건수를 확인할 수 없어 "
                "크롤링을 중단합니다."
            )

        total = (
            self.parse_total_count(
                soup
            )
        )

        if total == 0:

            logger.warning(
                "전체 건수 파싱 실패 "
                "또는 0건"
            )

            return

        total_pages = math.ceil(
            total
            / PER_PAGE
        )

        logger.info(
            f"전체 실종자: "
            f"{total}건 / "
            f"{total_pages}페이지"
        )

        for page in range(
            1,
            total_pages + 1,
        ):

            logger.info(
                f"목록 페이지 "
                f"{page}/{total_pages} "
                f"처리 중..."
            )

            if page > 1:

                time.sleep(
                    delay
                )

                soup = (
                    self.fetch_list_page(
                        page
                    )
                )

                if soup is None:

                    raise RuntimeError(
                        f"페이지 "
                        f"{page}/{total_pages} "
                        f"목록 요청 실패 "
                        f"— 찾음 처리를 "
                        f"안전하게 중단합니다."
                    )

            list_items = (
                self.parse_list_items(
                    soup
                )
            )

            if not list_items:

                raise RuntimeError(
                    f"페이지 "
                    f"{page}/{total_pages} "
                    f"목록 파싱 실패 "
                    f"(항목 0건) "
                    f"— 찾음 처리를 "
                    f"안전하게 중단합니다."
                )

            for item in list_items:

                msspsn_id = (
                    item[
                        "msspsn_idntfccd"
                    ]
                )

                logger.info(
                    f"상세 크롤링 시작: "
                    f"{msspsn_id}"
                )

                time.sleep(
                    delay
                )

                detail = (
                    self.fetch_detail(
                        msspsn_id
                    )
                )

                if detail is None:

                    logger.error(
                        f"상세 크롤링 실패로 "
                        f"건너뜀: "
                        f"{msspsn_id}"
                    )

                    continue

                detail.setdefault(
                    "name",
                    item.get(
                        "name",
                        "",
                    ),
                )

                detail.setdefault(
                    "gender",
                    item.get(
                        "gender",
                        "",
                    ),
                )

                detail.setdefault(
                    "current_age",
                    item.get(
                        "current_age"
                    ),
                )

                detail.setdefault(
                    "category",
                    item.get(
                        "category",
                        "",
                    ),
                )

                yield detail


# ==========================================================
# Django Management Command
# ==========================================================

class Command(BaseCommand):

    help = (
        "safe182 '찾고 있어요' "
        "실종자 전체 크롤링 → "
        "DB 저장 / 사라진 항목은 "
        "status='찾음' 처리"
    )


    # ======================================================
    # CLI 옵션
    # ======================================================

    def add_arguments(
        self,
        parser,
    ):

        parser.add_argument(
            "--delay",
            type=float,
            default=REQUEST_DELAY,
            help=(
                f"요청 간격(초), "
                f"기본값: "
                f"{REQUEST_DELAY}"
            ),
        )

        parser.add_argument(
            "--no-images",
            action="store_true",
            help="이미지 다운로드 생략",
        )

        parser.add_argument(
            "--update",
            action="store_true",
            help=(
                "이미 존재하는 레코드도 "
                "업데이트 "
                "(기본: 신규만 저장)"
            ),
        )


    # ======================================================
    # 실행
    # ======================================================

    def handle(
        self,
        *args,
        **options,
    ):

        from dasibomapp.models import (
            MissingPerson
        )

        delay = (
            options["delay"]
        )

        no_images = (
            options["no_images"]
        )

        do_update = (
            options["update"]
        )

        self.stdout.write(
            self.style.NOTICE(
                f"크롤링 시작 | "
                f"delay={delay}s | "
                f"이미지="
                f"{'생략' if no_images else '저장'} | "
                f"업데이트="
                f"{'ON' if do_update else 'OFF(신규만)'}"
            )
        )

        # ==============================================
        # 저장 위치는 크롤러가 아니라
        # UniversalMediaStorage에서 결정
        # ==============================================

        crawler = MissingPersonCrawler(
            download_images=(
                not no_images
            )
        )

        # ==============================================
        # 크롤링 전 현재 활성 실종자 목록
        # ==============================================

        db_ids = set(
            MissingPerson.objects
            .filter(
                source=(
                    MissingPerson
                    .Source
                    .SAFE182
                )
            )
            .exclude(
                status=(
                    MissingPerson
                    .Status
                    .FOUND
                )
            )
            .values_list(
                "msspsn_idntfccd",
                flat=True,
            )
        )

        seen_ids = set()

        crawl_ok = True

        created_count = 0
        updated_count = 0
        skipped_count = 0
        error_count = 0


        # ==============================================
        # 실제 크롤링
        # ==============================================

        try:

            for data in (
                crawler.crawl_all(
                    delay=delay
                )
            ):

                msspsn_id = data.get(
                    "msspsn_idntfccd",
                    "",
                )

                if not msspsn_id:

                    error_count += 1

                    continue

                seen_ids.add(
                    msspsn_id
                )

                try:

                    existing = (
                        MissingPerson
                        .objects
                        .filter(
                            msspsn_idntfccd=
                            msspsn_id
                        )
                        .first()
                    )

                    # ----------------------------------
                    # 기존 데이터 + update OFF
                    # ----------------------------------

                    if (
                        existing
                        and not do_update
                    ):

                        skipped_count += 1

                        continue

                    # ----------------------------------
                    # 모델에 존재하는 필드만 추출
                    # ----------------------------------

                    model_fields = {
                        f.name
                        for f
                        in MissingPerson
                        ._meta
                        .get_fields()
                    }

                    safe_data = {
                        k: v
                        for k, v
                        in data.items()
                        if k
                        in model_fields
                    }

                    # 크롤링 status는
                    # 직접 반영하지 않는다.
                    safe_data.pop(
                        "status",
                        None,
                    )

                    # ==================================
                    # UPDATE
                    # ==================================

                    if existing:

                        new_etc = (
                            safe_data.get(
                                "etc_spfeatr",
                                existing
                                .etc_spfeatr,
                            )
                        )

                        etc_changed = (
                            new_etc
                            is not None
                            and
                            new_etc.strip()
                            !=
                            (
                                existing
                                .etc_spfeatr
                                or ""
                            ).strip()
                        )

                        for (
                            field,
                            value,
                        ) in (
                            safe_data.items()
                        ):

                            if field in (
                                "msspsn_idntfccd",
                                "crawled_at",
                            ):
                                continue

                            setattr(
                                existing,
                                field,
                                value,
                            )

                        # 기타 특징 변경 시
                        # AI 분류 캐시 초기화
                        if etc_changed:

                            existing.etc_ai_category = (
                                None
                            )

                            existing.etc_ai_confidence = (
                                None
                            )

                            self.stdout.write(
                                self.style.NOTICE(
                                    f"[CACHE CLEAR] "
                                    f"etc_spfeatr 변경됨 "
                                    f"→ AI 캐시 초기화 "
                                    f"({msspsn_id})"
                                )
                            )

                        existing.save()

                        updated_count += 1

                        self.stdout.write(
                            f"[UPDATE] "
                            f"{existing.name} "
                            f"({msspsn_id})"
                        )

                    # ==================================
                    # CREATE
                    # ==================================

                    else:

                        MissingPerson.objects.create(
                            **safe_data,

                            source=(
                                MissingPerson
                                .Source
                                .SAFE182
                            ),

                            status=(
                                MissingPerson
                                .Status
                                .MISSING
                            ),
                        )

                        created_count += 1

                        self.stdout.write(
                            f"[NEW] "
                            f"{safe_data.get('name', '?')} "
                            f"({msspsn_id})"
                        )

                except Exception as e:

                    logger.exception(
                        f"DB 저장 실패 "
                        f"({msspsn_id})"
                    )

                    self.stderr.write(
                        f"[ERROR] "
                        f"{msspsn_id}: "
                        f"{e}"
                    )

                    error_count += 1


        # ==============================================
        # 목록 크롤링 자체 실패
        # ==============================================

        except RuntimeError as e:

            crawl_ok = False

            self.stderr.write(
                self.style.ERROR(
                    f"\n[크롤링 중단] "
                    f"{e}"
                )
            )

            self.stderr.write(
                self.style.WARNING(
                    "→ 일부 페이지를 "
                    "가져오지 못했으므로 "
                    "'찾음' 처리를 "
                    "건너뜁니다."
                )
            )


        # ==============================================
        # Safe182에서 사라진 사람 → FOUND
        # ==============================================

        found_count = 0

        if crawl_ok:

            vanished_ids = (
                db_ids
                - seen_ids
            )

            if vanished_ids:

                self.stdout.write(
                    self.style.WARNING(
                        f"\n사이트에서 사라진 "
                        f"실종자 "
                        f"{len(vanished_ids)}건 "
                        f"→ '찾음' 처리 중..."
                    )
                )

                found_count = (
                    MissingPerson.objects
                    .filter(
                        msspsn_idntfccd__in=
                            vanished_ids,

                        source=(
                            MissingPerson
                            .Source
                            .SAFE182
                        ),
                    )
                    .update(
                        status=(
                            MissingPerson
                            .Status
                            .FOUND
                        )
                    )
                )

                for mp in (
                    MissingPerson.objects
                    .filter(
                        msspsn_idntfccd__in=
                            vanished_ids,

                        source=(
                            MissingPerson
                            .Source
                            .SAFE182
                        ),
                    )
                    .only(
                        "msspsn_idntfccd",
                        "name",
                    )
                ):

                    self.stdout.write(
                        f"[FOUND] "
                        f"{mp.name} "
                        f"({mp.msspsn_idntfccd})"
                    )

            else:

                self.stdout.write(
                    "\n사이트에서 사라진 "
                    "실종자 없음 "
                    "(목록 변동 없음)"
                )

        else:

            self.stdout.write(
                self.style.WARNING(
                    "\n크롤링이 완전히 "
                    "완료되지 않아 "
                    "'찾음' 처리를 "
                    "건너뜁니다."
                )
            )


        # ==============================================
        # 최종 결과
        # ==============================================

        self.stdout.write(
            self.style.SUCCESS(
                f"\n✅ 완료! "
                f"신규: {created_count} | "
                f"업데이트: {updated_count} | "
                f"스킵: {skipped_count} | "
                f"찾음: {found_count} | "
                f"오류: {error_count}"
            )
        )