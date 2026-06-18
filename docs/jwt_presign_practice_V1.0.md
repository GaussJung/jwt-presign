# 간편앨범 실습 가이드 (JWT + Presigned URL) — v1.0

> **개요 교육 자료:** `refdoc/JWT_Presigned_URL_개념설명.pptx`, `docs/jwt_presign_user_manual_v1.0.pdf`
> 이 문서는 **실제 손으로 따라 하는 실습 절차서**입니다. 개념은 위 개요 자료로 먼저 학습한 뒤 진행하세요.
> **대상:** 본인 AWS 계정 + 본인 EC2(Ubuntu 24.04, x86_64, t3.micro). 교육 7~10인.

---

> ### 🛠 강사 검토 메모 (v1.0 — 검토 후 v1.1 반영 예정)
> 이번 초안에서 제안 순서(A~H) 대비 **보완·결정 필요** 항목:
> 1. **관리자 자격증명 방식** — 본 v1.0은 제안대로 *IAM User + 액세스 키* 흐름(B)으로 작성.
>    단, 프로젝트 아키텍처(CLAUDE.md §2/§8)는 *EC2 인스턴스 프로파일*을 권장(장기 키 미사용 → 키 유출
>    위험 제거). → **§B 말미의 〔대안〕 박스 참고 후 택1 결정.**
> 2. **포트** — 웹앱(auth-server)은 **3000** 포트로 동작. 제안의 80 대신 **3000 오픈**으로 작성(또는
>    `PORT=80`로 구동 시 권한 필요). → §A.
> 3. **개인키 배치 단계 추가** — 제안 A~H에 누락. 키 없으면 auth-server가 기동 실패 → **§D-2 신설.**
> 4. **AUDIENCE는 두 곳** — `auth-server/src/jwt.js` *그리고* `config/env.sh` 둘 다 수정해야 본인 스택이
>    정상 동작. → §E에서 명시.

---

## 진행 순서 한눈에

| 단계 | 내용 | 핵심 산출물 |
|---|---|---|
| A | 실습용 EC2 생성 | SSH 가능한 Ubuntu 서버 |
| B | 관리자 CLI 준비(IAM/자격증명) | `aws sts get-caller-identity` 성공 |
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

## B. 관리자 CLI 준비 (콘솔 + EC2)

### B-1. (콘솔) IAM 그룹/사용자/키
1. **IAM → 사용자 그룹 → 생성**: 이름 `adminGroup`, 정책 **AdministratorAccess** 연결.
2. **IAM → 사용자 → 생성**: 이름 `adminUser`, 그룹 `adminGroup`에 추가.
3. `adminUser` → **보안 자격 증명 → 액세스 키 생성**(CLI 용도) → **.csv 다운로드**(Access Key ID / Secret).

### B-2. (EC2) 도구 설치
```bash
# 기본 도구
sudo apt-get update && sudo apt-get install -y jq zip git unzip curl

# Node.js 20.x (NodeSource — 우분투 기본 저장소 버전에 의존하지 말 것)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# AWS CLI v2 (공식 설치본 — apt 패키지는 구버전일 수 있음)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && sudo ./aws/install
node --version && aws --version && jq --version
```

### B-3. (EC2) 자격증명 설정
```bash
aws configure
#   AWS Access Key ID     : <.csv의 Access Key ID>
#   AWS Secret Access Key : <.csv의 Secret>
#   Default region name   : ap-northeast-2
#   Default output format : json
aws sts get-caller-identity     # 계정ID가 보이면 성공
```

> 〔대안 — 권장: 인스턴스 프로파일〕 장기 액세스 키를 EC2에 두지 않는 방식입니다.
> 콘솔에서 **IAM 역할(AdministratorAccess)**을 만들어 EC2에 **인스턴스 프로파일로 연결**하면
> `aws configure` 없이 CLI가 동작하고, 키 유출/회수 부담이 사라집니다(CLAUDE.md §2/§8).
> IAM 학습 목적이면 B-1의 그룹/사용자 생성은 그대로 두되 **EC2에는 키 대신 역할을 부여**하는
> 절충도 가능합니다. → **강사 검토 결정 항목.**

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
API_ENDPOINT="$API_ENDPOINT" npm start         # http://localhost:3000 리슨
```
브라우저에서 **`http://<EC2-PUBLIC-IP>:3000`** 접속.

---

## G. 구동 검증

### G-1. 화면·토큰·로그
1. `http://<EC2-PUBLIC-IP>:3000` 접속 → 상단에 단계 1/2/3 카드.
2. **로그인**(기본값 `james` / `demo`) → 하단 **로그 패널**에 토큰 발행 확인:
   `[login] OK · sub=james · token=eyJhbGciOi...`  ← **토큰발행 = 로그보기**
3. **사진 업로드**(jpg/png/webp) → 로그에 `[presign] OK` → `[upload] 완료` → 잠시 후
   `[albums] N개 항목`, **내 앨범**에 썸네일 표시(= 썸네일 람다 자동 생성 성공).

### G-2. `aud` 격리 실증 (E의 목표)
2인 1조로 **상대의 API**에 내 토큰을 던져 401을 확인:
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
bash scripts/90_smoke_test.sh   # 로그인→presign→PUT(1x1 PNG)→썸네일→목록 end-to-end
```

### 자주 막히는 곳
- **403 SignatureDoesNotMatch**: presign의 contentType ≠ PUT의 Content-Type.
- **401**: 토큰 `iss/aud/kid`가 합의값과 일치하는지(특히 §E의 AUDIENCE 두 곳 일치).
- **썸네일 안 생김**: 06 트리거 prefix(`gallery/original/`), thumbnailer CloudWatch 로그 확인.
- **화면 안 열림**: 보안그룹 3000 오픈 / `npm start` 실행 / `API_ENDPOINT` 주입 여부.

---

## H. 자원 삭제 (보안 위협 · 비용 소요)

> ⚠️ **순서 중요**: 키를 먼저 지우면 CLI가 막혀 teardown이 안 됩니다. **teardown → 키 삭제 → EC2** 순서.

### H-1. AWS 리소스 삭제(파괴적)
```bash
bash scripts/99_teardown.sh     # 확인 프롬프트에 DELETE 입력
#   삭제: S3 버킷(객체 포함) · Lambda 3종 · HTTP API · Lambda 실행 역할/정책
```
> 레이어 버전과, **콘솔에서 만든 IAM `adminUser`/`adminGroup`은 teardown 대상이 아닙니다**(아래 수동 정리).

### H-2. CLI 액세스 키 비활성화 후 삭제 (보안)
```bash
KEY_ID=<.csv의 Access Key ID>
aws iam update-access-key --user-name adminUser --access-key-id "$KEY_ID" --status Inactive
aws iam delete-access-key --user-name adminUser --access-key-id "$KEY_ID"
```
> 〔인스턴스 프로파일을 택했다면〕 키가 없으므로 이 단계는 생략, 대신 역할/인스턴스 프로파일을 분리·삭제.
> 필요 시 `adminUser`/`adminGroup`도 콘솔에서 삭제.

### H-3. EC2 정리
- **중지(stop)**: 컴퓨팅 과금 중단(단, EBS 볼륨 비용은 잔존).
- **완전 비용 차단**은 **종료(terminate)** 권장(교육 종료 시).
- 보안그룹 22/3000은 종료 후 닫힘. 재사용 안 하면 인스턴스째 종료.

### H-4. 개인키 폐기
- `auth-server/keys/jwt_private_key.pem`은 **교육 전용 일회용 키** → 수업 후 로컬에서도 삭제.

---

## 부록: 아키텍처 1줄 요약
로그인(EC2, 개인키 RS256 서명) → JWT → API GW 네이티브 Authorizer(중앙 JWKS로 iss/aud/exp/서명 검증)
→ presigned PUT URL → 브라우저가 S3에 직접 업로드 → S3 이벤트 → thumbnailer(sharp) 썸네일 →
album-list(presigned GET)로 본인 사진만 조회.

*— 문서 버전 v1.0 · 검토 후 v1.1 업데이트 예정*
