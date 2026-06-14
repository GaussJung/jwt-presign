#!/usr/bin/env bash
# =============================================================================
# 06_wire_s3_event.sh  —  S3 업로드 이벤트 → thumbnailer Lambda 연결
# -----------------------------------------------------------------------------
# ⚠️ 무한루프 방지(가장 중요): 트리거는 'gallery/original/' prefix 에만 건다.
#    썸네일은 'gallery/thumb/' 로 쓰므로, 썸네일 생성이 다시 트리거되지 않는다.
# 순서: (1) S3가 람다를 호출할 권한 부여  →  (2) 버킷 알림 설정
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./config/env.sh
source "$STATE_FILE"

THUMB_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${FN_THUMB}"

echo "── 1) S3 → Lambda 호출 권한 ────────────────────────"
aws lambda add-permission --function-name "$FN_THUMB" --region "$REGION" \
  --statement-id "s3invoke" --action "lambda:InvokeFunction" \
  --principal s3.amazonaws.com \
  --source-arn "arn:aws:s3:::${BUCKET}" \
  --source-account "$ACCOUNT_ID" >/dev/null 2>&1 || true

echo "── 2) 버킷 이벤트 알림 설정(original/ prefix 한정) ──"
# 알림 설정 JSON 을 동적으로 생성(__ARN__ 치환)
cat > .state/notif.json << JSON
{
  "LambdaFunctionConfigurations": [
    {
      "LambdaFunctionArn": "${THUMB_ARN}",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": { "Key": { "FilterRules": [ { "Name": "prefix", "Value": "gallery/original/" } ] } }
    }
  ]
}
JSON
aws s3api put-bucket-notification-configuration --bucket "$BUCKET" \
  --notification-configuration "file://.state/notif.json"

echo "✅ 이벤트 연결 완료. 다음: bash scripts/90_smoke_test.sh"
