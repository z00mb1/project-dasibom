import time
import threading
import board
import busio
from digitalio import DigitalInOut
from adafruit_pn532.spi import PN532_SPI
from flask import Flask, jsonify

app = Flask(__name__)

# 태그 감지 후 이 시간(초) 안에 읽어가지 않으면 신호를 자동 폐기한다.
# 리액트가 1초마다 폴링하므로 기능상 1초면 충분하고, 5초는 네트워크가
# 잠깐 튀는 경우를 위한 여유분이다. 이보다 길게 잡으면 태그만 해두고
# 자리를 뜬 사람의 신호를 다음 사람이 물려받게 되므로 늘리지 말 것.
BADGE_TTL_SEC = 5

# --- CORS 설정 ---
# 배포된 키오스크 페이지(https://...)에서 이 로컬 서버를 직접 호출하므로
# 다른 출처의 요청을 허용해야 한다.
@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
    # 크롬의 Private Network Access 사전 요청(preflight) 통과용
    response.headers['Access-Control-Allow-Private-Network'] = 'true'
    # 태깅 신호는 1회용이므로 브라우저나 프록시가 캐시하면 안 된다
    response.headers['Cache-Control'] = 'no-store'
    return response

# --- PN532 설정 (하드웨어 연결 방식에 따라 다를 수 있음) ---
spi = busio.SPI(board.SCK, board.MOSI, board.MISO)
cs_pin = DigitalInOut(board.D5)
pn532 = PN532_SPI(spi, cs_pin, debug=False)

ic, ver, rev, support = pn532.firmware_version
print(f"Found PN532 with firmware version: {ver}.{rev}")
pn532.SAM_configuration()

# --- 상태 관리 변수 ---
# NFC 감시 스레드가 쓰고 Flask 요청 스레드가 읽어가므로 락으로 보호한다.
# 값은 {"uid": "04a2...", "at": <감지 시각>} 이고, 대기 중에는 None.
_badge_lock = threading.Lock()
_badge = None

@app.route('/check')
def check_status():
    global _badge
    with _badge_lock:
        badge = _badge
        _badge = None  # 읽는 순간 소비한다. 같은 태그가 두 번 쓰이지 않는다.

    # 소비했더라도 너무 오래된 신호면 버린다.
    # 태그만 해두고 화면 앞을 떠난 경우, 그 신호를 다음 사람이
    # 물려받아 남의 위치를 공유하게 되는 것을 막는다.
    if badge is not None and (time.monotonic() - badge["at"]) <= BADGE_TTL_SEC:
        return jsonify({"status": "success", "uid": badge["uid"]})

    return jsonify({"status": "fail"})

def run_nfc_listener():
    global _badge
    print("Waiting for NFC badge...")
    while True:
        # 배지 감지 시도 (0.5초 대기)
        uid = pn532.read_passive_target(timeout=0.5)

        if uid is None:
            # 배지가 없으면 다시 감지 대기
            continue

        uid_hex = "".join(f"{b:02x}" for b in uid)
        print(f"[SUCCESS] Badge Detected! UID: {uid_hex}")

        # 시각은 monotonic 을 쓴다. 라즈베리파이는 RTC 가 없어서 부팅 후
        # NTP 가 붙는 순간 벽시계(time.time)가 훌쩍 점프하는데,
        # 그때 TTL 계산이 틀어지는 것을 막기 위함이다.
        with _badge_lock:
            _badge = {"uid": uid_hex, "at": time.monotonic()}

        time.sleep(2)  # 중복 인식 방지

# 플라스크 서버 실행 (별도 스레드로 돌려야 리더기와 동시에 작동함)
if __name__ == '__main__':
    # NFC 리더기를 계속 감시하는 스레드 시작
    nfc_thread = threading.Thread(target=run_nfc_listener, daemon=True)
    nfc_thread.start()

    # 리액트 프록시와 맞추기 위해 5000번 포트로 실행
    app.run(host='0.0.0.0', port=5000)
