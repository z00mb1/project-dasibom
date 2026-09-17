import requests

SAFE182_USER_ID = "10000901"
SAFE182_API_KEY = "30fa8fd93f5d4af7"

url = "https://www.safe182.go.kr/api/lcm/safeMap.do"

data = {
    "esntlId": SAFE182_USER_ID,
    "authKey": SAFE182_API_KEY,
    "pageIndex": "1",
    "pageUnit": "10",
}

response = requests.post(url, data=data, timeout=10)

print("STATUS:", response.status_code)
print("HEADERS:", response.headers.get("Content-Type"))
print("RAW TEXT:")
print(response.text[:1000])  # 너무 길면 앞
