#!/usr/bin/env bash
# =============================================================================
# 02_create_iam_roles.sh  —  Lambda 실행 역할 + 최소권한 정책
# -----------------------------------------------------------------------------
# 만드는 것:
#   - 역할(Role): Lambda 가 맡을 수 있는 역할 (trust policy)
#   - 기본 로깅 권한: AWSLambdaBasicExecutionRole (CloudWatch Logs)
#   - 인라인 S3 권한: 우리 버킷 gallery/* 에 한정 (최소권한)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./config/env.sh

# .state/ 자기완결 보장(00 없이 단독 실행 대비) + STATE_FILE 키 갱신 헬퍼.
#   put_state: 같은 키 라인을 제거 후 append → 재실행 시 '절단/중복 라인' 방지.
mkdir -p "$(dirname "$STATE_FILE")"; touch "$STATE_FILE"
put_state() {  # $1=KEY $2=VALUE
  grep -v "^$1=" "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null || true
  mv -f "$STATE_FILE.tmp" "$STATE_FILE"
  echo "$1=$2" >> "$STATE_FILE"
}

echo "── 역할 ${LAMBDA_ROLE_NAME} 생성/확인 ───────────────"
if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" >/dev/null 2>&1; then
  echo "  이미 존재 → 건너뜀"
else
  aws iam create-role \
    --role-name "$LAMBDA_ROLE_NAME" \
    --assume-role-policy-document "file://config/lambda-trust-policy.json" >/dev/null
  echo "  ✓ 역할 생성"
fi

echo "── 기본 로깅 권한 부착 ──────────────────────────────"
aws iam attach-role-policy --role-name "$LAMBDA_ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

echo "── S3 인라인 권한 부착(__BUCKET__ 치환) ─────────────"
# 템플릿의 __BUCKET__ 을 실제 버킷명으로 치환해 임시 파일 생성
sed "s/__BUCKET__/${BUCKET}/g" config/lambda-s3-policy.json > .state/lambda-s3-policy.json
aws iam put-role-policy --role-name "$LAMBDA_ROLE_NAME" \
  --policy-name "s3-gallery-rw" \
  --policy-document "file://.state/lambda-s3-policy.json"

# 역할 ARN 을 상태 파일에 저장(다음 단계에서 사용)
#   예시: arn:aws:iam::111122223333:role/simple-album-lambda-role
ROLE_ARN="$(aws iam get-role --role-name "$LAMBDA_ROLE_NAME" --query 'Role.Arn' --output text)"
put_state ROLE_ARN "$ROLE_ARN"
echo "  ✓ ROLE_ARN=${ROLE_ARN}"

# IAM 전파 지연 주의: 역할 생성 직후 Lambda 생성 시 간헐적 실패 가능 → 잠시 대기
echo "  (IAM 전파 대기 10초)"; sleep 10
echo "✅ 역할 준비 완료. 다음: bash scripts/03_publish_layer.sh"
