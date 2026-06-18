#!/usr/bin/env bash
# =============================================================================
# 05_create_http_api.sh  —  API Gateway(HTTP API) + 네이티브 JWT Authorizer
# -----------------------------------------------------------------------------
# 흐름: API 생성 → JWT Authorizer 생성 → 람다 통합 → 라우트(보호) → CORS → 배포
# 핵심: Authorizer 는 코드가 아니라 'issuer + audience' 설정만으로 동작한다.
#       AWS가 https://auth-lab.nexioengine.com/.well-known/* 를 읽어 서명/iss/aud/exp 검증.
# ⚠️ TODO(라이브 검증): --jwt-configuration 의 shorthand 표기는 환경에 따라 JSON 형태가
#    더 안전하다. 강사용 EC2 사전 리허설에서 실제로 통과하는지 반드시 확인할 것.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./config/env.sh
source "$STATE_FILE"

# STATE_FILE 키 갱신 헬퍼(재실행 시 API_ID/AUTHZ_ID 등 라인 중복 누적 방지).
mkdir -p "$(dirname "$STATE_FILE")"; touch "$STATE_FILE"
put_state() {  # $1=KEY $2=VALUE
  grep -v "^$1=" "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null || true
  mv -f "$STATE_FILE.tmp" "$STATE_FILE"
  echo "$1=$2" >> "$STATE_FILE"
}

echo "── 1) HTTP API 생성/재사용(멱등) ───────────────────"
# 멱등성: 같은 이름의 API 가 이미 있으면 재사용(재실행 시 중복 생성·고아 리소스 방지). 없으면 생성.
#   ※ 과거 비멱등 실행으로 동명 API 가 여러 개 남아있다면 99_teardown 으로 정리 권장.
API_ID="$(aws apigatewayv2 get-apis --region "$REGION" \
  --query "Items[?Name=='${API_NAME}'].ApiId | [0]" --output text)"
if [ -n "$API_ID" ] && [ "$API_ID" != "None" ]; then
  echo "  기존 API 재사용: ${API_ID}"
else
  # create-api 응답 예시: { "ApiId":"abc123", "ApiEndpoint":"https://abc123.execute-api...." }
  API_ID="$(aws apigatewayv2 create-api --name "$API_NAME" --protocol-type HTTP \
    --region "$REGION" --query 'ApiId' --output text)"
  echo "  ✓ 새 API 생성: ${API_ID}"
fi
API_ENDPOINT="$(aws apigatewayv2 get-api --api-id "$API_ID" --region "$REGION" --query 'ApiEndpoint' --output text)"
put_state API_ID "$API_ID"
put_state API_ENDPOINT "$API_ENDPOINT"
echo "  ✓ ${API_ENDPOINT}"

echo "── 2) JWT Authorizer 생성/재사용(멱등) ─────────────"
# identity-source: 어디서 토큰을 읽나 → Authorization 헤더(Bearer 토큰)
AUTHZ_ID="$(aws apigatewayv2 get-authorizers --api-id "$API_ID" --region "$REGION" \
  --query "Items[?Name=='jwt-authorizer'].AuthorizerId | [0]" --output text)"
if [ -n "$AUTHZ_ID" ] && [ "$AUTHZ_ID" != "None" ]; then
  echo "  기존 Authorizer 재사용: ${AUTHZ_ID}"
else
  AUTHZ_ID="$(aws apigatewayv2 create-authorizer \
    --api-id "$API_ID" --region "$REGION" \
    --name "jwt-authorizer" --authorizer-type JWT \
    --identity-source '$request.header.Authorization' \
    --jwt-configuration "Audience=${AUDIENCE},Issuer=${ISSUER}" \
    --query 'AuthorizerId' --output text)"
  echo "  ✓ AuthorizerId=${AUTHZ_ID}"
fi
put_state AUTHZ_ID "$AUTHZ_ID"

# 람다 통합 + 라우트 생성 헬퍼
#   $1=함수명 $2='METHOD /path'
wire() {
  local fn="$1" route="$2"
  # 멱등성: 같은 route-key 가 이미 있으면 통합/라우트 재생성을 건너뛴다(중복 방지).
  local existing; existing="$(aws apigatewayv2 get-routes --api-id "$API_ID" --region "$REGION" \
    --query "Items[?RouteKey=='${route}'].RouteId | [0]" --output text)"
  if [ -n "$existing" ] && [ "$existing" != "None" ]; then
    echo "  · 라우트 이미 존재 → 건너뜀: ${route}"
    return
  fi
  local fn_arn; fn_arn="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${fn}"
  # AWS_PROXY 통합(payload v2.0): 이벤트가 requestContext.authorizer.jwt.claims 를 포함
  local int_id; int_id="$(aws apigatewayv2 create-integration \
    --api-id "$API_ID" --region "$REGION" \
    --integration-type AWS_PROXY --payload-format-version 2.0 \
    --integration-uri "$fn_arn" --query 'IntegrationId' --output text)"
  # 라우트에 JWT authorizer 부착(보호된 경로)
  aws apigatewayv2 create-route --api-id "$API_ID" --region "$REGION" \
    --route-key "$route" --target "integrations/${int_id}" \
    --authorization-type JWT --authorizer-id "$AUTHZ_ID" >/dev/null
  # API Gateway 가 이 람다를 호출할 수 있도록 권한 부여
  aws lambda add-permission --function-name "$fn" --region "$REGION" \
    --statement-id "apigw-$(echo "$route" | tr ' /' '__')" \
    --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*" >/dev/null 2>&1 || true
  echo "  ✓ ${route} → ${fn}"
}

echo "── 3) 보호 라우트 연결 ──────────────────────────────"
wire "$FN_PRESIGN" "POST /presign"
wire "$FN_LIST"    "GET /albums"

echo "── 4) CORS(브라우저에서 Authorization 헤더 호출 허용) ─"
aws apigatewayv2 update-api --api-id "$API_ID" --region "$REGION" \
  --cors-configuration \
  "AllowOrigins=*,AllowMethods=GET,POST,OPTIONS,AllowHeaders=authorization,content-type" >/dev/null

echo "── 5) 기본 스테이지(auto-deploy) ───────────────────"
aws apigatewayv2 create-stage --api-id "$API_ID" --region "$REGION" \
  --stage-name '$default' --auto-deploy >/dev/null 2>&1 || true

echo "✅ API 준비 완료. 호출 URL: ${API_ENDPOINT}"
echo "   다음: bash scripts/06_wire_s3_event.sh"
