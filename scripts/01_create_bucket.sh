#!/usr/bin/env bash
# =============================================================================
# 01_create_bucket.sh  —  S3 버킷 생성 + 퍼블릭 차단 + CORS 적용
# -----------------------------------------------------------------------------
# 멱등성: 이미 버킷이 있으면 생성을 건너뛴다(재실행 안전).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./config/env.sh

echo "── 버킷 ${BUCKET} 확인/생성 ─────────────────────────"
# head-bucket: 있으면 0, 없으면 비0. 멱등성 체크에 사용.
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "  이미 존재 → 생성 건너뜀"
else
  # 주의: ap-northeast-2 는 LocationConstraint 가 '필수'다(us-east-1 만 예외).
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration "LocationConstraint=${REGION}"
  echo "  ✓ 생성됨"
fi

echo "── 퍼블릭 액세스 전체 차단(조회는 presigned URL로) ──"
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "── CORS 적용(브라우저 직접 PUT/GET 허용) ────────────"
aws s3api put-bucket-cors --bucket "$BUCKET" \
  --cors-configuration "file://config/s3-cors.json"

echo "✅ 버킷 준비 완료. 다음: bash scripts/02_create_iam_roles.sh"
