# 간편앨범 Terraform 실습 가이드 (심화 과제) — v0.9

> **전제:** 기본 실습(`docs/3_jwt_presign_practice_guide.md`, CLI+sh)을 완료한 실습자 대상의 **심화 후속 과제**입니다.
> 기본 실습에서 `01~06` 스크립트로 한 단계씩 만들던 인프라를 **Terraform(선언형)** 으로 일괄 배포하고,
> 명령형(sh)과 선언형(IaC)의 차이를 체감하는 것이 목표입니다.
> **설계/구성 설명:** `terraform/doc/README.md` · **apply 실행 순서 다이어그램:** `terraform/doc/terraform_apply_sequence.png`
> **대상 환경:** 관리자 역할 인스턴스 프로파일이 연결된 배포서버 EC2(Ubuntu 24.04, x86_64).

---

## 진행 순서 한눈에

| 단계 | 내용 | 핵심 산출물 |
|---|---|---|
| A | 배포서버 EC2 준비(기본 실습 §A~B 동일) | `aws sts get-caller-identity` 성공 |
| B | 소스 동기화 + Terraform 설치 | `terraform version` 출력 |
| C | 구성(환경·개인키·AUDIENCE) | 기본 실습 §D~E와 동일 |
| D | 사전 단계 — 00 점검 + **03 레이어 먼저** | sharp 레이어 게시됨 |
| E | Terraform 일괄 배포(`tf_10_apply.sh`) | 01+02+04+05+06 상당 리소스 + API URL |
| F | 서버 구동 + 검증(90 smoke 무수정 재사용) | 업로드·썸네일·목록 |
| G | Terraform 동작 관찰(멱등성·DAG) | plan "No changes" 확인 |
| H | 자원 삭제(`tf_99_destroy.sh`) | 정리 완료 |

> ⚠️ **기본 실습 순서와 다른 점 하나:** 레이어(03)가 Terraform 배포(E)보다 **먼저**입니다.
> thumbnailer가 부착할 레이어를 Terraform이 "이름으로 조회"하므로, 레이어가 없으면 plan 단계에서 실패합니다.

---

## A. 배포서버 EC2 준비

기본 실습 §A(EC2 생성)·§B(인스턴스 프로파일 + CLI 도구)와 **완전히 동일**합니다.
- Ubuntu 24.04 LTS x86_64 · t3.micro · 보안그룹 22/3000
- 관리자 역할 `myrole_ec2_admin_profile` 연결
- 도구 설치(jq/zip/git/Node 24.x/AWS CLI v2) 후 확인:

```bash
aws sts get-caller-identity   # Arn에 assumed-role/myrole_ec2_admin_profile 이 보이면 정상
```

> ⚠️ **깨끗한 계정 상태에서 시작하세요.** 기본 실습(01~06 sh)으로 만든 리소스가 남아 있으면
> Terraform 생성 시 `already exists` 계열 오류로 실패합니다.
> 남아 있다면 먼저 `bash scripts/99_teardown.sh`(DELETE 입력)로 정리 후 진행합니다.

---

## B. 소스 동기화 + Terraform 설치

```bash
git clone <REPOSITORY_URL> simple-album   # 최초 1회 (이미 있다면 git pull)
cd ~/simple-album                          # 이후 모든 명령은 프로젝트 루트에서

bash terraform/tf_00_install.sh            # Terraform 설치(HashiCorp apt 저장소, 멱등)
terraform version                          # v1.5+ 출력 확인
```

---

## C. 구성 (환경 · 개인키 · AUDIENCE)

기본 실습과 동일한 **단일 출처** 규칙입니다 — Terraform도 값을 따로 갖지 않고
래퍼 스크립트가 `config/env.sh`를 읽어 주입합니다.

1. **환경값 확인** — `source ./config/env.sh` 로 REGION/ACCOUNT_ID/BUCKET 출력 확인 (기본 실습 §D-1)
2. **개인키 배치** — `auth-server/keys/jwt_private_key.pem` (기본 실습 §D-2, 빠뜨리면 서버 기동 실패)
3. **AUDIENCE 커스터마이징** — `auth-server/src/jwt.js` + `config/env.sh` **두 곳 일치** (기본 실습 §E)

> AUDIENCE를 바꾸면 Terraform 쪽은 파일 수정이 필요 없습니다 — `tf_10_apply.sh`가
> env.sh 값을 `TF_VAR_audience`로 주입해 JWT Authorizer 검증값까지 자동 반영됩니다.
> ⚠️ 단, **E(배포) 이후에 바꿨다면** `tf_10_apply.sh`를 다시 실행하세요
> (Terraform이 Authorizer의 audience 변경분만 감지해 in-place 업데이트합니다 — 이것도 관찰 포인트).

---

## D. 사전 단계 — 점검 + 레이어 (순서 주의!)

```bash
bash scripts/00_prereqs.sh        # 도구/자격증명/리전/ACCOUNT_ID 점검 (기본 실습과 동일)
bash scripts/03_publish_layer.sh  # sharp 레이어 빌드(EC2=linux-x64) → 게시  ← E보다 먼저!
```

> **왜 03이 먼저인가:** sharp는 네이티브 바이너리라 Terraform이 만들 수 없어 기존 sh로 게시합니다.
> Terraform은 `data "aws_lambda_layer_version"` 데이터 소스로 이 레이어의 **최신 버전을 이름으로 조회**만 합니다.
> (`tf_10_apply.sh`가 레이어 존재를 먼저 확인하고, 없으면 친절한 안내 후 중단합니다)

---

## E. Terraform 일괄 배포

기본 실습에서 5개 스크립트(01·02·04·05·06)로 나눠 하던 일을 **apply 1회**로 처리합니다.

```bash
bash terraform/tf_10_apply.sh
```

스크립트가 하는 일(자세한 로직은 파일 주석 참조):
1. `config/env.sh` 값을 `TF_VAR_*` 환경변수로 주입 (값의 단일 출처 유지)
2. `terraform init` — AWS/archive provider 다운로드(최초 1회만 오래 걸림)
3. `terraform apply` — **plan(실행 계획)이 먼저 출력**됩니다. `Plan: 19 to add...` 형태의
   요약과 리소스 목록을 읽어본 뒤 `yes` 를 입력하면 생성이 시작됩니다.
4. `terraform output` 값을 `.state/resources.env` 에 기록 — 기본 실습과 같은 키(API_ENDPOINT 등)로
   저장되므로 **90 스모크 테스트·operation 스크립트가 무수정으로 동작**합니다.

apply 로그에서 볼 것 (다이어그램 `terraform_apply_sequence.png`와 대조):
```
aws_s3_bucket.album: Creating...          ─┐
aws_iam_role.lambda: Creating...           ├─ 서로 참조가 없어 동시에 시작(병렬)
aws_apigatewayv2_api.album: Creating...   ─┘
...
aws_lambda_function.presign: Creation complete after 12s
aws_apigatewayv2_integration.presign: Creating...   ← Lambda 완료를 기다렸다가 시작(참조 의존)
```

완료 시 출력되는 `호출 URL(api_endpoint)`을 확인하세요.

---

## F. 서버 구동 + 검증

기본 실습 §F~G와 동일합니다 (Terraform이어도 이후 절차는 달라지지 않습니다):

```bash
cd auth-server && npm install && cd ..    # 최초 1회
bash operation/startup.sh                 # 백그라운드 기동 (API_ENDPOINT 자동 로드)

bash scripts/90_smoke_test.sh             # 로그인→presign→PUT→썸네일→목록 end-to-end
```

브라우저 `http://<EC2-PUBLIC-IP>:3000` → 로그인(james/demo) → 업로드 → 썸네일 확인.
`aud` 격리 실증(2인 1조 교차 401)도 기본 실습 §G-2 그대로 진행 가능합니다.

---

## G. Terraform 동작 관찰 (이 과제의 학습 포인트)

인프라가 떠 있는 상태에서, 명령형(sh)과의 차이를 눈으로 확인합니다.

### G-1. 멱등성 — "No changes"
```bash
cd terraform
terraform plan     # → "No changes. Your infrastructure matches the configuration."
```
기본 실습의 sh는 `head-bucket`/`get-role` 등으로 멱등성을 **직접 구현**했지만,
Terraform은 tfstate와 실제를 비교해 **자동 판단**합니다.

### G-2. 드리프트 감지 — 콘솔에서 손대보기
AWS 콘솔에서 버킷 CORS 규칙을 하나 지운 뒤:
```bash
terraform plan     # → 지워진 CORS를 감지하고 "1 to change" 로 복원 계획 제시
terraform apply    # → 선언된 상태로 되돌림
```
> 수동 변경(드리프트)이 코드와 어긋나면 감지·복원된다 — sh에는 없는 능력입니다.

### G-3. 의존 그래프 실물 확인
```bash
terraform graph                      # DAG를 DOT 텍스트로 출력
sudo apt-get install -y graphviz     # (선택) 이미지로 렌더링
terraform graph | dot -Tpng > my_graph.png
```
`doc/terraform_apply_sequence.png` 다이어그램의 "실물 버전"입니다.

### G-4. (선택) 직렬 실행으로 순서 관찰
```bash
terraform destroy -auto-approve && terraform apply -parallelism=1
```
병렬도를 1로 낮추면 의존 순서대로 한 개씩 생성되어 로그에서 순서가 가장 또렷하게 보입니다.

---

## H. 자원 삭제 (보안 위협 · 비용 소요)

> ⚠️ **Terraform으로 배포했다면 반드시 `tf_99_destroy.sh`로 지웁니다.**
> 기존 `99_teardown.sh`(CLI 삭제)를 쓰면 tfstate와 실제 상태가 어긋납니다.

### H-0. auth-server 중지
```bash
bash operation/stop.sh
```

### H-1. Terraform 리소스 + 레이어 삭제(파괴적)
```bash
bash terraform/tf_99_destroy.sh    # 확인 프롬프트에 DELETE 입력
#   삭제: TF 관리 리소스 전부(버킷·Lambda 3종·HTTP API·IAM) + sharp 레이어 전 버전 + .state
```
> 기본 sh teardown과 달리 **레이어 버전까지 함께 정리**합니다(destroy 후 CLI로 삭제).
> 버킷은 `force_destroy` 설정으로 객체가 남아 있어도 비우고 삭제됩니다.

### H-2. EC2/역할/개인키 정리
기본 실습 §H-2(EC2 종료) · §H-3(관리자 역할 정리) · §H-4(개인키 폐기)와 동일합니다.

---

## 자주 막히는 곳

| 증상 | 원인 · 조치 |
|---|---|
| plan 단계 `no matching Lambda Layer Version found` | §D의 03을 아직 안 돌림 → `bash scripts/03_publish_layer.sh` 먼저 |
| `BucketAlreadyOwnedByYou` / `EntityAlreadyExists` | 기본 실습(sh) 리소스 잔존 → `bash scripts/99_teardown.sh` 로 정리 후 재시도 |
| `Error: Invalid provider configuration` / init 실패 | 네트워크로 provider 다운로드 불가 → 프록시/보안그룹 아웃바운드 확인 |
| 90 smoke test에서 API_ENDPOINT 비어 있음 | 래퍼 없이 `terraform apply`만 직접 실행함 → `bash terraform/tf_10_apply.sh` 재실행(.state 브리지 기록) |
| destroy가 레이어 조회 실패로 중단 | 레이어를 수동으로 먼저 지운 경우 → `terraform destroy -refresh=false` |
| 401 Unauthorized | 토큰 `iss/aud/kid` 확인 — 특히 §C의 AUDIENCE 두 곳 일치 + 변경 후 재apply 여부 |
| 403 SignatureDoesNotMatch | presign contentType ≠ PUT Content-Type (기본 실습과 동일) |

---

## 부록: sh ↔ Terraform 대응 한눈에

| 기본 실습(sh) | 이 과제 | 비고 |
|---|---|---|
| 00_prereqs.sh | 그대로 사용 | + `tf_00_install.sh` (Terraform 설치) |
| 01·02·04·05·06 | `terraform apply` 1회 | .tf 파일과 1:1 매핑은 README §3 |
| 03_publish_layer.sh | 그대로 사용 — **단 apply보다 먼저** | 네이티브 빌드는 IaC 밖 |
| 90_smoke_test.sh | 그대로 사용 | `.state` 브리지 덕분에 무수정 |
| 99_teardown.sh | `tf_99_destroy.sh` 로 대체 | 레이어 버전까지 정리 |

아키텍처는 기본 실습과 동일: 로그인(RS256) → JWT → API GW 네이티브 Authorizer →
presigned PUT → S3 직접 업로드 → S3 이벤트 → thumbnailer → album-list(presigned GET).

---

*— 문서 버전 v0.9 (초안) · 강사용 EC2 리허설(init/validate/apply/destroy end-to-end) 통과 후 v1.0 안정화 예정.
검증 전 유의: HCL은 아직 실환경 미검증 상태이며, plan 요약의 리소스 개수 등 세부 수치는 리허설 후 확정.*
