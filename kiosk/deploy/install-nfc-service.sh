#!/usr/bin/env bash
#
# 라즈베리파이 부팅 시 nfc_server.py 가 자동으로 뜨도록 systemd 서비스를 등록한다.
#
# 사용법 (라즈베리파이에서):
#   cd ~/kiosk/deploy
#   bash install-nfc-service.sh
#
set -euo pipefail

SERVICE_NAME="nfc-server"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/${SERVICE_NAME}.service"
TARGET="/etc/systemd/system/${SERVICE_NAME}.service"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m [!] %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m [v] %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m [x] %s\033[0m\n' "$*" >&2; exit 1; }

# --- 1. 필요한 파일이 다 있는지 ---------------------------------------------
say "파일 확인"
[ -f "$PROJECT_DIR/nfc_server.py" ] || die "nfc_server.py 를 찾을 수 없습니다: $PROJECT_DIR"
[ -f "$TEMPLATE" ]                  || die "서비스 템플릿이 없습니다: $TEMPLATE"
ok "nfc_server.py  -> $PROJECT_DIR/nfc_server.py"

command -v systemctl >/dev/null 2>&1 || die "systemd 가 없는 시스템입니다. 라즈베리파이에서 실행하세요."

RUN_USER="$(id -un)"
[ "$RUN_USER" != "root" ] || warn "root 로 실행 중입니다. 평소 쓰는 계정으로 실행하는 걸 권장합니다."
ok "실행 계정      -> $RUN_USER"

# --- 2. 파이썬 고르기 (가상환경이 있으면 그걸 우선) --------------------------
say "파이썬 확인"
if   [ -x "$PROJECT_DIR/venv/bin/python" ];  then PYTHON="$PROJECT_DIR/venv/bin/python"
elif [ -x "$PROJECT_DIR/.venv/bin/python" ]; then PYTHON="$PROJECT_DIR/.venv/bin/python"
elif command -v python3 >/dev/null 2>&1;     then PYTHON="$(command -v python3)"
else die "python3 를 찾을 수 없습니다."
fi
ok "파이썬         -> $PYTHON"

# 라이브러리가 실제로 import 되는지 미리 확인 (여기서 걸러야 부팅 후 헤매지 않음)
MISSING=""
for mod in board busio digitalio adafruit_pn532.spi flask; do
    "$PYTHON" -c "import $mod" >/dev/null 2>&1 || MISSING="$MISSING $mod"
done
if [ -n "$MISSING" ]; then
    warn "import 안 되는 모듈:$MISSING"
    warn "먼저 설치하세요:"
    warn "  $PYTHON -m pip install adafruit-blinka adafruit-circuitpython-pn532 flask"
    warn "  (Bookworm 이상에서 'externally-managed-environment' 오류가 나면 --break-system-packages 를 붙이거나 venv 를 만드세요)"
    warn "서비스 등록은 계속 진행합니다. 라이브러리 설치 후 재시작하면 정상 동작합니다."
else
    ok "필요한 라이브러리 전부 확인됨"
fi

# --- 3. SPI 활성화 여부 ------------------------------------------------------
say "SPI 확인"
if ls /dev/spidev* >/dev/null 2>&1; then
    ok "SPI 장치 있음 -> $(ls /dev/spidev* | tr '\n' ' ')"
else
    warn "/dev/spidev* 가 없습니다. SPI 가 꺼져 있습니다."
    warn "  sudo raspi-config  ->  Interface Options  ->  SPI  ->  Yes  ->  재부팅"
fi

# 리더기 접근에 필요한 그룹에 넣어준다 (이미 속해 있으면 넘어감)
for grp in spi gpio; do
    if getent group "$grp" >/dev/null 2>&1; then
        if id -nG "$RUN_USER" | tr ' ' '\n' | grep -qx "$grp"; then
            ok "$RUN_USER 는 이미 '$grp' 그룹"
        else
            sudo usermod -aG "$grp" "$RUN_USER"
            warn "$RUN_USER 를 '$grp' 그룹에 추가했습니다 (재부팅 후 적용)"
        fi
    fi
done

# --- 4. 서비스 파일 생성 및 등록 --------------------------------------------
say "서비스 등록"
TMP="$(mktemp)"
sed -e "s|__USER__|$RUN_USER|g" \
    -e "s|__WORKDIR__|$PROJECT_DIR|g" \
    -e "s|__PYTHON__|$PYTHON|g" \
    "$TEMPLATE" > "$TMP"

sudo cp "$TMP" "$TARGET"
rm -f "$TMP"
sudo chmod 644 "$TARGET"
ok "설치됨        -> $TARGET"

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"          # 부팅 시 자동 시작
sudo systemctl restart "$SERVICE_NAME"         # 지금 바로 시작
ok "부팅 자동 시작 활성화"

# --- 5. 결과 확인 ------------------------------------------------------------
say "상태"
sleep 2
sudo systemctl status "$SERVICE_NAME" --no-pager --lines=15 || true

cat <<EOF

------------------------------------------------------------
 등록 완료. 이제 전원을 켜면 자동으로 뜹니다.

 상태 보기    : sudo systemctl status $SERVICE_NAME
 실시간 로그  : journalctl -u $SERVICE_NAME -f
 다시 시작    : sudo systemctl restart $SERVICE_NAME
 잠시 끄기    : sudo systemctl stop $SERVICE_NAME
 자동시작 해제: sudo systemctl disable $SERVICE_NAME

 동작 확인    : curl http://127.0.0.1:5000/check
                -> {"status":"fail"} 이 나오면 정상 (뱃지 대면 success)
------------------------------------------------------------
EOF
