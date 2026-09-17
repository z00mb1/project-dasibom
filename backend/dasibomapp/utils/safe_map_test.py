import requests

URL = "https://www.safe182.go.kr/api/lcm/safeMap.do"

headers = {
    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    "Referer": "https://www.safe182.go.kr/",
    "Origin": "https://www.safe182.go.kr",
    "Accept": "application/json, text/plain, */*",
}

payload = [
    ("esntlId", "10000901"),
    ("authKey", "30fa8fd93f5d4af7"),
    ("pageIndex", "1"),
    ("pageUnit", "10"),
    ("minY", "37.56"),
    ("maxY", "37.57"),
    ("minX", "126.97"),
    ("maxX", "126.99"),
    ("xmlUseYN", "N"),
    ("clArray[]", "09"),
    ("clArray[]", "17"),
    ("clArray[]", "18"),
    ("clArray[]", "19"),
    ("clArray[]", "20"),
    ("clArray[]", "22"),
    ("clArray[]", "23"),
]

res = requests.post(URL, data=payload, headers=headers, timeout=10)

print("STATUS:", res.status_code)
print("\n===== RAW RESPONSE =====")
print(res.text[:1500])
