# Toss 증권 읽기 전용 릴레이

비개발자용 클릭 안내서는 [`GUIDE.md`](GUIDE.md), 서버 원클릭 설치는 [`setup.sh`](setup.sh) 를 보세요.

토스 Open API 키는 **이 서버에만** 두고, 어시스턴트에는 릴레이용 `RELAY_TOKEN`만 줍니다.  
허용된 **GET** 만 전달하며, 주문 생성/정정/취소 등 변경 API는 **로컬에서 405/404로 거절**하고 토스에 요청하지 않습니다.

## 구성 파일

| 파일 | 설명 |
|------|------|
| `app.py` | FastAPI 릴레이 (~150줄, 감사 가능) |
| `requirements.txt` | Python 의존성 |
| `.env.example` | 환경변수 템플릿 |
| `toss-relay.service` | systemd 유닛 |
| `Caddyfile` | HTTPS 리버스 프록시 |
| `tests/` | 변경 API 차단 테스트 |

## 1. Oracle Cloud Always Free VM (서울)

1. [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/) 가입  
   - **홈 리전은 가입 시 고정** → `South Korea Central (Seoul)` / `ap-seoul-1` 선택  
   - 카드·휴대폰 본인확인 필요(Always Free만 쓰면 과금 없음)  
2. Compute → Create instance  
   - Image: **Ubuntu 22.04/24.04** (Always Free Eligible)  
   - Shape: `VM.Standard.E2.1.Micro`(AMD) 또는 용량 있으면 `VM.Standard.A1.Flex`(Ampere, 예: 1 OCPU / 6GB)  
   - **주의:** Chuncheon(`ap-chuncheon-1`)에서는 Ampere A1 생성 불가. 홈 리전을 잘못 고르면 Always Free 인스턴스를 서울에 못 만듦.  
   - VCN: Public subnet + Internet Gateway, **Assign public IPv4**  
3. 생성 후 Networking → 해당 VNIC → **Reserved public IP** 로 전환(고정 IP, OCI에서 별도 과금 없음)  
4. VCN Security List / NSG: Ingress `0.0.0.0/0` → TCP **22**, **443** (필요 시 80)  
5. SSH: `ssh -i ~/.ssh/your_key ubuntu@<PUBLIC_IP>`

### Ubuntu 방화벽 (중요)

Oracle Ubuntu 이미지는 **iptables가 443을 막는 경우가 많습니다.** Security List만 열면 부족합니다.

```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo netfilter-persistent save   # 패키지 없으면: sudo apt install iptables-persistent
# 또는 ufw 사용 시:
# sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw enable
```

## 2. 릴레이 설치

비개발자용 원클릭(권장): Ubuntu VM에 SSH 접속한 뒤 **한 줄**:

```bash
sudo apt-get install -y git >/dev/null 2>&1; git clone https://github.com/Donghyunlee-create/toss-relay.git ~/toss-relay 2>/dev/null || git -C ~/toss-relay pull; cd ~/toss-relay && bash setup.sh
```

`setup.sh` 가 venv·의존성·`.env`·systemd·Caddy(HTTPS)까지 처리합니다. 수동 설치가 필요하면:

```bash
sudo apt update && sudo apt install -y python3-venv python3-pip git curl
cd ~
git clone https://github.com/Donghyunlee-create/toss-relay.git ~/toss-relay
cd ~/toss-relay
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
openssl rand -hex 32   # 출력값을 RELAY_TOKEN 에 넣기
nano .env              # TOSS_CLIENT_ID / TOSS_CLIENT_SECRET / TOSS_ACCOUNT_SEQ / RELAY_TOKEN
```

`TOSS_ACCOUNT_SEQ`: WTS에서 Open API 키 발급 후, 허용 IP에 **이 VM의 Reserved Public IP** 등록 →  
로컬에서(또는 임시로 VM에서) `GET /api/v1/accounts` 로 `accountSeq` 확인.

systemd:

```bash
sudo cp toss-relay.service /etc/systemd/system/
# User/경로가 ubuntu 가 아니면 유닛 파일 수정
sudo systemctl daemon-reload
sudo systemctl enable --now toss-relay
sudo systemctl status toss-relay
```

## 3. HTTPS (Caddy)

도메인이 있으면 A 레코드를 VM IP에 연결.  
없으면 **sslip.io / nip.io** 사용 (예: IP `130.162.1.2` → `https://130-162-1-2.sslip.io`).

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install -y caddy

# Caddyfile 의 호스트명을 본인 도메인 또는 sslip.io 로 수정
sudo cp Caddyfile /etc/caddy/Caddyfile
# 또는: RELAY_HOSTNAME=130-162-1-2.sslip.io 를 환경에 넣고 기존 Caddyfile 사용
sudo systemctl reload caddy
```

## 4. 토스 허용 IP

WTS → **설정 → Open API → 허용 IP 관리**에 VM **Reserved Public IP** 등록.  
미등록 시 토스가 403을 반환합니다.

## 5. 동작 확인

```bash
# 헬스
curl -s https://<호스트>/healthz

# 읽기 (계좌/잔고 등) — RELAY_TOKEN 필요
curl -s -H "Authorization: Bearer $RELAY_TOKEN" \
  https://<호스트>/api/v1/holdings

# 변경 API는 토스에 안 가고 즉시 거절되어야 함
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  -H "Authorization: Bearer $RELAY_TOKEN" \
  https://<호스트>/api/v1/orders
# → 405
```

로컬 테스트:

```bash
cd ~/toss-relay && source .venv/bin/activate
pytest -q
```

## 보안 메모

- 어시스턴트에는 `RELAY_TOKEN`만 저장. `TOSS_CLIENT_*` 는 VM `.env` 에만.
- `app.py` allowlist에 없는 경로·비-GET은 upstream 호출 없이 404/405.
- `.env` 권한 잠그기: `chmod 600 ~/toss-relay/.env`
- 토스 Open API 키는 **이 릴레이 전용으로 하나 새로 발급**하세요. 토스는 client 하나당 유효 토큰을 1개만 허용해서, 같은 키를 다른 곳에서 쓰면 서로의 토큰을 무효화합니다.
- `RELAY_TOKEN`이 유출됐다고 의심되면 새 값으로 바꾸고 `sudo systemctl restart toss-relay`.
- 유휴 회수: Always Free 인스턴스는 7일간 CPU·네트워크(A1은 메모리까지) 95분위가 20% 미만이면 중지될 수 있습니다. 조회용 릴레이는 거의 항상 이 조건에 걸리므로, 계정을 **PAYG(종량제)로 업그레이드**해 두는 것을 권장합니다. Always Free 한도 안에서만 쓰면 요금은 0원이고 회수 대상에서 빠집니다. (업그레이드 후 콘솔에서 예산 알림을 1달러로 걸어 두면 안심됩니다.)
