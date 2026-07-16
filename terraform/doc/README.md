# Terraform 심화 과제 — Simple Album 인프라를 선언형으로

> 기존 `scripts/01~06`(AWS CLI + sh, 명령형)로 만들던 인프라를 Terraform(선언형)으로
> 재구성하는 **심화 후속 과제**용 실습 자료. (위치: `terraform/`, 문서: `terraform/doc/`)
> 배포는 관리자 역할 인스턴스 프로파일이 적용된 **배포서버 EC2(Ubuntu 24.04)** 에서 진행한다.

---

## 1. 하이브리드 구성 — 제안안 검토 결과

제안된 분담은 **그대로 실현 가능**하다. 단, 4가지 보완이 필요하다(§2).

| 단계 | 담당 | 판정 · 비고 |
|---|---|---|
| 00_prereqs | 기존 sh 유지 | ✅ 사전 점검은 IaC 대상 아님 |
| 01 버킷+CORS | Terraform | ✅ `s3.tf` |
| 02 IAM | Terraform | ✅ `iam.tf` (sleep 10 불필요 — provider 가 재시도) |
| 03 sharp 레이어 | 기존 sh 유지 | ✅ 단 **실행 순서가 apply 앞으로 이동**(§2-1) |
| 04 Lambda 배포 | Terraform | ✅ `lambda.tf` (zip 패키징은 archive provider 가 대체) |
| 05 HTTP API+Authorizer | Terraform | ✅ `apigw.tf` |
| 06 S3 이벤트 | Terraform | ✅ `s3_event.tf` |
| 90 smoke test | 기존 sh 유지 | ✅ 무수정 동작 — **출력 브리지 필요**(§2-2) |
| 99 teardown | 기존 sh 유지 | ⚠️ **대안 권장** — TF 리소스는 `tf_99_destroy.sh` 로(§2-3) |

### 보완 4가지 (대안 의견)

1. **실행 순서 변경: 03이 apply보다 먼저.**
   thumbnailer(04→TF)가 레이어 ARN을 필요로 한다. Terraform 은
   `data "aws_lambda_layer_version"` 으로 03이 게시한 최신 버전을 이름(`sharp-x64`)으로
   조회하므로, **레이어가 먼저 존재해야 plan 이 통과**한다. 03은 버킷/IAM에 의존하지
   않으므로 앞당겨도 문제 없다.

2. **90 호환용 출력 브리지.**
   `90_smoke_test.sh` 는 `.state/resources.env` 의 `API_ENDPOINT` 를 source 한다.
   `tf_10_apply.sh` 가 apply 후 `terraform output` 을 같은 파일·같은 키로 기록해
   **90을 한 줄도 고치지 않고** 재사용한다.

3. **teardown 이원화 — 99_teardown.sh 를 TF 리소스에 쓰지 말 것.**
   TF가 만든 리소스를 CLI(99)로 지우면 tfstate와 실제 상태가 어긋난다(교육적으로도
   잘못된 습관). TF 리소스 + 레이어 정리는 `tf_99_destroy.sh` 가 담당한다.
   기존 99는 "sh 방식으로 배포했을 때"의 짝으로만 유지.

4. **env.sh 단일 출처 유지.**
   `.tf` 에 값을 중복 정의하지 않도록, 래퍼(`tf_10_apply.sh`)가 `config/env.sh` 를
   source 하여 `TF_VAR_*` 로 주입한다. 계정ID는 `aws_caller_identity` 데이터 소스로
   동적 취득(하드코딩 금지 규칙 동일 적용).

---

## 2. 실행 순서 (기존 sh 흐름과 순서가 다름에 주의)

```bash
# 배포서버 EC2 (관리자 프로파일 적용, Ubuntu 24.04)
git clone <repo> && cd jwt-presign

bash scripts/00_prereqs.sh              # 1) 자격증명/리전/CLI 점검  (sh)
bash terraform/tf_00_install.sh         # 2) Terraform 설치(최초 1회) (sh)
bash scripts/03_publish_layer.sh        # 3) sharp 레이어 게시 — 먼저! (sh)
bash terraform/tf_10_apply.sh           # 4) 01+02+04+05+06 일괄 배포 (TF)
# (auth-server 기동: cd auth-server && npm install && 별도 터미널 npm start)
bash scripts/90_smoke_test.sh           # 5) end-to-end 검증          (sh)

bash terraform/tf_99_destroy.sh         # 6) 전체 삭제(수업 종료 후)   (TF)
```

기존 sh 흐름(`00→01→02→03→04→05→06→90`)과 달리 **03이 3번째**로 온다.

---

## 3. 파일 구성 (기존 스크립트와 1:1 매핑)

```
terraform/
├── versions.tf      # Terraform/Provider 버전 고정
├── variables.tf     # 입력 변수(값은 env.sh 에서 주입)
├── main.tf          # 계정ID·레이어 조회(data) + 공통 locals
├── s3.tf            # ← 01_create_bucket.sh
├── iam.tf           # ← 02_create_iam_roles.sh
├── lambda.tf        # ← 04_deploy_lambdas.sh
├── apigw.tf         # ← 05_create_http_api.sh
├── s3_event.tf      # ← 06_wire_s3_event.sh
├── outputs.tf       # 출력값(→ .state 브리지의 원천)
├── tf_00_install.sh # Terraform 설치(Ubuntu, HashiCorp apt 저장소)
├── tf_10_apply.sh   # env.sh 주입 → init/apply → .state 브리지
├── tf_99_destroy.sh # destroy + 레이어 버전 정리 (⚠️ DELETE 입력 필요)
├── .gitignore       # tfstate/.terraform 커밋 방지
└── doc/
    ├── README.md                     # 이 문서
    └── terraform_apply_sequence.png  # apply 실행 순서(DAG) 다이어그램
```

---

## 4. 교육 포인트 — 명령형 vs 선언형 비교 관찰

| 관찰 대상 | 기존 sh 에서 | Terraform 에서 |
|---|---|---|
| 멱등성 | `head-bucket`/`get-role` 로 직접 확인 후 분기 | tfstate 와 비교해 자동 판단 (`plan` 이 "No changes" 출력) |
| 값 치환 | `sed __BUCKET__` 치환 | 리소스 참조(`aws_s3_bucket.album.arn`) |
| 의존 순서 | 스크립트 번호(01→02→…)로 사람이 관리 | 참조 그래프에서 자동 도출 |
| IAM 전파 대기 | `sleep 10` | provider 내부 재시도 |
| 코드 변경 감지 | 매번 update-function-code | `source_code_hash` 로 변경시에만 |
| 삭제 | 역순으로 CLI 삭제 나열 | `destroy` 한 번 |

실습 중 `terraform plan` 을 두 번째 실행해 "No changes" 를 확인시키면
멱등성 개념이 가장 선명하게 전달된다.

apply 가 리소스를 어떤 순서로 만드는지(참조 그래프 기반 병렬 실행)는
`doc/terraform_apply_sequence.png` 다이어그램 참조.

---

## 5. 기존 sh 배포와의 공존 주의사항

- **같은 계정에서 sh(01~06)와 TF를 섞어 쓰지 말 것.**
  이미 sh로 리소스를 만든 계정에서 `apply` 하면 "already exists" 로 실패한다.
  → 기존 sh 리소스를 `99_teardown.sh` 로 정리한 **깨끗한 상태에서 시작**한다.
  (심화의 심화: `terraform import` 로 기존 리소스를 tfstate 에 편입하는 과제도 가능)
- **teardown 짝 맞추기:** sh 로 배포 → `99_teardown.sh` / TF 로 배포 → `tf_99_destroy.sh`.
- tfstate 는 로컬 파일(기본)이며 배포서버 EC2에만 존재한다. 계정 단위 격리 실습이므로
  원격 백엔드(S3+DynamoDB lock)는 불필요 — 이것도 "언제 원격 백엔드가 필요한가"
  토론 소재로 활용 가능.

---

## 6. 트러블슈팅

| 증상 | 원인 · 조치 |
|---|---|
| plan 단계 `no matching Lambda Layer Version found` | 03을 아직 안 돌림 → `bash scripts/03_publish_layer.sh` 먼저 |
| apply 시 `BucketAlreadyOwnedByYou` / `EntityAlreadyExists` | sh(01~06)로 만든 리소스 잔존 → `99_teardown.sh` 로 정리 후 재시도 |
| destroy 가 레이어 조회 실패로 중단 | 레이어를 먼저 수동 삭제한 경우 → `terraform destroy -refresh=false` |
| 90 smoke test 에서 API_ENDPOINT 비어 있음 | `tf_10_apply.sh` 를 안 거치고 직접 `terraform apply` 함 → 래퍼로 재실행(브리지 기록) |
| 401 Unauthorized | issuer 끝 슬래시/aud 불일치 — sh 실습과 동일한 체크포인트 |

---

## 7. 리포 위생

- `terraform/` 은 공개 리포에 **추적되는** 디렉토리다. 실행 시 생기는 로컬 산출물
  (`.terraform/`, `*.tfstate*`, `build/`)은 `terraform/.gitignore` 가 커밋을 막는다.
- **tfstate 는 절대 커밋 금지** — 계정ID·ARN 등 실환경 값이 그대로 담긴다.
- `.tf` 파일에는 계정ID·시크릿이 없다(동적 취득 + env.sh 주입) — 커밋 전 스캔은 기존과 동일.
