import logging
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests
from django.conf import settings
from django.core.cache import cache

from dasibomapp.utils.geo import get_bbox
from dasibomapp.services.frequentzone_service import (
    get_accident_frequent_zones,
)

import threading
logger = logging.getLogger(__name__)

SAFE182_API_URL = "https://www.safe182.go.kr/api/lcm/safeMap.do"

ALLOWED_CODES = ["09", "13", "20", "22", "23"]


# ============================================================
# 같은 위치로 동시에 여러 요청이 들어오는 것 방지
# ============================================================


def _fetch_safe182_by_code(base, code):
    """
    SAFE182 시설 코드 하나 조회
    """

    data = base + [("clArray", code)]

    try:
        resp = requests.post(
            SAFE182_API_URL,
            data=data,
            timeout=4,
        )

        print(
            f"[시설조회] clArray={code} "
            f"status={resp.status_code}"
        )

        resp.raise_for_status()

        content_type = resp.headers.get(
            "Content-Type",
            ""
        )

        if "json" not in content_type.lower():
            logger.warning(
                f"clArray={code} JSON 응답 아님"
            )
            return []

        items = resp.json().get(
            "list",
            []
        )

        print(
            f"[시설조회] clArray={code} "
            f"items={len(items)}"
        )

        return items

    except requests.Timeout:
        logger.warning(
            f"clArray={code} 요청 시간 초과"
        )
        return []

    except Exception as e:
        logger.warning(
            f"clArray={code} 요청 실패: {e}"
        )
        return []


def _fetch_safe182_facilities(
    lat,
    lng,
    radius_km,
):
    bbox = get_bbox(
        lat,
        lng,
        radius_km,
    )

    print(
        f"[시설조회] 검색 반경={radius_km}km "
        f"bbox={bbox}"
    )
    base = [
        (
            "esntlId",
            settings.SAFE182_USER_ID,
        ),
        (
            "authKey",
            settings.SAFE182_API_KEY,
        ),
        (
            "pageIndex",
            "1",
        ),
        (
            "pageUnit",
            "100",
        ),
        (
            "minY",
            bbox["minLat"],
        ),
        (
            "maxY",
            bbox["maxLat"],
        ),
        (
            "minX",
            bbox["minLng"],
        ),
        (
            "maxX",
            bbox["maxLng"],
        ),
        (
            "xmlUseYN",
            "N",
        ),
    ]

    all_items = []

    # ========================================================
    # SAFE182 5개 분류 동시에 조회
    # ========================================================
    with ThreadPoolExecutor(
        max_workers=len(ALLOWED_CODES)
    ) as executor:

        futures = {
            executor.submit(
                _fetch_safe182_by_code,
                base,
                code,
            ): code
            for code in ALLOWED_CODES
        }

        for future in as_completed(
            futures
        ):
            code = futures[future]

            try:
                items = future.result()

                all_items.extend(
                    items
                )

            except Exception as e:
                logger.warning(
                    f"clArray={code} "
                    f"병렬 조회 실패: {e}"
                )

    print(
        "[시설조회] 전체 수집 "
        f"all_items={len(all_items)}"
    )

    # ========================================================
    # 중복 제거
    # ========================================================
    seen = set()

    results = []

    for item in all_items:

        sn = item.get("lcSn")

        if sn is None:
            continue

        if sn in seen:
            continue

        seen.add(sn)

        try:
            lat_val = float(
                item.get("lcinfoLa")
            )

            lng_val = float(
                item.get("lcinfoLo")
            )

        except (
            TypeError,
            ValueError,
        ):
            continue

        results.append({
            "id": str(sn),

            "name": item.get(
                "bsshNm"
            ),

            "categoryName": item.get(
                "clNm"
            ),

            "code": item.get(
                "cl"
            ),

            "address": item.get(
                "adres"
            ),

            "tel": (
                item.get("telno")
                or "정보 없음"
            ),

            "lat": lat_val,

            "lng": lng_val,

            "type": "safe",

            "dangerType": None,
        })

    print(
        "[시설조회] SAFE182 최종 "
        f"results={len(results)}"
    )

    return results


def _fetch_accident_zones(
    lat,
    lng,
    radius_km,
):
    try:
        return get_accident_frequent_zones(
            lat=lat,
            lng=lng,
            radius_km=radius_km,
        )

    except Exception as e:
        print(
            "[생활안전지도] "
            "사고다발지역 조회 실패:",
            e,
        )

        return []


def _load_facilities(
    lat,
    lng,
    radius_km,
):
    with ThreadPoolExecutor(
        max_workers=2
    ) as executor:

        safe_future = executor.submit(
            _fetch_safe182_facilities,
            lat,
            lng,
            radius_km,
        )

        accident_future = executor.submit(
            _fetch_accident_zones,
            lat,
            lng,
            radius_km,
        )

        try:
            safe_results = safe_future.result()

        except Exception as e:
            logger.warning(
                f"SAFE182 전체 조회 실패: {e}"
            )
            safe_results = []

        try:
            accident_results = accident_future.result()

        except Exception as e:
            logger.warning(
                f"사고다발지역 전체 조회 실패: {e}"
            )
            accident_results = []

    return (
        safe_results
        + accident_results
    )

def get_nearby_facilities(
    lat: float,
    lng: float,
    radius_km: float = 0.5,
):
    """
    생활안전지도 전체 조회
    - 반경 500m 고정
    - 캐시 사용
    - 전역 lock 사용 안 함
    """

    # 서버에서 무조건 500m
    radius_km = 0.5

    print(
        f"[생활안전지도] 요청 "
        f"lat={lat}, lng={lng}, "
        f"radius={radius_km}"
    )

    # 너무 세밀하게 좌표가 달라져서
    # 캐시가 계속 새로 생기는 것을 방지
    cache_lat = round(float(lat), 3)
    cache_lng = round(float(lng), 3)

    cache_key = (
        f"dasibom_facilities:"
        f"{cache_lat}:"
        f"{cache_lng}:"
        f"{radius_km}"
    )

    # --------------------------------------
    # 1. 캐시 있으면 바로 반환
    # --------------------------------------
    cached_results = cache.get(cache_key)

    if cached_results is not None:
        print(
            f"[생활안전지도] ⚡ 캐시 반환 "
            f"{cache_key}"
        )
        return cached_results

    # --------------------------------------
    # 2. 캐시 없으면 실제 조회
    # --------------------------------------
    results = _load_facilities(
        lat=lat,
        lng=lng,
        radius_km=radius_km,
    )

    # --------------------------------------
    # 3. 10분 캐시
    # --------------------------------------
    cache.set(
        cache_key,
        results,
        timeout=600,
    )

    print(
        f"[생활안전지도] 캐시 저장 "
        f"{cache_key}"
    )

    return results