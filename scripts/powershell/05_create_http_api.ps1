# =============================================================================
# 05_create_http_api.ps1  —  HTTP API + 네이티브 JWT Authorizer (Windows)
# ⚠️ TODO(라이브 검증): --jwt-configuration shorthand 가 환경에 따라 까다로울 수 있다.
#    강사용 리허설에서 정상 토큰 통과 / 틀린 aud 401 을 반드시 확인할 것.
# =============================================================================
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..\.."); . .\config\env.ps1; . .\scripts\powershell\_load_state.ps1

# resources.env 키 업서트 헬퍼(재실행 시 API_ID/AUTHZ_ID 등 라인 중복 누적 방지).
function Put-State($key, $val) {
  New-Item -ItemType Directory -Force -Path .state | Out-Null
  $f = ".state\resources.env"
  if (Test-Path $f) { (Get-Content $f) | Where-Object { $_ -notmatch "^$key=" } | Set-Content $f }
  Add-Content $f "$key=$val"
}

Write-Host "── 1) HTTP API 생성/재사용(멱등) ──"
# 같은 이름 API 가 있으면 재사용(재실행 시 중복 생성·고아 리소스 방지). 없으면 생성.
#   ※ 과거 비멱등 실행으로 동명 API 가 여러 개라면 99_teardown 으로 정리 권장.
$ApiId = (aws apigatewayv2 get-apis --region $REGION --query "Items[?Name=='$API_NAME'].ApiId | [0]" --output text)
if ($ApiId -and $ApiId -ne "None") {
  Write-Host "  기존 API 재사용: $ApiId"
} else {
  $ApiId = (aws apigatewayv2 create-api --name $API_NAME --protocol-type HTTP --region $REGION --query 'ApiId' --output text)
  Write-Host "  ✓ 새 API 생성: $ApiId"
}
$ApiEndpoint = (aws apigatewayv2 get-api --api-id $ApiId --region $REGION --query 'ApiEndpoint' --output text)
Put-State "API_ID" $ApiId
Put-State "API_ENDPOINT" $ApiEndpoint
Write-Host "  ✓ $ApiEndpoint"

Write-Host "── 2) JWT Authorizer 생성/재사용(멱등) ──"
$AuthzId = (aws apigatewayv2 get-authorizers --api-id $ApiId --region $REGION --query "Items[?Name=='jwt-authorizer'].AuthorizerId | [0]" --output text)
if ($AuthzId -and $AuthzId -ne "None") {
  Write-Host "  기존 Authorizer 재사용: $AuthzId"
} else {
  $AuthzId = (aws apigatewayv2 create-authorizer --api-id $ApiId --region $REGION `
    --name "jwt-authorizer" --authorizer-type JWT `
    --identity-source '$request.header.Authorization' `
    --jwt-configuration "Audience=$AUDIENCE,Issuer=$ISSUER" `
    --query 'AuthorizerId' --output text)
  Write-Host "  ✓ AuthorizerId=$AuthzId"
}
Put-State "AUTHZ_ID" $AuthzId

function Wire($fn, $route) {
  # 멱등성: 같은 route-key 가 이미 있으면 통합/라우트 재생성을 건너뛴다(중복 방지).
  $existing = (aws apigatewayv2 get-routes --api-id $ApiId --region $REGION --query "Items[?RouteKey=='$route'].RouteId | [0]" --output text)
  if ($existing -and $existing -ne "None") { Write-Host "  · 라우트 이미 존재 → 건너뜀: $route"; return }
  $fnArn = "arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:$fn"
  $intId = (aws apigatewayv2 create-integration --api-id $ApiId --region $REGION `
    --integration-type AWS_PROXY --payload-format-version 2.0 --integration-uri $fnArn `
    --query 'IntegrationId' --output text)
  aws apigatewayv2 create-route --api-id $ApiId --region $REGION `
    --route-key $route --target "integrations/$intId" `
    --authorization-type JWT --authorizer-id $AuthzId | Out-Null
  $sid = "apigw-" + ($route -replace '[ /]','_')
  aws lambda add-permission --function-name $fn --region $REGION --statement-id $sid `
    --action lambda:InvokeFunction --principal apigateway.amazonaws.com `
    --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:$ApiId/*/*" 2>$null | Out-Null
  Write-Host "  ✓ $route → $fn"
}
Write-Host "── 3) 보호 라우트 ──"
Wire $FN_PRESIGN "POST /presign"
Wire $FN_LIST    "GET /albums"

Write-Host "── 4) CORS ──"
aws apigatewayv2 update-api --api-id $ApiId --region $REGION `
  --cors-configuration "AllowOrigins=*,AllowMethods=GET,POST,OPTIONS,AllowHeaders=authorization,content-type" | Out-Null

Write-Host "── 5) 기본 스테이지(auto-deploy) ──"
aws apigatewayv2 create-stage --api-id $ApiId --region $REGION --stage-name '$default' --auto-deploy 2>$null | Out-Null
Write-Host "✅ API: $ApiEndpoint   다음: scripts\06_wire_s3_event.ps1"
