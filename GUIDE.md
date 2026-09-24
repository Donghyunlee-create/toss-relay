# 토스증권 읽기전용 연결 — 따라하기 안내서

코딩을 몰라도 됩니다. **웹 브라우저만** 쓰면 됩니다.  
예상 시간: 약 40분. 막히면 맨 아래 **문제 해결**을 보세요.

이 안내서는 Oracle 공식 문서의 화면 경로를 기준으로 썼습니다.  
버튼 이름이 조금 다를 수 있으니, **비슷한 단어**를 찾으면 됩니다.

---

## 0) 준비물

- 신용카드 (본인 확인용. Always Free만 쓰면 요금 0원)
- 휴대폰 번호 (인증 SMS)
- 토스증권 계좌 (없으면 토스 앱에서 먼저 개설)
- 여유 시간 약 40분
- PC 또는 노트북 브라우저 (Chrome / Edge 권장)

---

## 1) Oracle Cloud 가입 (홈 리전 = 서울)

1. 브라우저에서 가입 페이지를 엽니다.  
   https://signup.oraclecloud.com  
2. 이름·이메일·비밀번호·국가를 입력합니다.
3. **Home Region(홈 리전)** 을 고를 때 **반드시**  
   `South Korea Central (Seoul)` / `ap-seoul-1` 을 고르세요.  
   **한 번 정하면 바꿀 수 없습니다.** Always Free 서버는 홈 리전에만 만들 수 있습니다.
4. 휴대폰 인증 → 신용카드 등록.  
   카드에 소액(확인용)이 잠시 잡힐 수 있지만, **업그레이드하지 않으면 청구되지 않습니다.**
5. 약관에 동의하고 가입을 마칩니다. 콘솔(관리 화면)로 들어갑니다.

참고: https://docs.oracle.com/en-us/iaas/Content/GSG/Tasks/signingup_topic-Sign_Up_for_Free_Oracle_Cloud_Promotion.htm

---

## 2) PAYG 업그레이드 + 예산 알림 (요금 0원 유지, 유휴 회수 방지)

**왜 하나요?**  
무료(Always Free)만 쓰면 서버가 일주일 이상 “거의 쉬는 상태”면 Oracle이 서버를 끌 수 있습니다.  
조회용 서버는 거의 항상 이 조건에 걸립니다.  
**Pay As You Go(종량제)로 바꿔도 Always Free 한도 안이면 요금은 0원**이고, 유휴 회수 대상에서 빠집니다.

### 2-1. PAYG로 업그레이드

1. 콘솔 왼쪽 위 **☰ 메뉴(네비게이션)** 를 엽니다.
2. **Billing & Cost Management** → **Upgrade and Manage Payment** 를 누릅니다.  
   (또는 화면 위/옆의 **Upgrade** 링크)
3. Pay As You Go 설명을 읽고 약관에 체크한 뒤 **Upgrade your account** / **Upgrade account** 를 누릅니다.
4. 카드에 확인용 승인(문서상 약 $100 상당)이 잠시 잡힐 수 있고, 곧 해제됩니다.  
   업그레이드 완료 메일이 올 때까지 반나절~하루 걸릴 수 있습니다.

참고: https://docs.oracle.com/en-us/iaas/Content/Billing/Tasks/changingpaymentmethod.htm

### 2-2. 예산 알림 $1

실수로 유료 자원을 만들면 메일로 알려 줍니다. (예산은 “경고”이지 자동 차단은 아닙니다.)

1. **☰** → **Billing & Cost Management** → **Cost Management** → **Budgets**
2. **Create Budget** 클릭
3. 대상(Compartment)은 보통 **root**(맨 위 테넌시) 선택
4. 월 한도를 **1** (USD) 정도로 입력
5. Alert 에서 **실제 사용액이 한도의 100%** 같은 조건 + 본인 이메일 입력
6. **Create**

참고: https://docs.oracle.com/en-us/iaas/Content/Billing/Tasks/create-budget.htm

---

## 3) Cloud Shell 열기 + SSH 키 만들기

로컬 PC에 SSH 프로그램을 설치할 필요 없습니다. **브라우저 안 터미널**을 씁니다.

1. 콘솔 오른쪽 위 근처 **Cloud Shell** 아이콘(`>_`)을 누른 뒤 **Cloud Shell** 을 고릅니다.  
   화면 아래에 검은 터미널이 열립니다.
2. 인터넷이 안 되면 Cloud Shell 창 **왼쪽 위 메뉴(☰ 또는 ⋮)** → **Network** → **Public Network** 를 고르세요.  
   (개인 계정에서는 보통 바로 됩니다. 안 되면 테넌시 정책이 필요할 수 있습니다.)
3. 아래를 **한 줄씩** 붙여넣고 Enter 합니다.  
   (SSH 비밀키를 만듭니다. 비밀번호는 비워 둡니다.)

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
```

이 명령은: 서버 로그인용 열쇠 한 쌍을 Cloud Shell 홈에 만듭니다.

4. 공개키를 화면에 출력합니다.

```bash
cat ~/.ssh/id_ed25519.pub
```

이 명령은: `ssh-ed25519` 로 시작하는 한 줄을 보여 줍니다.  
**그 줄 전체를 드래그해서 복사**해 두세요. (다음 단계에서 붙여넣습니다.)

참고: https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cloudshellintro.htm  
업로드 메뉴: https://docs.oracle.com/en-us/iaas/Content/API/Concepts/devcloudshellgettingstarted.htm

---

## 4) 서버(인스턴스) 만들기

1. 콘솔 위쪽 **리전**이 **Seoul / ap-seoul-1** 인지 확인합니다.
2. **☰** → **Compute** → **Instances** → **Create instance**
3. **Name**: 아무 이름 (예: `toss-relay`)
4. **Placement**: Always Free Eligible 이 보이면 그대로 둡니다.
5. **Image**: **Canonical Ubuntu** (22.04 또는 24.04, Always Free Eligible 표시가 있는 것)
6. **Shape**:  
   - 우선 **VM.Standard.E2.1.Micro** (AMD, Always Free)  
   - 용량이 없으면 **Change shape** 에서 Ampere **A1.Flex** (예: OCPU 1, 메모리 6GB) 시도  
   - `Out of host capacity` 가 나오면 → 문제 해결 참고
7. **Networking**:  
   - Create new VCN / 또는 기본 VCN의 **Public Subnet**  
   - **Assign a public IPv4 address: Yes** (반드시 켜기)
8. **Add SSH keys**: **Paste public keys** 선택 → 3단계에서 복사한 `ssh-ed25519 ...` 한 줄을 붙여넣기
9. **Create** 클릭 → 상태가 **RUNNING** 될 때까지 기다립니다.
10. 인스턴스 상세 화면에서 **Public IP address** 숫자를 메모합니다. (예: `130.162.1.2`)

참고: https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/launchinginstance.htm  
튜토리얼: https://docs.oracle.com/en-us/iaas/Content/Compute/tutorials/first-linux-instance/overview.htm

---

## 5) 고정 IP(Reserved Public IP)로 바꾸기

토스 “허용 IP”에 넣을 주소가 바뀌지 않게 고정합니다. (요금 없음)

1. **Instances** → 방금 만든 인스턴스 이름 클릭
2. 아래쪽 **Networking** / **Attached VNICs** → **Primary VNIC** 이름 클릭  
   (화면 구성이 조금 다르면 “VNIC”, “Attached VNICs” 를 찾으세요)
3. **IPv4 Addresses** (또는 **IP administration**) 탭
4. Private IP 줄의 **⋮ (Actions)** → **Edit**
5. **Public IP type** → **Reserved public IP**
6. **Create new Reserved IP Address** (이름만 적고) → **Update**
7. 화면에 나온 **Reserved** 공인 IP를 다시 메모합니다. (이전과 같거나 새로 할당될 수 있음)

참고: https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/reserved-public-ip-assign.htm

---

## 6) 보안 목록에서 80·443 열기

1. **☰** → **Networking** → **Virtual Cloud Networks** → 본인 VCN 클릭
2. **Security Lists** → **Default Security List** (또는 서브넷에 연결된 목록) 클릭
3. **Add Ingress Rules** (수신 규칙 추가) 를 **두 번** 합니다.

| 항목 | 값 |
|------|-----|
| Source Type | CIDR |
| Source CIDR | `0.0.0.0/0` |
| IP Protocol | TCP |
| Destination Port Range | `80` (한 번), 다음은 `443` |
| Description | `http` / `https` (선택) |

SSH(22) 규칙은 기본으로 있는 경우가 많습니다. 없으면 22도 같은 방식으로 추가하세요.

참고: https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/securitylists.htm

---

## 7) 토스 WTS에서 Open API 키 + 허용 IP

1. 브라우저에서 https://www.tossinvest.com 로그인
2. **설정** → **Open API**
3. **이 릴레이 전용으로 새 키**를 발급합니다. (`client_id`, `client_secret`)  
   - secret 은 **지금만** 보이니 메모장에 잠시 적어 두세요.  
   - 같은 키를 다른 프로그램과 같이 쓰면 서로 토큰이 끊깁니다.
4. 같은 화면 **허용 IP 관리**에 **5단계에서 메모한 서버 공인 IP** 를 등록합니다.

(공개 가이드에서도 경로를 “WTS → 설정 → Open API → 허용 IP 관리”로 안내합니다.)

---

## 8) Cloud Shell에서 서버 접속 + 한 줄로 설치

아래 명령에서 `<IP>` 는 **5단계에서 메모한 고정 IP 숫자**로 바꿔서 입력하세요. (예: `ubuntu@130.162.1.2`)  
처음 접속할 때 `Are you sure you want to continue connecting` 이 나오면 **yes** 를 입력하고 Enter.

1. Cloud Shell에서 서버로 들어갑니다. 접속되면 줄 맨 앞이 `ubuntu@...` 로 바뀝니다.

```bash
ssh ubuntu@<IP>
```

2. 서버에 들어온 뒤, 아래 **한 줄 전체**를 복사해서 붙여넣고 Enter 합니다.  
   (처음이면 내려받고, 이미 있으면 최신으로 받은 뒤, 설치 화면이 이어집니다.)

```bash
sudo apt-get install -y git >/dev/null 2>&1; git clone https://github.com/Donghyunlee-create/toss-relay.git ~/toss-relay 2>/dev/null || git -C ~/toss-relay pull; cd ~/toss-relay && bash setup.sh
```

이 한 줄은: GitHub에서 프로그램을 받아 `setup.sh` 를 실행합니다.  
필요한 프로그램을 설치하고, 토스 키를 물어보고, HTTPS 주소까지 자동으로 만듭니다.

- `client_id` 물으면 → 7단계에서 받은 값 붙여넣기  
- `client_secret` 물으면 → 붙여넣기 (화면에 안 보임, 정상)  
- **403** 이 나오면 → 허용 IP에 서버 IP를 등록했는지 확인하고, 등록 후 **같은 한 줄**을 다시 실행 (기존 설정 유지 → Y)

성공하면 초록색 상자에서 **서버 주소**(`https://숫자-숫자-숫자-숫자.sslip.io`)와 **RELAY_TOKEN** 이 나옵니다.

폴더가 잘 받았는지 궁금하면:

```bash
ls ~/toss-relay
```

이 명령은: `app.py` 와 `setup.sh` 가 보여야 합니다.

---

### GitHub 방법이 안 될 때 (zip으로 올리기)

1. 어시스턴트가 준 `toss-relay.zip` 을 PC에 저장합니다.
2. **Cloud Shell** 창 **왼쪽 위 메뉴** → **Upload** → PC의 zip 선택 → Upload  
   (또는 zip 파일을 Cloud Shell 창으로 드래그 앤 드롭)
3. Cloud Shell에서 (아직 서버 들어가기 **전**):

```bash
scp ~/toss-relay.zip ubuntu@<IP>:~/
```

이 명령은: zip을 서버 홈으로 보냅니다. (`<IP>` 를 바꾸세요.)

4. 서버로 들어간 뒤:

```bash
ssh ubuntu@<IP>
sudo apt-get update -qq && sudo apt-get install -y -qq unzip
unzip -o ~/toss-relay.zip -d ~
cd ~/toss-relay && bash setup.sh
```

참고(업로드): https://docs.oracle.com/en-us/iaas/Content/API/Concepts/devcloudshellgettingstarted.htm

---

## 9) 결과 확인 + 어시스턴트에게 넘기기

1. **채팅에는 서버 주소만** 보내세요.  
   예: `https://130-162-1-2.sslip.io`
2. **RELAY_TOKEN** 은 채팅에 넣지 마세요.  
   어시스턴트가 보내는 **보안 입력란(secure input)** 에만 붙여넣으세요.
3. (선택) 서버에서 이미 `setup.sh` 가 POST 주문 → 405 를 검사했습니다.  
   브라우저에서 `https://...sslip.io/healthz` 가 `{"ok":true}` 이면 정상입니다.

---

## 문제 해결

### Out of host capacity
Always Free 자리가 잠깐 없는 상태입니다.  
다른 **Availability domain** 으로 다시 Create, 또는 몇 시간 뒤 / 이른 아침에 재시도.  
A1 대신 **E2.1.Micro** 를 쓰거나 그 반대도 시도.

### 403 / 허용되지 않은 IP
토스 WTS → 설정 → Open API → 허용 IP 관리에 **Reserved Public IP** 가 들어가 있는지 확인.  
등록 후:

```bash
cd ~/toss-relay && bash setup.sh
```

기존 설정 유지 Y.

### Permission denied (publickey)
- 인스턴스 만들 때 붙여넣은 공개키가 Cloud Shell의 `~/.ssh/id_ed25519.pub` 와 같은지 확인
- 사용자 이름은 반드시 `ubuntu` (Ubuntu 이미지)

```bash
cat ~/.ssh/id_ed25519.pub
```

### 사이트(HTTPS)가 안 열림
1. Security List에 **80, 443** 이 있는지 (6단계)  
2. 서버에서 다시:

```bash
cd ~/toss-relay && bash setup.sh
```

(`setup.sh` 가 iptables도 열어 줍니다.)

3. 주소가 **5단계 IP** 기준 `숫자-숫자-숫자-숫자.sslip.io` 인지 확인  
   IP를 바꿨으면 setup.sh 를 다시 돌려 Caddy 주소를 갱신하세요.

### Cloud Shell에서 ssh/scp 가 안 됨
Cloud Shell **Public Network** 로 전환했는지 확인 (3단계).

### 다시 설치하고 싶을 때
서버에서:

```bash
cd ~/toss-relay && bash setup.sh
```

멱등이므로 여러 번 실행해도 됩니다.

---

## 참고 문서 (공식)

- 가입 / 홈 리전: https://docs.oracle.com/en-us/iaas/Content/GSG/Tasks/signingup_topic-Sign_Up_for_Free_Oracle_Cloud_Promotion.htm  
- Free Tier / Always Free: https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier.htm  
- Always Free·유휴 회수: https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm  
- PAYG 업그레이드: https://docs.oracle.com/en-us/iaas/Content/Billing/Tasks/changingpaymentmethod.htm  
- 예산 만들기: https://docs.oracle.com/en-us/iaas/Content/Billing/Tasks/create-budget.htm  
- Cloud Shell: https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cloudshellintro.htm  
- Cloud Shell 사용·업로드: https://docs.oracle.com/en-us/iaas/Content/API/Concepts/devcloudshellgettingstarted.htm  
- 인스턴스 생성: https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/launchinginstance.htm  
- Reserved Public IP 할당: https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/reserved-public-ip-assign.htm  
- Security Lists: https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/securitylists.htm  
