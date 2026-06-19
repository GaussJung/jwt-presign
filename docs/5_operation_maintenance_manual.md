# 간편앨범 운영/유지보수 매뉴얼

> **대상:** 구축 완료 후 반복 운영 작업.
> 모든 명령은 **프로젝트 루트(`~/simple-album/`)** 에서 실행합니다.
> 설정값은 `config/env.sh` 로드 후 환경변수로 참조합니다.
> Ubuntu 24.04 / 기본 사용자 `ubuntu` 기준.

---

## 1. 서비스 기동 / 정지

### 1-1. 기동

**목적:** auth-server를 백그라운드에서 실행하고 SSH 세션이 끊겨도 유지시킨다.

```bash
bash operation/startup.sh
```

**정상 확인:**
```
  ✓ auth-server 기동 완료
    PID : 12345
    로그: tail -f operation/.run/auth-server.log
    주소: http://<EC2-PUBLIC-IP>:3000
```
PID 파일이 생성되고 브라우저에서 `http://<EC2-PUBLIC-IP>:3000` 접속 가능하면 성공.

> **주의:** `startup.sh`는 `nohup`으로 실행하므로 SSH 연결이 끊겨도 서버는 유지됩니다.
> 단, **EC2 재부팅 후에는 재기동이 필요**합니다. 자동화하려면 §1-3을 참고하세요.

---

### 1-2. 정지

**목적:** auth-server 프로세스를 안전하게 종료한다(멱등 — 이미 중지 상태여도 안전).

```bash
bash operation/stop.sh
```

**정상 확인:**
```
  ✓ auth-server 종료 (PID 12345)
  · PID 파일 정리 완료
```
또는 이미 중지 상태였다면:
```
  ℹ PID 파일 없음 — 이미 중지 상태입니다.
```

---

### 1-3. EC2 재부팅 시 자동 기동 (crontab @reboot)

**목적:** EC2가 재부팅된 후 수동 개입 없이 auth-server가 자동으로 기동되도록 설정한다.

```bash
crontab -e
```

편집기가 열리면 **맨 아래**에 다음 한 줄을 추가하고 저장합니다.

```
@reboot sleep 15 && bash /home/ubuntu/simple-album/operation/startup.sh >> /home/ubuntu/simple-album/operation/.run/reboot-startup.log 2>&1
```

> `sleep 15` — 재부팅 직후 EC2 인스턴스 메타데이터 서비스(IMDS)가 준비되기 전에
> `startup.sh`가 실행되면 AWS 자격증명을 취득하지 못할 수 있습니다.
> 15초 대기로 네트워크와 IMDS가 안정된 뒤 기동합니다.

**설정 확인:**
```bash
crontab -l   # 추가된 @reboot 줄이 보이면 등록 완료
```

**재부팅 후 정상 확인:**
```bash
# EC2 재기동 후 SSH 접속하여 확인
cat operation/.run/reboot-startup.log   # 기동 로그
cat operation/.run/auth-server.pid      # PID 파일 존재 확인
curl -s http://localhost:3000/config.json | jq .   # 응답 확인
```

**설정 제거 방법 (자동 시작 비활성화):**
```bash
crontab -e   # @reboot 줄을 삭제하고 저장
```

---

## 2. 상태 확인 (Health Check)

### 2-1. PID / 프로세스 확인

**목적:** auth-server가 실제로 실행 중인지 확인한다.

```bash
# PID 파일 확인
cat operation/.run/auth-server.pid

# 해당 PID 프로세스 존재 여부
ps -p $(cat operation/.run/auth-server.pid) -o pid,stat,cmd
```

**정상 확인:** `S` 또는 `Sl` 상태의 `node` 프로세스가 보이면 정상.

---

### 2-2. HTTP 응답 확인

**목적:** auth-server가 요청을 정상 처리하는지 확인한다.

```bash
# config.json 반환 확인 (인증 불필요)
curl -s http://localhost:3000/config.json | jq .
```

**정상 확인:** `{ "apiEndpoint": "https://..." }` 형태의 JSON 반환.

---

### 2-3. API Gateway + Lambda 동작 확인

**목적:** 로그인 → JWT → presign/albums API 전체 흐름이 동작하는지 확인한다.

```bash
source config/env.sh
source "${STATE_FILE}"   # API_ENDPOINT 로드

# 토큰 발급
TOKEN=$(curl -s -X POST http://localhost:3000/login \
  -H 'content-type: application/json' \
  -d '{"username":"james","password":"demo"}' | jq -r .token)

# albums API 호출
curl -s -X GET "${API_ENDPOINT}/albums" \
  -H "Authorization: Bearer ${TOKEN}" | jq .
```

**정상 확인:** `{ "items": [...] }` 반환. `401` 이면 토큰/Authorizer 불일치, `403` 이면 Lambda 권한 문제.

---

## 3. Lambda 소스 개선 후 재배포

**목적:** `lambdas/` 하위 코드를 수정한 뒤 AWS Lambda에 반영한다.

```bash
# 1) 코드 수정 (예: lambdas/thumbnailer/index.mjs 편집)
# 2) 재배포 — 기존 스크립트 재사용(멱등)
bash scripts/04_deploy_lambdas.sh
```

**정상 확인:**
```bash
source config/env.sh
aws lambda get-function --function-name "${FN_THUMB}" \
  --query 'Configuration.[FunctionName,LastModified,CodeSize]' \
  --output table --region "${REGION}"
```
`LastModified` 가 방금 시각이면 배포 성공.

> **thumbnailer 주의:** `lambdas/thumbnailer/` 를 수정할 때 **sharp 레이어 의존 코드를 건드리지 않았다면** 레이어 재빌드(`03_publish_layer.sh`)는 불필요합니다.
> Node.js 버전을 변경하거나 `sharp` import 방식을 바꿨다면 `03_publish_layer.sh` → `04_deploy_lambdas.sh` 순서로 재실행하세요.

---

## 4. 웹앱(auth-server) 소스 개선 후 재배포

**목적:** `auth-server/` 코드를 수정한 뒤 실행 중인 서버에 반영한다.

```bash
# 1) 최신 코드 pull
git pull

# 2) 의존성 갱신 (package.json 이 변경된 경우에만 필요)
cd auth-server && npm install && cd ..

# 3) 서버 재기동 (stop → start)
bash operation/stop.sh
bash operation/startup.sh
```

**정상 확인:** §2-2 / §2-3 절차로 응답 확인.

> `auth-server/public/` 의 정적 파일(HTML/JS/CSS)은 서버가 요청마다 디스크에서 읽으므로
> `git pull` 후 재기동만으로 브라우저에 즉시 반영됩니다.

---

## 5. 환경설정 변경 반영

> ⚠️ **핵심 원칙:** 토큰의 `iss`/`aud` 값과 API Gateway Authorizer 설정이 한 글자라도 다르면
> **전원 401** 이 됩니다. 아래 나열된 모든 지점을 **동시에** 반영한 뒤 재배포하세요.

---

### 5-1. AUDIENCE 변경

영향 지점 4곳을 **모두** 변경해야 합니다.

| 위치 | 변경 내용 |
|---|---|
| `config/env.sh` | `AUDIENCE="myalbum-new"` |
| `auth-server/src/jwt.js` | `const AUDIENCE = "myalbum-new";` |
| Lambda 환경변수 | `04_deploy_lambdas.sh` 재실행으로 반영 |
| API GW Authorizer 검증값 | `05_create_http_api.sh` 재실행으로 반영 |

```bash
# 1) 두 파일 동시 수정 (myalbum-old → myalbum-new)
sed -i 's/myalbum-old/myalbum-new/' auth-server/src/jwt.js config/env.sh

# 2) Lambda + API GW 재배포
bash scripts/04_deploy_lambdas.sh
bash scripts/05_create_http_api.sh

# 3) auth-server 재기동
bash operation/stop.sh
bash operation/startup.sh
```

**정상 확인:** §2-3 절차로 새 `aud` 토큰 → 200 확인.

---

### 5-2. ISSUER(인증서버) 변경

영향 지점과 절차는 AUDIENCE 변경과 동일합니다.

| 위치 | 변경 내용 |
|---|---|
| `config/env.sh` | `ISSUER="https://new-issuer.example.com"` |
| `auth-server/src/jwt.js` | `const ISSUER = "https://new-issuer.example.com";` |
| Lambda 환경변수 | `04_deploy_lambdas.sh` 재실행 |
| API GW Authorizer issuer | `05_create_http_api.sh` 재실행 |

```bash
bash scripts/04_deploy_lambdas.sh
bash scripts/05_create_http_api.sh
bash operation/stop.sh
bash operation/startup.sh
```

> ⚠️ **JWKS 일치 필수:** API Gateway는 새 issuer의 `/.well-known/jwks.json` 에서 공개키를
> 가져와 서명을 검증합니다. **auth-lab 측 JWKS가 새 issuer URL과 일치하도록** 사전에
> 확인하세요. 불일치 시 올바른 토큰도 401 처리됩니다.

---

## 6. 문제 발생 시 로그 보기

### 6-1. Lambda CloudWatch 로그

```bash
source config/env.sh

# 실시간 스트리밍 (Ctrl+C 로 중단)
aws logs tail /aws/lambda/${FN_PRESIGN}  --follow --region "${REGION}"
aws logs tail /aws/lambda/${FN_THUMB}    --follow --region "${REGION}"
aws logs tail /aws/lambda/${FN_LIST}     --follow --region "${REGION}"

# 최근 1시간 오류만 추출
aws logs tail /aws/lambda/${FN_THUMB} --since 1h --region "${REGION}" 2>&1 \
  | grep -o '"errorMessage":"[^"]*"'
```

**로그 그룹 경로:** `/aws/lambda/<함수명>` (AWS 콘솔 → CloudWatch → 로그 그룹에서도 확인)

---

### 6-2. auth-server 로그

```bash
# 실시간 확인
tail -f operation/.run/auth-server.log

# 최근 50줄
tail -50 operation/.run/auth-server.log
```

---

### 6-3. 증상 → 원인 매핑

| 증상 | 가능한 원인 | 확인 방법 |
|---|---|---|
| **401 Unauthorized** | `iss`/`aud`/`kid` 불일치, 토큰 만료, Authorizer 설정 오류 | §5 변경 지점 모두 일치 확인 |
| **403 SignatureDoesNotMatch** | presign의 `contentType` ≠ S3 PUT `Content-Type` | 브라우저 네트워크 탭에서 두 값 대조 |
| **CORS 오류** | API GW CORS 미설정 또는 `Authorization` 헤더 미허용 | `05_create_http_api.sh` 재실행 |
| **썸네일 미생성** | S3 이벤트 트리거 누락, thumbnailer 오류 | `06_wire_s3_event.sh` 확인, CloudWatch 로그 §6-1 |
| **화면 안 열림** | auth-server 미기동, 보안그룹 3000 미오픈, `API_ENDPOINT` 미설정 | §2-1/2-2 확인, EC2 보안그룹 인바운드 확인 |
| **`Unable to locate credentials`** | 인스턴스 프로파일 미연결 | EC2 콘솔 → 작업 → 보안 → IAM 역할 확인 |

---

## 7. Lambda 롤백 (개요)

> 교육 환경에서는 배포 시 `$LATEST` 를 덮어씁니다. 별도 버전/별칭을 발행하지 않으므로
> **이전 배포로 되돌리려면 git에서 원하는 커밋을 체크아웃한 뒤 재배포**하는 것이 가장 확실합니다.

```bash
# 1) 이전 커밋으로 코드 되돌리기
git log --oneline -10            # 되돌릴 커밋 해시 확인
git checkout <커밋해시> -- lambdas/thumbnailer/index.mjs   # 특정 파일만 복원

# 2) 재배포
bash scripts/04_deploy_lambdas.sh
```

운영 환경에서는 `aws lambda publish-version` + `aws lambda update-alias` 로
버전/별칭 기반 롤백을 구성하는 것이 권장됩니다(교육 범위 외).

---

*— 문서 버전 v1.0 · 구축 완료 후 반복 운영 작업 절차서*
