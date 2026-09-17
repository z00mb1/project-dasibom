#!/usr/bin/env bash
#
# 리더기 서버(127.0.0.1:5000)를 zrok 공개 터널로 내보내고, 부팅할 때마다
# 자동으로 다시 붙도록 systemd 서비스를 등록한다.
#
# 왜 필요한가:
#   https 로 배포된 페이지(Vercel)가 http://127.0.0.1:5000 을 직접 부르는 구성은
#   크롬 142 부터 "로컬 네트워크 접근" 권한 없이는 통째로 차단된다.
#   백엔드(dasibom-api)와 똑같이 리더기도 https 주소를 갖게 만들어 그 문제를 피한다.
#
# 사용법 (라즈베리파이에서):
#   cd ~/kiosk/deploy
#   bash install-zrok-tunnel.sh              # 기본 이름: dasibom-nfc
#   bash install-zrok-tunnel.sh 원하는이름
#
# 등록이 끝나면 .env.production 의 REACT_APP_NFC_URL 을 여기서 찍어주는
# 주소와 똑같이 맞춘 뒤 다시 배포해야 한다.
#
set -euo pipefail

SHARE_NAME="${1:-dasibom-nfc}"
TARGET="127.0.0.1:5000"
SERVICE_NAME="zrok-nfc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/${SERVICE_NAME}.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m [!] %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m [v] %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m [x] %s\033[0m\n' "$*" >&2; exit 1; }

# --- 1. zrok 준비 상태 확인 -------------------------------------------------
say "zrok 확인"
command -v zrok >/dev/null 2>&1 || die "zrok 가 설치되어 있지 않습니다. https://docs.zrok.io 참고"
ZROK="$(command -v zrok)"
ok "zrok           -> $ZROK"

RUN_USER="$(id -un)"
RUN_HOME="$HOME"
ok "실행 계정      -> $RUN_USER ($RUN_HOME)"

# zrok enable 을 한 번이라도 했다면 ~/.zrok/environment.json 이 생긴다.
# 이게 없으면 터널을 만들 수 없다.
[ -f "$RUN_HOME/.zrok/environment.json" ] \
    || die "이 계정에서 zrok 환경이 켜져 있지 않습니다. 먼저 실행하세요: zrok enable <계정토큰>"
ok "zrok 환경      -> 사용 가능"

# --- 2. 리더기 서버가 떠 있는지 ---------------------------------------------
say "리더기 서버 확인"
if curl -fsS --max-time 3 "http://$TARGET/check" >/dev/null 2>&1; then
    ok "$TARGET 응답함"
else
    warn "$TARGET 이 응답하지 않습니다. nfc-server 서비스를 먼저 띄우세요:"
    warn "  sudo systemctl restart nfc-server && journalctl -u nfc-server -f"
    warn "터널 등록은 계속 진행합니다 (리더기 서버가 나중에 떠도 연결됩니다)."
fi

# --- 3. 고정 이름 터널 예약 --------------------------------------------------
# 예약(reserve)해 두면 재부팅해도 주소가 바뀌지 않는다. 이미 있으면 그대로 쓴다.
say "터널 예약 ($SHARE_NAME)"
if zrok overview 2>/dev/null | grep -q "\"$SHARE_NAME\""; then
    ok "이미 예약된 이름입니다. 그대로 사용합니다."
else
    if zrok reserve public "$TARGET" --unique-name "$SHARE_NAME"; then
        ok "예약 완료"
    else
        die "예약에 실패했습니다. 이름이 이미 남에게 선점되었을 수 있으니 다른 이름으로 다시 실행하세요:
     bash install-zrok-tunnel.sh dasibom-nfc-2"
    fi
fi

PUBLIC_URL="https://${SHARE_NAME}.shares.zrok.io"

# --- 4. systemd 서비스 등록 --------------------------------------------------
say "서비스 등록"
[ -f "$TEMPLATE" ] || die "서비스 템플릿이 없습니다: $TEMPLATE"

TMP="$(mktemp)"
sed -e "s|__USER__|$RUN_USER|g" \
    -e "s|__HOME__|$RUN_HOME|g" \
    -e "s|__ZROK__|$ZROK|g" \
    -e "s|__SHARE__|$SHARE_NAME|g" \
    "$TEMPLATE" > "$TMP"

sudo cp "$TMP" "$SERVICE_PATH"
rm -f "$TMP"
sudo chmod 644 "$SERVICE_PATH"
ok "설치됨        -> $SERVICE_PATH"

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"
ok "부팅 자동 시작 활성화"

# --- 5. 결과 확인 ------------------------------------------------------------
say "연결 확인"
sleep 5
if curl -fsS --max-time 10 "$PUBLIC_URL/check" 2>/dev/null | grep -q '"status"'; then
    ok "$PUBLIC_URL/check 정상 응답"
else
    warn "$PUBLIC_URL/check 응답이 없습니다. 로그를 확인하세요:"
    warn "  journalctl -u $SERVICE_NAME -n 30 --no-pager"
fi

cat <<EOF

------------------------------------------------------------
 리더기 공개 주소 : $PUBLIC_URL

 남은 작업 (개발 PC에서):
   1) .env.production 의 REACT_APP_NFC_URL 을 위 주소로 맞춘다
   2) 다시 빌드해서 배포한다  (npm run build → vercel --prod)

 상태 보기   : sudo systemctl status $SERVICE_NAME
 실시간 로그 : journalctl -u $SERVICE_NAME -f
 다시 시작   : sudo systemctl restart $SERVICE_NAME
------------------------------------------------------------
EOF
