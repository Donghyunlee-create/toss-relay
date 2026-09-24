#!/usr/bin/env bash
# Toss 읽기전용 릴레이 설치 스크립트 (Oracle Ubuntu VM, user=ubuntu)
# 멱등: 여러 번 실행해도 안전. 서버에서: cd ~/toss-relay && bash setup.sh
set -euo pipefail

INSTALL_DIR="/home/ubuntu/toss-relay"
SERVICE_NAME="toss-relay"
CADDY_SITE="/etc/caddy/Caddyfile"
ENV_FILE="${INSTALL_DIR}/.env"
UNIT_DST="/etc/systemd/system/${SERVICE_NAME}.service"

red()  { printf '\033[1;31m%s\033[0m\n' "$*"; }
green(){ printf '\033[1;32m%s\033[0m\n' "$*"; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '→ %s\n' "$*"; }

die() { red "오류: $*"; exit 1; }

need_ubuntu_user() {
  if [[ "$(id -u)" -eq 0 ]]; then
    die "root 로 실행하지 마세요. ubuntu 사용자로 실행하세요: bash setup.sh"
  fi
}

# --- 0. 사전 확인 -----------------------------------------------------------
need_ubuntu_user

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "${SCRIPT_DIR}/app.py" ]]; then
  die "이 스크립트 옆에 app.py 가 없습니다.
  서버에서 다음처럼 준비했는지 확인하세요:
    cd ~/toss-relay   (git clone 또는 zip 을 푼 폴더)
    bash setup.sh
  현재 위치: ${SCRIPT_DIR}"
fi

if [[ "$(whoami)" != "ubuntu" ]]; then
  info "경고: 현재 사용자가 'ubuntu' 가 아닙니다 ($(whoami)). 계속 진행합니다."
fi

bold "=== Toss 읽기전용 릴레이 설치를 시작합니다 ==="

# --- 1. 패키지 --------------------------------------------------------------
info "시스템 패키지 설치 중..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq \
  python3 python3-venv python3-pip curl ca-certificates rsync \
  debian-keyring debian-archive-keyring apt-transport-https gnupg \
  iptables iptables-persistent >/dev/null

# Caddy (공식 apt 저장소)
if ! command -v caddy >/dev/null 2>&1; then
  info "Caddy 설치 중..."
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq caddy >/dev/null
fi

# --- 2. 앱 파일 배치 --------------------------------------------------------
info "앱 파일을 ${INSTALL_DIR} 에 복사합니다..."
sudo mkdir -p "${INSTALL_DIR}"
sudo chown ubuntu:ubuntu "${INSTALL_DIR}"

# SCRIPT_DIR 이 이미 INSTALL_DIR 이면 복사 생략 (그 자리에서 실행한 경우)
if [[ "${SCRIPT_DIR}" != "${INSTALL_DIR}" ]]; then
  rsync -a \
    --exclude '.venv/' \
    --exclude '.env' \
    --exclude '__pycache__/' \
    --exclude '.pytest_cache/' \
    --exclude '*.pyc' \
    "${SCRIPT_DIR}/" "${INSTALL_DIR}/"
else
  info "이미 ${INSTALL_DIR} 에서 실행 중입니다. 파일 복사 생략."
fi

# --- 3. Python venv ---------------------------------------------------------
info "Python 가상환경 준비..."
if [[ ! -d "${INSTALL_DIR}/.venv" ]]; then
  python3 -m venv "${INSTALL_DIR}/.venv"
fi
# shellcheck disable=SC1091
source "${INSTALL_DIR}/.venv/bin/activate"
pip install -q --upgrade pip
pip install -q -r "${INSTALL_DIR}/requirements.txt"

# --- 4. 자격증명 입력 -------------------------------------------------------
prompt_secret() {
  # /dev/tty 사용 → bash <(curl ...) 파이프 실행에도 안전
  local var_name="$1" prompt="$2" value=""
  printf '%s' "$prompt" > /dev/tty
  # shellcheck disable=SC2162
  IFS= read -r -s value < /dev/tty || true
  printf '\n' > /dev/tty
  printf -v "$var_name" '%s' "$value"
}

prompt_line() {
  local var_name="$1" prompt="$2" value=""
  printf '%s' "$prompt" > /dev/tty
  # shellcheck disable=SC2162
  IFS= read -r value < /dev/tty || true
  printf -v "$var_name" '%s' "$value"
}

TOSS_CLIENT_ID=""
TOSS_CLIENT_SECRET=""
RELAY_TOKEN=""
TOSS_ACCOUNT_SEQ=""

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
  info "기존 .env 를 발견했습니다."
  keep="y"
  prompt_line keep "기존 설정을 유지할까요? [Y/n]: "
  keep="${keep:-y}"
  if [[ ! "${keep}" =~ ^[Yy]$ ]]; then
    TOSS_CLIENT_ID=""
    TOSS_CLIENT_SECRET=""
    RELAY_TOKEN=""
    TOSS_ACCOUNT_SEQ=""
  fi
fi

if [[ -z "${TOSS_CLIENT_ID}" ]]; then
  prompt_line TOSS_CLIENT_ID "토스 Open API client_id 를 붙여넣으세요: "
fi
if [[ -z "${TOSS_CLIENT_SECRET}" ]]; then
  prompt_secret TOSS_CLIENT_SECRET "토스 Open API client_secret 을 붙여넣으세요 (화면에 안 보임): "
fi
[[ -n "${TOSS_CLIENT_ID}" ]] || die "client_id 가 비어 있습니다."
[[ -n "${TOSS_CLIENT_SECRET}" ]] || die "client_secret 이 비어 있습니다."

if [[ -z "${RELAY_TOKEN}" ]]; then
  RELAY_TOKEN="$(openssl rand -hex 32)"
  info "릴레이 토큰을 새로 만들었습니다."
fi

# --- 5. .env 기록 -----------------------------------------------------------
info ".env 작성 (권한 600)..."
umask 077
cat > "${ENV_FILE}" <<EOF
RELAY_TOKEN=${RELAY_TOKEN}
TOSS_CLIENT_ID=${TOSS_CLIENT_ID}
TOSS_CLIENT_SECRET=${TOSS_CLIENT_SECRET}
TOSS_ACCOUNT_SEQ=${TOSS_ACCOUNT_SEQ}
EOF
chmod 600 "${ENV_FILE}"
chown ubuntu:ubuntu "${ENV_FILE}" 2>/dev/null || true

# --- 6. 공인 IP 탐지 --------------------------------------------------------
detect_public_ip() {
  local ip=""
  ip="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "${ip}" ]]; then
    # OCI 인스턴스 메타데이터 (Authorization: Bearer Oracle)
    ip="$(curl -fsS --max-time 3 -H 'Authorization: Bearer Oracle' \
      'http://169.254.169.254/opc/v2/vnics/' 2>/dev/null \
      | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(d, list):
    for x in d:
        if x.get("publicIp"):
            print(x["publicIp"])
            break
' 2>/dev/null || true)"
  fi
  printf '%s' "${ip}"
}

info "공인 IP 확인 중..."
PUBLIC_IP="$(detect_public_ip)"
[[ -n "${PUBLIC_IP}" ]] || die "공인 IP 를 찾지 못했습니다. 인스턴스에 Public IP 가 붙어 있는지 확인하세요."
SSIP_HOST="$(printf '%s' "${PUBLIC_IP}" | tr '.' '-')".sslip.io
info "공인 IP: ${PUBLIC_IP}"
info "HTTPS 주소: https://${SSIP_HOST}"

# --- 7. iptables (Oracle Ubuntu REJECT 앞에 삽입) ---------------------------
open_tcp_port() {
  local port="$1"
  # 동일 규칙이 이미 있으면 스킵 (멱등)
  if sudo iptables -C INPUT -p tcp -m state --state NEW --dport "${port}" -j ACCEPT 2>/dev/null; then
    info "iptables: 포트 ${port} 이미 허용됨"
    return 0
  fi
  local reject_line
  reject_line="$(sudo iptables -L INPUT --line-numbers -n \
    | awk '/REJECT|DROP/ {print $1; exit}')"
  if [[ -n "${reject_line}" ]]; then
    sudo iptables -I INPUT "${reject_line}" -p tcp -m state --state NEW \
      --dport "${port}" -j ACCEPT
  else
    sudo iptables -A INPUT -p tcp -m state --state NEW --dport "${port}" -j ACCEPT
  fi
  info "iptables: 포트 ${port} 허용"
}

info "방화벽(iptables)에서 80/443 열기..."
open_tcp_port 80
open_tcp_port 443
# 비대화형 저장
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo mkdir -p /etc/iptables
sudo sh -c 'iptables-save > /etc/iptables/rules.v4'
sudo sh -c 'ip6tables-save > /etc/iptables/rules.v6' 2>/dev/null || true
if command -v netfilter-persistent >/dev/null 2>&1; then
  sudo netfilter-persistent save >/dev/null 2>&1 || true
fi

# --- 8. Caddy ---------------------------------------------------------------
info "Caddy HTTPS 설정 (${SSIP_HOST})..."
sudo tee "${CADDY_SITE}" >/dev/null <<EOF
${SSIP_HOST} {
	reverse_proxy 127.0.0.1:8000
	encode gzip
	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains"
		X-Content-Type-Options nosniff
		Referrer-Policy no-referrer
		-Server
	}
}
EOF
sudo systemctl enable caddy >/dev/null
sudo systemctl restart caddy

# --- 9. systemd -------------------------------------------------------------
info "systemd 서비스 등록..."
sudo tee "${UNIT_DST}" >/dev/null <<EOF
[Unit]
Description=Toss Securities read-only Open API relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${INSTALL_DIR}/.venv/bin/uvicorn app:app --host 127.0.0.1 --port 8000
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" >/dev/null
sudo systemctl restart "${SERVICE_NAME}"

# 기동 대기
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS --max-time 2 http://127.0.0.1:8000/healthz >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -fsS --max-time 3 http://127.0.0.1:8000/healthz >/dev/null \
  || die "릴레이가 시작되지 않았습니다. 로그: sudo journalctl -u ${SERVICE_NAME} -n 50 --no-pager"

# --- 10. 변경 API 차단 확인 -------------------------------------------------
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  -H "Authorization: Bearer ${RELAY_TOKEN}" \
  http://127.0.0.1:8000/api/v1/orders || true)"
if [[ "${code}" != "405" ]]; then
  die "안전 검사 실패: POST /api/v1/orders 가 405 가 아니라 ${code} 입니다."
fi
green "안전 검사 통과: POST /api/v1/orders → 405 (토스에 전달 안 됨)"

# --- 11. accountSeq 자동 발견 ----------------------------------------------
info "토스 계좌 목록 조회 중 (허용 IP 등록이 필요할 수 있음)..."
ACCOUNTS_RAW="$(curl -sS -w '\n%{http_code}' \
  -H "Authorization: Bearer ${RELAY_TOKEN}" \
  http://127.0.0.1:8000/api/v1/accounts || true)"
HTTP_CODE="$(printf '%s' "${ACCOUNTS_RAW}" | tail -n1)"
ACCOUNTS_BODY="$(printf '%s' "${ACCOUNTS_RAW}" | sed '$d')"

if [[ "${HTTP_CODE}" == "403" ]]; then
  red "============================================================"
  red "토스가 이 서버 IP 를 거부했습니다 (403)."
  red "토스증권 WTS → 설정 → Open API → 허용 IP 관리 에"
  red "  아래 IP 를 등록하세요:"
  bold "  ${PUBLIC_IP}"
  red "등록한 뒤 이 서버에서 다시 실행하세요:"
  bold "  cd ${INSTALL_DIR} && bash setup.sh"
  red "(물으면 기존 설정 유지 Y)"
  red "============================================================"
  exit 2
fi

if [[ "${HTTP_CODE}" != "200" ]]; then
  red "계좌 조회 실패 (HTTP ${HTTP_CODE}). 응답:"
  printf '%s\n' "${ACCOUNTS_BODY}" | head -c 500; echo
  die "client_id/secret 또는 네트워크를 확인한 뒤 setup.sh 를 다시 실행하세요."
fi

NEW_SEQ="$(printf '%s' "${ACCOUNTS_BODY}" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("", end="")
    raise SystemExit(0)
result = d.get("result") or []
if not result:
    print("", end="")
    raise SystemExit(0)
for a in result:
    if a.get("accountType") == "BROKERAGE" and a.get("accountSeq") is not None:
        print(a["accountSeq"])
        raise SystemExit(0)
print(result[0].get("accountSeq", ""), end="")
')"

if [[ -z "${NEW_SEQ}" ]]; then
  red "계좌가 비어 있습니다. 토스증권 종합매매 계좌가 있는지 확인하세요."
  die "accountSeq 를 자동으로 찾지 못했습니다."
fi

# .env 갱신 + 재시작
TOSS_ACCOUNT_SEQ="${NEW_SEQ}"
umask 077
cat > "${ENV_FILE}" <<EOF
RELAY_TOKEN=${RELAY_TOKEN}
TOSS_CLIENT_ID=${TOSS_CLIENT_ID}
TOSS_CLIENT_SECRET=${TOSS_CLIENT_SECRET}
TOSS_ACCOUNT_SEQ=${TOSS_ACCOUNT_SEQ}
EOF
chmod 600 "${ENV_FILE}"
sudo systemctl restart "${SERVICE_NAME}"
sleep 1
info "TOSS_ACCOUNT_SEQ=${TOSS_ACCOUNT_SEQ} 저장 완료"

# --- 12. 요약 ---------------------------------------------------------------
echo
green "╔════════════════════════════════════════════════════════════╗"
green "║  설치 완료!                                                ║"
green "╠════════════════════════════════════════════════════════════╣"
printf '║  서버 주소: https://%-38s ║\n' "${SSIP_HOST}"
printf '║  공인 IP  : %-44s ║\n' "${PUBLIC_IP}"
printf '║  계좌 Seq : %-44s ║\n' "${TOSS_ACCOUNT_SEQ}"
green "╠════════════════════════════════════════════════════════════╣"
green "║  ★ 릴레이 토큰 (채팅에 붙여넣지 마세요)                     ║"
green "║  어시스턴트가 보내는 '보안 입력란'에만 넣으세요.             ║"
green "╚════════════════════════════════════════════════════════════╝"
echo
bold "RELAY_TOKEN (복사용):"
echo "${RELAY_TOKEN}"
echo
info "채팅에는 서버 주소만 보내세요: https://${SSIP_HOST}"
info "토큰은 채팅이 아니라 보안 입력란에만 넣습니다."
echo
