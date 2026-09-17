"""
safe182.go.kr '보호하고 있어요' 크롤러

사용법:
    python manage.py crawl_safe182

이미지 저장:
    MEDIA_WRITE_MODE=local
        -> 로컬 media

    MEDIA_WRITE_MODE=cloudinary
        -> Cloudinary

    MEDIA_WRITE_MODE=both
        -> 로컬 + Cloudinary
"""

import re
import time
import logging
from datetime import datetime

import requests
from bs4 import BeautifulSoup

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage


logger = logging.getLogger(__name__)


BASE_URL = "https://www.safe182.go.kr"

LIST_URL = (
    f"{BASE_URL}/home/lcm/lcmMssList.do"
)

DETAIL_URL = (
    f"{BASE_URL}/home/lcm/lcmMssGet.do"
)

REQUEST_DELAY = 1.0


HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Referer": (
        f"{BASE_URL}/home/lcm/"
        f"lcmMssList.do?rptDscd=1"
    ),
    "Accept-Language": "ko-KR,ko;q=0.9",
}


class Safe182Crawler:

    def __init__(
        self,
        download_images=True,
    ):
        """
        download_images:
            True  -> 이미지 다운로드
            False -> 이미지 다운로드 생략

        실제 저장 위치는
        default_storage =
        UniversalMediaStorage가 결정한다.
        """

        self.session = requests.Session()

        self.session.headers.update(
            HEADERS
        )

        self.download_images = (
            download_images
        )


    # ======================================================
    # 목록 페이지
    # ======================================================

    def fetch_list_page(
        self,
        page: int = 1,
    ) -> BeautifulSoup:

        params = {
            "rptDscd": "1",
            "pageIndex": str(page),
        }

        resp = self.session.get(
            LIST_URL,
            params=params,
            timeout=15,
        )

        resp.raise_for_status()

        return BeautifulSoup(
            resp.text,
            "html.parser",
        )


    def parse_total_count(
        self,
        soup: BeautifulSoup,
    ) -> int:

        strong = soup.select_one(
            "p.item strong.main-color"
        )

        if not strong:
            return 0

        raw = strong.text.strip()

        try:
            return int(
                re.sub(
                    r"[^\d]",
                    "",
                    raw,
                )
            )
        except ValueError:
            return 0


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

                item["name"] = raw_title
                item["current_age"] = None
                item["gender"] = ""

            tag = li.select_one(
                "span.info"
            )

            item["category"] = (
                tag.text.strip()
                if tag
                else ""
            )

            items.append(item)

        return items


    # ======================================================
    # 상세 페이지
    # ======================================================

    def fetch_detail(
        self,
        msspsn_idntfccd: str,
    ) -> dict:

        data = {
            "msspsnIdntfccd":
                msspsn_idntfccd
        }

        resp = self.session.post(
            DETAIL_URL,
            data=data,
            timeout=15,
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


    def _parse_detail(
        self,
        soup: BeautifulSoup,
        msspsn_idntfccd: str,
    ) -> dict:

        result = {
            "msspsn_idntfccd":
                msspsn_idntfccd
        }

        # ----------------------------------------------
        # 이름 / 나이 / 성별
        # ----------------------------------------------

        name_tag = soup.select_one(
            "span.name"
        )

        if name_tag:

            raw = (
                name_tag.text.strip()
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

                result["current_age"] = int(
                    m.group(2)
                )

                result["gender"] = (
                    m.group(3)
                    or ""
                )

        # ----------------------------------------------
        # 분류
        # ----------------------------------------------

        tag = soup.select_one(
            "span.info"
        )

        result["category"] = (
            tag.text.strip()
            if tag
            else ""
        )

        # ----------------------------------------------
        # 상세 필드
        # ----------------------------------------------

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

            key = (
                th.text.strip()
            )

            value = (
                td.text.strip()
            )

            if key in field_map:
                result[
                    field_map[key]
                ] = value

        # ----------------------------------------------
        # 당시 나이
        # ----------------------------------------------

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

        # ----------------------------------------------
        # 발생일
        # ----------------------------------------------

        occ_raw = result.pop(
            "_occurred_raw",
            "",
        )

        result["occurred_at"] = (
            self._parse_date(
                occ_raw
            )
        )

        # ----------------------------------------------
        # 이미지
        # ----------------------------------------------

        raw_image_urls = (
            self._collect_raw_image_urls(
                soup,
                msspsn_idntfccd,
            )
        )

        # --no-images가 아니면
        # UniversalMediaStorage로 저장
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

            # 이미지 다운로드를 생략한 경우
            # 원본 Safe182 URL 유지
            result["image_urls"] = (
                raw_image_urls
            )

        return result


    # ======================================================
    # 날짜
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

        # 썸네일 목록이 없으면
        # 메인 이미지 확인
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
    # 이미지 다운로드
    # ======================================================

    def _download_images(
        self,
        msspsn_idntfccd: str,
        urls: list[str],
    ) -> list[str]:

        """
        Safe182의 이미지를 다운로드하고
        Django default_storage로 저장.

        DB에는 저장 위치에 관계없이 항상:

        protected_persons/123456/0.jpg

        같은 상대경로를 넣는다.
        """

        saved_paths = []

        for idx, url in enumerate(
            urls
        ):

            try:

                logger.info(
                    f"이미지 다운로드: "
                    f"{msspsn_idntfccd} "
                    f"[{idx}]"
                )

                resp = self.session.get(
                    url,
                    timeout=15,
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

                # Safe182 noImage
                if ext == ".gif":

                    logger.debug(
                        f"이미지 없음(gif) "
                        f"스킵: {url}"
                    )

                    continue

                filename = (
                    f"{idx}{ext}"
                )

                relative_path = (
                    f"protected_persons/"
                    f"{msspsn_idntfccd}/"
                    f"{filename}"
                )

                # ======================================
                # 핵심
                # ======================================
                #
                # MEDIA_ROOT에 직접 open()하지 않는다.
                #
                # UniversalMediaStorage가:
                #
                # local
                # cloudinary
                # both
                #
                # 중 어디에 저장할지 결정한다.
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

            except Exception as e:

                logger.warning(
                    f"이미지 다운로드/저장 실패 "
                    f"({url}): {e}"
                )

        return saved_paths


    # ======================================================
    # Content-Type -> 확장자
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

        soup = (
            self.fetch_list_page(1)
        )

        total = (
            self.parse_total_count(
                soup
            )
        )

        logger.info(
            f"전체 보호중 실종자: "
            f"{total}건"
        )

        page = 1

        while True:

            logger.info(
                f"목록 페이지 "
                f"{page} 크롤링 중..."
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

            list_items = (
                self.parse_list_items(
                    soup
                )
            )

            if not list_items:
                break

            for item in list_items:

                msspsn_id = (
                    item[
                        "msspsn_idntfccd"
                    ]
                )

                time.sleep(
                    delay
                )

                try:

                    detail = (
                        self.fetch_detail(
                            msspsn_id
                        )
                    )

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

                except Exception as e:

                    logger.error(
                        f"상세 크롤링 실패 "
                        f"({msspsn_id}): "
                        f"{e}"
                    )

                    continue

            has_next = any(
                (
                    f"pageIndex="
                    f"{page + 1}"
                )
                in a.get(
                    "href",
                    "",
                )
                for a
                in soup.select(
                    "ul.pagination a"
                )
            )

            if not has_next:
                break

            page += 1