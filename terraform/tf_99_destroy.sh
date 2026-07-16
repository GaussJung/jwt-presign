#!/usr/bin/env bash
# =============================================================================
# tf_99_destroy.sh — Terraform 이 만든 리소스 전체 삭제 (⚠️ 파괴적)
# -----------------------------------------------------------------------------
# ⚠️ Terraform 으로 배포했다면 반드시 이 스크립트로 지운다.
#    기존 99_teardown.sh(CLI 직접 삭제)를 쓰면 tfstate 와 실제 상태가 어긋난다.
# 삭제 범위:
#   - tfstate 관리 리소스 전부(API·Lambda 3종·IAM·버킷 — 객체 포함 force_destroy)
#   - sharp 레이어 버전(03 이 TF 밖에서 게시 → destroy 후 CLI 로 별도 정리)
# 안전장치: 'DELETE' 를 직접 입력해야 진행. (99_teardown.sh 와 동일 관례)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"                 # terraform/
REPO_ROOT="$(cd .. && pwd)"
source "${REPO_ROOT}/config/env.sh"

echo "⚠️  다음 리소스를 영구 삭제합니다:"
echo "    - Terraform 관리 리소스 전부: S3 버킷 ${BUCKET}(객체 포함) / API ${API_NAME}"
echo "      / Lambda 3종 / IAM 역할 ${LAMBDA_ROLE_NAME}"
echo "    - sharp 레이어(${SHARP_LAYER_NAME}) 모든 버전"
read -r -p "정말 삭제하려면 DELETE 입력: " CONFIRM
[ "$CONFIRM" = "DELETE" ] || { echo "취소됨."; exit 0; }

# destroy 시에도 plan 이 변수·데이터소스를 평가하므로 env.sh 값을 동일하게 주입
export TF_VAR_region="$REGION"
export TF_VAR_issuer="$ISSUER"
export TF_VAR_audience="$AUDIENCE"
export TF_VAR_api_name="$API_NAME"
export TF_VAR_lambda_role_name="$LAMBDA_ROLE_NAME"
export TF_VAR_sharp_layer_name="$SHARP_LAYER_NAME"
export TF_VAR_fn_presign="$FN_PRESIGN"
export TF_VAR_fn_thumb="$FN_THUMB"
export TF_VAR_fn_list="$FN_LIST"

echo "── 1) terraform destroy ─────────────────────────────"
# 레이어 data 소스 평가가 필요하므로 레이어 삭제(2단계)보다 먼저 실행해야 한다.
terraform destroy -auto-approve

echo "── 2) sharp 레이어 버전 정리(TF 관리 밖) ────────────"
for V in $(aws lambda list-layer-versions --layer-name "$SHARP_LAYER_NAME" \
  --region "$REGION" --query 'LayerVersions[].Version' --output text 2>/dev/null); do
  echo "  · 레이어 버전 ${V} 삭제"
  aws lambda delete-layer-version --layer-name "$SHARP_LAYER_NAME" \
    --version-number "$V" --region "$REGION" 2>/dev/null || true
done

# 브리지로 기록했던 리소스 ID 캐시 제거(99_teardown.sh 와 동일)
rm -f "${REPO_ROOT}/${STATE_FILE}"

echo "✅ 정리 완료."
