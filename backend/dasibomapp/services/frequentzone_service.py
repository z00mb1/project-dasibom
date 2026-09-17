# dasibomapp/services/frequentzone_service.py

import math
import requests

from django.conf import settings
from dasibomapp.utils.region_code import get_region_code_by_location


FREQUENTZONE_REST_URL = (
    "http://apis.data.go.kr/B552061/frequentzoneLg/getRestFrequentzoneLg"
)

# 사고다발지역 조회 코드
DEFAULT_SEARCH_YEAR_CD = "2025119"


def haversine_km(lat1, lng1, lat2, lng2):
    """
    두 좌표 사이의 거리(km)를 계산한다.
    """
    earth_radius_km = 6371.0

    lat1_rad = math.radians(lat1)
    lng1_rad = math.radians(lng1)
    lat2_rad = math.radians(lat2)
    lng2_rad = math.radians(lng2)

    dlat = lat2_rad - lat1_rad
    dlng = lng2_rad - lng1_rad

    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(lat1_rad)
        * math.cos(lat2_rad)
        * math.sin(dlng / 2) ** 2
    )

    c = 2 * math.atan2(
        math.sqrt(a),
        math.sqrt(1 - a)
    )

    return earth_radius_km * c


def safe_int(value, default=0):
    """
    API 응답값을 안전하게 int로 변환한다.
    """
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def get_accident_frequent_zones(
    lat: float,
    lng: float,
    radius_km: float = 3.0
):
    print("=" * 70)
    print(
        f"[사고다발지역] 입력 좌표 "
        f"lat={lat}, lng={lng}"
    )

    # --------------------------------------------------
    # 1. 현재 GPS 좌표 → 시도/구군 코드 변환
    # --------------------------------------------------
    region = get_region_code_by_location(
        lat=lat,
        lng=lng
    )

    if not region:
        print(
            "[사고다발지역] "
            "좌표에 해당하는 region_code 매핑 실패"
        )
        return []

    print(
        f"[사고다발지역] region={region}"
    )

    sido = region.get("sido")
    gugun = region.get("gugun")

    if not sido or not gugun:
        print(
            "[사고다발지역] "
            f"잘못된 지역 코드 sido={sido}, gugun={gugun}"
        )
        return []

    # --------------------------------------------------
    # 2. 공공데이터 사고다발지역 API 요청
    # --------------------------------------------------
    params = {
        "ServiceKey": settings.FREQUENTZONE_API_KEY,
        "searchYearCd": DEFAULT_SEARCH_YEAR_CD,
        "siDo": sido,
        "guGun": gugun,
        "type": "json",
        "numOfRows": "100",
        "pageNo": "1",
    }

    try:
        resp = requests.get(
            FREQUENTZONE_REST_URL,
            params=params,
            timeout=10
        )

        print(
            "[사고다발지역] request url:",
            resp.url
        )
        print(
            "[사고다발지역] status:",
            resp.status_code
        )
        print(
            "[사고다발지역] content-type:",
            resp.headers.get("Content-Type")
        )
        print(
            "[사고다발지역] body:",
            resp.text[:500]
        )

        resp.raise_for_status()

        data = resp.json()

    except requests.RequestException as e:
        print(
            "[사고다발지역] HTTP 요청 실패:",
            e
        )
        return []

    except ValueError as e:
        print(
            "[사고다발지역] JSON 파싱 실패:",
            e
        )
        return []

    # --------------------------------------------------
    # 3. 응답 items 추출
    # --------------------------------------------------
    if "response" in data:
        body = (
            data
            .get("response", {})
            .get("body", {})
        )

        items_obj = body.get(
            "items",
            {}
        )

        items = items_obj.get(
            "item",
            []
        )

    else:
        items_obj = data.get(
            "items",
            {}
        )

        items = items_obj.get(
            "item",
            []
        )

    # API에서 item 하나만 있을 때 dict로 오는 경우 대응
    if isinstance(items, dict):
        items = [items]

    if not isinstance(items, list):
        items = []

    print(
        f"[사고다발지역] "
        f"파싱된 items 개수={len(items)}"
    )

    # --------------------------------------------------
    # 4. 현재 위치와 실제 거리 계산
    # --------------------------------------------------
    results = []

    for item in items:

        try:
            zone_lat = float(
                item.get("la_crd")
            )

            zone_lng = float(
                item.get("lo_crd")
            )

        except (TypeError, ValueError):
            print(
                "[사고다발지역] "
                "좌표 없는 항목 제외:",
                item.get("spot_nm")
            )
            continue

        distance = haversine_km(
            lat,
            lng,
            zone_lat,
            zone_lng
        )

        print(
            "[사고다발지역] 후보:",
            item.get("spot_nm"),
            "lat=",
            zone_lat,
            "lng=",
            zone_lng,
            "distanceKm=",
            round(distance, 3)
        )

        # 설정된 반경보다 멀면 제외
        if distance > radius_km:
            continue

        results.append({
            "id": (
                f"accident_"
                f"{item.get('afos_fid') or item.get('spot_cd')}"
            ),

            "name": item.get("spot_nm"),

            "categoryName": "교통사고 다발지역",

            "code": "ACCIDENT_FREQUENT_ZONE",

            # 프론트 마커 구분용
            "type": "danger",

            "dangerType": "traffic_accident",

            "address": item.get("spot_nm"),

            "tel": "정보 없음",

            "lat": zone_lat,

            "lng": zone_lng,

            # 상세 정보
            "regionName": item.get("sido_sgg_nm"),

            "accidentCount": safe_int(
                item.get("occrrnc_cnt")
            ),

            "casualtyCount": safe_int(
                item.get("caslt_cnt")
            ),

            "deathCount": safe_int(
                item.get("dth_dnv_cnt")
            ),

            "seriousInjuryCount": safe_int(
                item.get("se_dnv_cnt")
            ),

            "minorInjuryCount": safe_int(
                item.get("sl_dnv_cnt")
            ),

            "injuryReportCount": safe_int(
                item.get("wnd_dnv_cnt")
            ),

            "distanceKm": round(
                distance,
                3
            ),
        })

    print(
        f"[사고다발지역] "
        f"최종 반환 results={len(results)}"
    )

    print("=" * 70)

    return results