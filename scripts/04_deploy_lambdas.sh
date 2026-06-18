#!/usr/bin/env bash
# =============================================================================
# 04_deploy_lambdas.sh  —  Lambda 함수 3종 배포(presign / thumbnailer / list)
# -----------------------------------------------------------------------------
# 멱등성: 함수가 있으면 코드만 업데이트, 없으면 새로 생성.
# 공통 환경변수: 함수 코드가 process.env 로 읽는다(BUCKET/REGION/ISSUER/AUDIENCE).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./config/env.sh
source "$STATE_FILE"   # ROLE_ARN, SHARP_LAYER_ARN 로드

# 함수 코드 zip 패키징 헬퍼
#   $1=람다 디렉토리(lambdas/xxx)  →  build/xxx.zip 생성
package() {
  local dir="$1" name; name="$(basename "$dir")"
  echo "  · 패키징 ${name}"
  ( cd "$dir" && npm install --omit=dev >/dev/null 2>&1 || true )  # 의존성(있으면)
  rm -f "build/${name}.zip"; mkdir -p build
  ( cd "$dir" && zip -qr "../../build/${name}.zip" . -x "*.git*" )
}

# 함수 생성-또는-업데이트 헬퍼
#   $1=함수명 $2=핸들러 $3=zip $4..=추가 옵션(레이어/메모리 등)
deploy() {
  local fn="$1" handler="$2" zip="$3"; shift 3
  # 코드 외 설정(런타임/핸들러/역할/환경변수). create·update 양쪽에 동일 적용한다.
  #   $@ = 함수별 추가옵션(--timeout/--memory-size/--layers) — create/update-config 모두 유효.
  local cfg=(--runtime nodejs20.x --role "$ROLE_ARN" --region "$REGION" \
             --handler "$handler" \
             --environment "Variables={BUCKET=$BUCKET,REGION=$REGION,ISSUER=$ISSUER,AUDIENCE=$AUDIENCE}")
  if aws lambda get-function --function-name "$fn" --region "$REGION" >/dev/null 2>&1; then
    echo "  · 업데이트 ${fn}"
    aws lambda update-function-code --function-name "$fn" --zip-file "fileb://$zip" --region "$REGION" >/dev/null
    aws lambda wait function-updated --function-name "$fn" --region "$REGION"
    # 코드만이 아니라 설정(env/메모리/타임아웃/레이어)도 재반영 → 재실행 멱등성 보장.
    aws lambda update-function-configuration --function-name "$fn" "${cfg[@]}" "$@" >/dev/null
    aws lambda wait function-updated --function-name "$fn" --region "$REGION"
  else
    echo "  · 생성 ${fn}"
    aws lambda create-function --function-name "$fn" --zip-file "fileb://$zip" "${cfg[@]}" "$@" >/dev/null
    aws lambda wait function-active --function-name "$fn" --region "$REGION"
  fi
}

echo "── presign-creator ─────────────────────────────────"
package lambdas/presign-creator
deploy "$FN_PRESIGN" "index.handler" "build/presign-creator.zip" --timeout 10 --memory-size 256

echo "── album-list ──────────────────────────────────────"
package lambdas/album-list
deploy "$FN_LIST" "index.handler" "build/album-list.zip" --timeout 10 --memory-size 256

echo "── thumbnailer (sharp 레이어 부착, 메모리/타임아웃 ↑) ─"
package lambdas/thumbnailer
deploy "$FN_THUMB" "index.handler" "build/thumbnailer.zip" \
  --timeout 30 --memory-size 512 --layers "$SHARP_LAYER_ARN"

echo "✅ 람다 배포 완료. 다음: bash scripts/05_create_http_api.sh"
