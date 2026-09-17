import math

# 1km 당 위도 약 0.009도
def get_bbox(lat, lng, radius_km):
    lat_delta = radius_km / 111
    lng_delta = radius_km / (111 * math.cos(math.radians(lat)))

    return {
        "minLat": lat - lat_delta,
        "maxLat": lat + lat_delta,
        "minLng": lng - lng_delta,
        "maxLng": lng + lng_delta,
    }
