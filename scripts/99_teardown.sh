#!/usr/bin/env bash
# =============================================================================
# 99_teardown.sh  —  생성한 모든 리소스 삭제 (⚠️ 파괴적)
# -----------------------------------------------------------------------------
# 비용 방지를 위해 실습 후 반드시 실행. 생성의 역순으로 지운다.
# 안전장치: 'DELETE' 를 직접 입력해야 진행.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./config/env.sh
[ -f "$STATE_FILE" ] && source "$STATE_FILE" || true

echo "⚠️  다음 리소스를 영구 삭제합니다:"
echo "    - S3 버킷: ${BUCKET} (객체 포함)"
echo "    - API: ${API_ID:-<none>}  /  Lambda 3종 + 백업"
echo "    - IAM 역할: ${LAMBDA_ROLE_NAME}  /  레이어: ${SHARP_LAYER_NAME}"
read -r -p "정말 삭제하려면 DELETE 입력: " CONFIRM
[ "$CONFIRM" = "DELETE" ] || { echo "취소됨."; exit 0; }

del() { echo "  · $*"; "$@" >/dev/null 2>&1 || true; }   # 실패해도 계속(이미 없을 수 있음)

[ -n "${API_ID:-}" ] && del aws apigatewayv2 delete-api --api-id "$API_ID" --region "$REGION"
for FN in "$FN_PRESIGN" "$FN_THUMB" "$FN_LIST" "$FN_AUTHZ_BACKUP"; do
  del aws lambda delete-function --function-name "$FN" --region "$REGION"
done
# 버킷 비우고 삭제
del aws s3 rm "s3://${BUCKET}" --recursive
del aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION"
# IAM 정리(인라인 정책 분리 → 관리형 분리 → 역할 삭제)
del aws iam delete-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-name "s3-gallery-rw"
del aws iam detach-role-policy --role-name "$LAMBDA_ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
del aws iam delete-role --role-name "$LAMBDA_ROLE_NAME"

echo "✅ 정리 완료. (레이어 버전은 콘솔에서 확인 후 수동 삭제 권장)"
rm -f "$STATE_FILE"
