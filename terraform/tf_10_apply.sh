#!/usr/bin/env bash
# =============================================================================
# tf_10_apply.sh — Terraform 으로 인프라 일괄 배포 (기존 01·02·04·05·06 대체)
# -----------------------------------------------------------------------------
# 선행 조건(순서 주의 — 기존 sh 흐름과 다르다!):
#   1) bash scripts/00_prereqs.sh        # 자격증명/리전 점검
#   2) bash scripts/03_publish_layer.sh  # sharp 레이어 먼저!(TF 가 이름으로 조회)
#   3) bash terraform/tf_10_apply.sh          ← 이 스크립트
#   4) bash scripts/90_smoke_test.sh     # 무수정 동작(아래 브리지 덕분)
#
# 역할:
#   - config/env.sh(단일 출처)를 TF_VAR_* 로 주입 → .tf 에 값 중복 정의 없음
#   - terraform init/apply 실행(apply 는 plan 을 보여주고 yes 확인을 받는다)
#   - terraform output → .state/resources.env 브리지(90_smoke_test 호환)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"                 # terraform/ (어디서 호출해도 동작)
REPO_ROOT="$(cd .. && pwd)"
source "${REPO_ROOT}/config/env.sh"

# 자격증명 가드(00 없이 단독 실행 대비)
if [ -z "${ACCOUNT_ID}" ]; then
  echo "❌ AWS 자격증명이 없습니다. 먼저 실행: bash scripts/00_prereqs.sh"
  exit 1
fi

echo "── 0) sharp 레이어 선행 확인(03 을 먼저 실행했는가) ──"
LATEST_LAYER="$(aws lambda list-layer-versions --layer-name "$SHARP_LAYER_NAME" \
  --region "$REGION" --query 'LayerVersions[0].LayerVersionArn' --output text 2>/dev/null || true)"
if [ -z "$LATEST_LAYER" ] || [ "$LATEST_LAYER" = "None" ]; then
  echo "❌ sharp 레이어(${SHARP_LAYER_NAME})가 없습니다."
  echo "   먼저 실행: bash scripts/03_publish_layer.sh"
  exit 1
fi
echo "  ✓ ${LATEST_LAYER}"

# env.sh(단일 출처) → Terraform 변수 주입
export TF_VAR_region="$REGION"
export TF_VAR_issuer="$ISSUER"
export TF_VAR_audience="$AUDIENCE"
export TF_VAR_api_name="$API_NAME"
export TF_VAR_lambda_role_name="$LAMBDA_ROLE_NAME"
export TF_VAR_sharp_layer_name="$SHARP_LAYER_NAME"
export TF_VAR_fn_presign="$FN_PRESIGN"
export TF_VAR_fn_thumb="$FN_THUMB"
export TF_VAR_fn_list="$FN_LIST"

echo "── 1) terraform init ────────────────────────────────"
terraform init -input=false

echo "── 2) terraform apply (plan 확인 후 yes 입력) ───────"
terraform apply

echo "── 3) 출력값 → .state/resources.env 브리지 ──────────"
# 90_smoke_test.sh 가 기존 방식 그대로 STATE_FILE 을 source 하므로,
# Terraform 출력값을 같은 파일에 같은 키로 기록해 준다.
STATE="${REPO_ROOT}/${STATE_FILE}"
mkdir -p "$(dirname "$STATE")"; touch "$STATE"
put_state() {  # $1=KEY $2=VALUE — 같은 키 라인 제거 후 append(중복 방지)
  grep -v "^$1=" "$STATE" > "$STATE.tmp" 2>/dev/null || true
  mv -f "$STATE.tmp" "$STATE"
  echo "$1=$2" >> "$STATE"
}
put_state API_ID          "$(terraform output -raw api_id)"
put_state API_ENDPOINT    "$(terraform output -raw api_endpoint)"
put_state AUTHZ_ID        "$(terraform output -raw authorizer_id)"
put_state ROLE_ARN        "$(terraform output -raw role_arn)"
put_state SHARP_LAYER_ARN "$(terraform output -raw sharp_layer_arn)"
echo "  ✓ ${STATE} 갱신 완료"

echo "✅ 배포 완료. 호출 URL: $(terraform output -raw api_endpoint)"
echo "   다음: bash scripts/90_smoke_test.sh  (auth-server 기동 상태에서)"
