# 간편앨범 실습 가이드 (JWT + Presigned URL) — v1.1

> **개요 교육 자료:** `refdoc/JWT_Presigned_URL_개념설명.pptx`, `docs/jwt_presign_user_manual_v1.0.pdf`
> 이 문서는 **실제 손으로 따라 하는 실습 절차서**입니다. 개념은 위 개요 자료로 먼저 학습한 뒤 진행하세요.
> **대상:** 본인 AWS 계정 + 본인 EC2(Ubuntu 24.04, x86_64, t3.micro). 교육 7~10인.

---

> ### 📌 v1.0 → v1.1 변경 요약 (강사 검토 반영)
> 1. **관리자 자격증명: IAM User+액세스 키 → EC2 인스턴스 프로파일로 정정.**
>    역할명 **`myrole_ec2_admin_profile`** (AdministratorAccess, 교육 샌드박스 전용). 장기 키를 EC2에
>    두지 않아 키 유출·회수 부담이 없습니다(CLAUDE.md §2/§8 부합). → **§B, §H 변경.**
> 2. **포트 3000 확정** — 웹앱(auth-server)은 3000 포트. 보안그룹 22+3000. → §A.
> 3. **개인키 배치 단계(§D-2) 유지** — 키 없으면 auth-server 기동 실패.
> 4. **AUDIENCE 두 곳 동시 수정(§E) 유지** — `auth-server/src/jwt.js` + `config/env.sh`.
> 5. **(검토 반영)** `npm start` 포그라운드 점유 → **별도 터미널/백그라운드 실행** 안내 보강(§F),
>    §G-2 교차 테스트 **전제** 명시.

---

## 진행 순서 한눈에

| 단계 | 내용 | 핵심 산출물 |
|---|---|---|
| A | 실습용 EC2 생성 | SSH 가능한 Ubuntu 서버 |
| B | 관리자 권한(인스턴스 프로파일) + CLI 도구 | `aws sts get-caller-identity` 성공 |
| C | 소스 동기화(git) | 프로젝트 루트 |
| D | 구성(환경 + 개인키 배치) | `config/env.sh`, `auth-server/keys/jwt_private_key.pem` |
| E | 소스 커스터마이징(AUDIENCE) | 교육생별 고유 `aud` |
| F | 프로그램 구동(스크립트 00~06 + 서버) | 인프라 + 웹앱 |
| G | 구동 검증(화면/토큰/로그 + aud 격리 실증) | 업로드·썸네일·401 |
| H | 자원 삭제(보안/비용) | 정리 완료 |

> 모든 셸 명령은 EC2(Ubuntu, `bash`) 기준입니다. Windows에서 시도한다면 `scripts\*.ps1` 세트를 사용하세요.

---

## A. 실습용 EC2 생성

- **AMI:** Ubuntu Server 24.04 LTS, **아키텍처 x86_64** (Arm 아님)
- **타입:** t3.micro · **키페어:** 새로 생성(.pem 다운로드 보관)
- **네트워크:** 퍼블릭 IPv4 자동 할당 **활성화**
- **IAM 인스턴스 프로파일:** §B-1에서 만들 역할 `myrole_ec2_admin_profile`을 연결합니다.
  (역할을 먼저 만들었다면 시작 마법사의 *고급 세부 정보 → IAM 인스턴스 프로파일*에서 선택, 아니면 §B-2에서 사후 연결)
- **보안 그룹(인바운드):**
  | 포트 | 용도 | 소스 |
  |---|---|---|
  | 22 (SSH) | 접속 | **내 IP** 권장 |
  | 3000 (TCP) | 웹앱(auth-server) | 내 IP 또는 교육장 대역 |

> ⚠️ **포트 3000**: 웹앱은 `auth-server`가 3000 포트로 서빙합니다(80 아님). 80으로 열고 싶다면
> 구동 시 `PORT=80`이 필요하고 권한 처리(`sudo`/`setcap`)가 추가됩니다 — 교육에서는 **3000 권장**.

접속:
```bash
ssh -i <your-key>.pem ubuntu@<EC2-PUBLIC-IP>   # 기본 사용자: ubuntu
```

---

## B. 관리자 권한(인스턴스 프로파일) + CLI 도구

> **왜 인스턴스 프로파일인가:** EC2에 역할을 부여하면 CLI가 **임시 자격증명**을 메타데이터에서 자동
> 취득합니다. 디스크에 저장되는 장기 액세스 키가 없어 유출·회수 부담이 사라집니다(교육 샌드박스 전용 권한).

### B-1. (콘솔) 관리자 역할 생성
1. **IAM → 역할 → 역할 생성**
2. 신뢰할 수 있는 엔터티: **AWS 서비스 → EC2**
3. 권한 정책: **AdministratorAccess** 연결 *(교육 샌드박스 전용 — 운영 금지)*
4. 역할 이름: **`myrole_ec2_admin_profile`** → 생성
   - 콘솔이 동일 이름의 **인스턴스 프로파일**을 자동 생성합니다.

### B-2. (콘솔) EC2에 인스턴스 프로파일 연결
- **EC2 → 인스턴스 선택 → 작업 → 보안 → IAM 역할 수정** → `myrole_ec2_admin_profile` 선택 → 저장
  *(A 단계 시작 마법사에서 이미 연결했다면 생략)*

### B-3. (EC2) 도구 설치
```bash
# 기본 도구
sudo apt-get update && sudo apt-get install -y jq zip git unzip curl

# Node.js 24.x (NodeSource — 우분투 기본 저장소 버전에 의존하지 말 것)
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs

# AWS CLI v2 (공식 설치본 — apt 패키지는 구버전일 수 있음)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && sudo ./aws/install
node --version && aws --version && jq --version
```

### B-4. (EC2) 자격증명 확인 — `aws configure` 불필요
인스턴스 프로파일이 연결되어 있으면 키 설정 없이 바로 동작합니다.
```bash
aws sts get-caller-identity
#  → Arn 이 .../assumed-role/myrole_ec2_admin_profile/... 형태면 정상
#  (계정ID가 보이면 성공 — 이후 ACCOUNT_ID 는 스크립트가 자동 취득)
```
> 만약 `Unable to locate credentials` 가 나오면 §B-2의 역할 연결이 누락된 것입니다(연결 후 1~2분 대기).

---

## C. 소스 동기화

```bash
git clone <REPOSITORY_URL> simple-album && cd simple-album   # 최초 1회
# 이후 업데이트는: git pull
```
이후 모든 명령은 **프로젝트 루트**(`simple-album/`)에서 실행합니다.

> --- 여기서부터 프로젝트 파일 사용 ---

---

## D. 구성

### D-1. 환경값 확인 (`config/env.sh`)
환경값의 **단일 출처**입니다. 직접 채울 시크릿은 없습니다.
- `REGION=ap-northeast-2`, `ISSUER`, `AUDIENCE`, `JWT_KID` — 합의값(이미 설정됨).
- `ACCOUNT_ID` — `aws sts get-caller-identity`로 **자동 취득**(하드코딩 금지).
- `BUCKET=myalbum-${ACCOUNT_ID}` — 계정별 자동 결정.
```bash
source ./config/env.sh    # 맨 윗줄에 REGION/ACCOUNT_ID/BUCKET 가 출력되면 정상
```

### D-2. 개인키 배치 (⚠️ 필수 — 빠뜨리면 서버 기동 실패)
폐쇄 커뮤니티로 받은 **교육 전용 개인키**를 배치합니다. (리포에는 없음 / `*.pem`은 `.gitignore`)
```bash
cp <받은경로>/jwt_private_key.pem auth-server/keys/jwt_private_key.pem
ls -l auth-server/keys/jwt_private_key.pem    # 존재 확인
```
> 이 키로 `/login`이 RS256 토큰을 서명합니다. 검증용 공개키(JWKS)는 중앙 issuer가 호스팅하므로
> EC2에는 공개키를 두지 않습니다.

---

## E. 소스 커스터마이징 — 교육생별 `AUDIENCE`

**목표:** 교육생마다 `aud`를 다르게 설정 → *교육생 A의 토큰으로 교육생 B의 API에 접근 시 401*을 실증.

`AUDIENCE`는 **두 파일이 일치**해야 본인 스택이 동작합니다(발행 측 + 검증 측):

| 파일 | 줄 | 역할 |
|---|---|---|
| `auth-server/src/jwt.js` | `const AUDIENCE = "myalbum1";` | 토큰 **발행** 시 `aud` |
| `config/env.sh` | `export AUDIENCE="myalbum1"` | 05 스크립트가 API GW **Authorizer 검증값**으로 사용 |

본인 고유값으로 **두 곳 모두** 변경(예: 이니셜/직번 사용):
```bash
#  myalbum1  →  myalbum-<본인식별자>   (예: myalbum-kim)
sed -i 's/myalbum1/myalbum-kim/' auth-server/src/jwt.js config/env.sh
grep -rn "myalbum-kim" auth-server/src/jwt.js config/env.sh   # 두 곳 모두 바뀌었는지 확인
```
> ⚠️ 이 변경은 **04·05 실행 전, 그리고 auth-server 기동 전**에 끝내야 합니다(검증값이 토큰 발행 시점에
> 고정되므로). 이미 05를 돌렸다면 값 변경 후 05를 다시 실행하세요(멱등 — 기존 API 재사용).

**격리 실증(2인 1조):** A는 `myalbum-A`, B는 `myalbum-B`로 설정.
서명키·issuer·kid는 전원 공통이고 **aud만 다릅니다.** → §G에서 교차 호출 테스트.

---

## F. 프로그램 구동 (스크립트 + 서버)

스크립트는 **순서대로**, 각자 **재실행 안전(idempotent)**. 각 단계 후 해당 파일 주석("왜")을 읽으세요.
```bash
bash scripts/00_prereqs.sh        # 도구/자격증명/리전/ACCOUNT_ID 점검
bash scripts/01_create_bucket.sh  # S3 버킷 + 퍼블릭 차단 + CORS
bash scripts/02_create_iam_roles.sh   # Lambda 실행 역할 + 최소권한
bash scripts/03_publish_layer.sh  # sharp 레이어 빌드(EC2=linux-x64) → 게시
bash scripts/04_deploy_lambdas.sh # presign / thumbnailer / album-list 배포
bash scripts/05_create_http_api.sh    # HTTP API + 네이티브 JWT Authorizer + 라우트 + CORS
bash scripts/06_wire_s3_event.sh  # S3 이벤트(gallery/original/) → thumbnailer
```

웹/인증 서버 구동(05가 출력한 API 주소를 주입):
```bash
source .state/resources.env                    # API_ENDPOINT 로드(스크립트가 기록해 둠)
cd auth-server && npm install                  # 최초 1회 의존성 설치
API_ENDPOINT="$API_ENDPOINT" npm start         # 포그라운드로 http://localhost:3000 리슨(터미널 점유)
```
> ⚠️ `npm start`는 **`auth-server/` 디렉토리 안에서** 실행해야 합니다(`package.json` 위치).
> 프로젝트 루트(`simple-album/`)에서 실행하면 `ENOENT: package.json not found` 오류가 납니다.
>
> ℹ️ 같은 EC2에서 §G의 `curl`/스모크 테스트를 이어서 하려면
> **SSH 창을 하나 더 열거나**, 아래처럼 **백그라운드로 실행**하세요(`auth-server/` 안에서):
> ```bash
> nohup env API_ENDPOINT="$API_ENDPOINT" npm start > /tmp/auth-server.log 2>&1 &
> tail -f /tmp/auth-server.log     # 기동 로그 확인(Ctrl+C 로 빠져나와도 서버는 계속 실행)
> ```

브라우저에서 **`http://<EC2-PUBLIC-IP>:3000`** 접속.

---

## G. 구동 검증

### G-1. 화면·토큰·로그
1. `http://<EC2-PUBLIC-IP>:3000` 접속 → 상단에 단계 1/2/3 카드.
2. **로그인**(기본값 `james` / `demo`) → 하단 **로그 패널**에 토큰 발행 확인:
   `[login] OK · sub=james · token=eyJhbGciOi...`  ← **토큰발행 = 로그보기**
3. **사진 업로드**(jpg/png/webp) → 로그에 `[presign] OK` → `[upload] 완료` → 잠시 후
   `[albums] N개 항목`, **내 앨범**에 썸네일 표시(= 썸네일 람다 자동 생성 성공).

### G-1-1. Presigned URL 원리 확인

앨범에서 썸네일을 클릭하면 브라우저 주소창(또는 네트워크 탭)에서 아래와 같은 URL을 볼 수 있습니다.

```
https://myalbum-<ACCOUNT_ID>.s3.ap-northeast-2.amazonaws.com/gallery/thumb/james/20260618_....jpg
  ?X-Amz-Algorithm=AWS4-HMAC-SHA256
  &X-Amz-Credential=ASIA...%2Fap-northeast-2%2Fs3%2Faws4_request
  &X-Amz-Date=20260618T132343Z
  &X-Amz-Expires=300
  &X-Amz-Signature=55d066...
```

**파일명 뒤의 쿼리스트링이 임시 접근권한 그 자체**입니다. S3 버킷은 퍼블릭 비공개이므로, URL만으로는 접근이 안 됩니다. Lambda가 본인 자격증명으로 "이 조건에서만 허용"이라는 서명을 URL에 포함시켜, 브라우저가 Lambda 없이 S3와 직접 통신할 수 있게 합니다.

| 파라미터 | 의미 |
|---|---|
| `X-Amz-Credential` | 어떤 자격증명(Lambda 역할)으로 서명했는지 |
| `X-Amz-Date` | 서명 생성 시각 |
| `X-Amz-Expires` | 유효시간(초) — `300` = 5분 후 자동 만료 |
| `X-Amz-Security-Token` | EC2/Lambda가 STS에서 발급받은 **임시 자격증명 토큰** |
| `X-Amz-Signature` | 위 조건을 HMAC-SHA256으로 서명한 값 — 위변조 방지 |

> **PUT vs GET presigned URL**
> - **업로드(PUT)**: `presign-creator` Lambda가 생성 → 브라우저가 S3에 직접 PUT
> - **조회(GET)**: `album-list` Lambda가 생성 → 브라우저가 S3에 직접 GET
>
> 두 경우 모두 이진 데이터(이미지)가 Lambda/API Gateway를 거치지 않습니다.
> Lambda는 **"서명된 URL"만 발급**하고, 실제 전송은 브라우저↔S3 간 직접 이루어집니다.

#### 실전 권장안 — GET은 CloudFront로 대체

실습에서는 조회도 Presigned GET으로 구현했지만, **실전 서비스에서는 조회 경로만 CloudFront로 교체**하는 것이 일반적입니다.

```
[업로드]  브라우저 → Presigned PUT → S3 직접 저장       ← 변경 없음
[조회]    브라우저 → CloudFront → S3 (OAC로 비공개)     ← Presigned GET 대체
```

| 항목 | Presigned GET (실습) | CloudFront (실전 권장) |
|---|---|---|
| URL 만료 | 있음 (300초 등) | 없음 — 항상 유효한 짧은 URL |
| URL 형태 | 긴 쿼리스트링(`?X-Amz-...`) | 깔끔한 URL (`/gallery/thumb/...`) |
| 캐싱 | 없음 — 매번 S3 직접 접근 | 엣지 캐시 — 첫 요청 후 글로벌 캐시 |
| 비용 | S3 GET 요청마다 과금 | S3 요청 감소 + CloudFront 전송 과금 |
| 버킷 공개 여부 | 비공개 유지 가능 | **비공개 유지 가능 (OAC)** |
| 구현 복잡도 | Lambda `getSignedUrl` | CloudFront 배포 + OAC 설정 |

> **OAC(Origin Access Control)**: S3 버킷을 CloudFront에서 오는 요청만 허용하도록 설정하는 방식.
> 버킷을 공개하지 않고도 CloudFront를 통해 안전하게 이미지를 제공할 수 있습니다.

썸네일 **반복 조회**가 많은 앨범 서비스에서 CloudFront가 특히 유리합니다. Presigned GET은 매번 S3를 거치지만, CloudFront는 첫 요청 이후 엣지에서 캐시로 응답해 S3 비용과 지연을 동시에 줄입니다.

### G-2. `aud` 격리 실증 (E의 목표)
2인 1조로 **상대의 API**에 내 토큰을 던져 401을 확인합니다.
> 전제: ① 내 auth-server가 떠 있을 것(§F), ② 상대의 **API-ID**(상대가 05 실행 후 공유)를 알 것.
```bash
# (A에서) 내 토큰 발급
TOKEN=$(curl -s -X POST http://localhost:3000/login \
  -H 'content-type: application/json' -d '{"username":"james","password":"demo"}' | jq -r .token)

# A의 토큰(aud=myalbum-A)으로 B의 API 호출 → 401 (aud 불일치, Authorizer 거부)
curl -i -X POST https://<B의-API-ID>.execute-api.ap-northeast-2.amazonaws.com/presign \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"contentType":"image/png"}'
#   → HTTP/1.1 401 Unauthorized  (서명·iss는 통과하지만 aud가 달라 거부)
```
> 같은 토큰을 **본인 API**로 호출하면 200 + presigned URL. 이 대비로 Authorizer의 `aud` 검증을 체감합니다.

### G-3. (선택) 자동 스모크 테스트
```bash
bash scripts/90_smoke_test.sh   # 로그인→presign→PUT(640×480 PNG)→썸네일→목록 end-to-end
```

### 자주 막히는 곳
- **403 SignatureDoesNotMatch**: presign의 contentType ≠ PUT의 Content-Type.
- **401**: 토큰 `iss/aud/kid`가 합의값과 일치하는지(특히 §E의 AUDIENCE 두 곳 일치).
- **썸네일 안 생김**: 06 트리거 prefix(`gallery/original/`), thumbnailer CloudWatch 로그 확인.
- **화면 안 열림**: 보안그룹 3000 오픈 / `npm start` 실행 / `API_ENDPOINT` 주입 여부.
- **`Unable to locate credentials`**: 인스턴스 프로파일(§B-2) 연결 누락.

---

## H. 자원 삭제 (보안 위협 · 비용 소요)

> ⚠️ **순서 중요**: 관리자 권한(인스턴스 프로파일)은 리소스 삭제에 필요합니다.
> **teardown(앱 리소스) → EC2 정리 → (선택) 역할 정리** 순서로 진행하세요.

### H-1. AWS 리소스 삭제(파괴적)
```bash
bash scripts/99_teardown.sh     # 확인 프롬프트에 DELETE 입력
#   삭제: S3 버킷(객체 포함) · Lambda 3종 · HTTP API · Lambda 실행 역할/정책
```
> 레이어 버전은 teardown 대상이 아닙니다(콘솔에서 확인 후 수동 삭제 권장).

### H-2. EC2 정리
- **중지(stop)**: 컴퓨팅 과금 중단(단, EBS 볼륨 비용은 잔존).
- **완전 비용 차단**은 **종료(terminate)** 권장(교육 종료 시). 종료하면 인스턴스 프로파일 연결도 함께 해제됩니다.
- 보안그룹 22/3000은 종료 후 닫힘.

### H-3. (선택) 관리자 역할 정리
> ✅ **장기 액세스 키가 없으므로 키 비활성화/삭제 단계가 불필요합니다**(인스턴스 프로파일 방식의 이점).
> 계정을 재사용하지 않거나 관리자 역할을 남기고 싶지 않다면 아래로 정리합니다.
- **콘솔:** EC2에서 역할 분리(작업 → 보안 → IAM 역할 수정 → 없음) 후,
  IAM → 역할 → `myrole_ec2_admin_profile` 삭제.
> ⚠️ 역할을 EC2에서 떼면 그 인스턴스의 CLI 관리자 권한이 사라집니다. **반드시 §H-1 teardown 완료 후** 진행하세요.

### H-4. 개인키 폐기
- `auth-server/keys/jwt_private_key.pem`은 **교육 전용 일회용 키** → 수업 후 로컬에서도 삭제.

---

## 부록: 아키텍처 1줄 요약
로그인(EC2, 개인키 RS256 서명) → JWT → API GW 네이티브 Authorizer(중앙 JWKS로 iss/aud/exp/서명 검증)
→ presigned PUT URL → 브라우저가 S3에 직접 업로드 → S3 이벤트 → thumbnailer(sharp) 썸네일 →
album-list(presigned GET)로 본인 사진만 조회.

*— 문서 버전 v1.1 · v1.0 대비 변경: 관리자 자격증명을 EC2 인스턴스 프로파일(`myrole_ec2_admin_profile`)로 정정*
