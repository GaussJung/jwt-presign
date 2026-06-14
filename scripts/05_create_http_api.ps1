# =============================================================================
# 05_create_http_api.ps1  —  HTTP API + 네이티브 JWT Authorizer (Windows)
# ⚠️ TODO(라이브 검증): --jwt-configuration shorthand 가 환경에 따라 까다로울 수 있다.
#    강사용 리허설에서 정상 토큰 통과 / 틀린 aud 401 을 반드시 확인할 것.
# =============================================================================
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot ".."); . .\config\env.ps1; . .\scripts\_load_state.ps1

Write-Host "── 1) HTTP API 생성 ──"
$ApiId = (aws apigatewayv2 create-api --name $API_NAME --protocol-type HTTP --region $REGION --query 'ApiId' --output text)
$ApiEndpoint = (aws apigatewayv2 get-api --api-id $ApiId --region $REGION --query 'ApiEndpoint' --output text)
"API_ID=$ApiId" | Add-Content .state\resources.env
"API_ENDPOINT=$ApiEndpoint" | Add-Content .state\resources.env
Write-Host "  ✓ $ApiEndpoint"

Write-Host "── 2) JWT Authorizer 생성 ──"
$AuthzId = (aws apigatewayv2 create-authorizer --api-id $ApiId --region $REGION `
  --name "jwt-authorizer" --authorizer-type JWT `
  --identity-source '$request.header.Authorization' `
  --jwt-configuration "Audience=$AUDIENCE,Issuer=$ISSUER" `
  --query 'AuthorizerId' --output text)
Write-Host "  ✓ AuthorizerId=$AuthzId"

function Wire($fn, $route) {
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
