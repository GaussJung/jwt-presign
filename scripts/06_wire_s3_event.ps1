# =============================================================================
# 06_wire_s3_event.ps1  —  S3 이벤트 → thumbnailer (Windows)
# ⚠️ 무한루프 방지: prefix=gallery/original/ 에만 트리거. 썸네일은 gallery/thumb/ 로 출력.
# =============================================================================
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot ".."); . .\config\env.ps1; . .\scripts\_load_state.ps1

$ThumbArn = "arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:$FN_THUMB"

Write-Host "── 1) S3 → Lambda 호출 권한 ──"
aws lambda add-permission --function-name $FN_THUMB --region $REGION `
  --statement-id "s3invoke" --action "lambda:InvokeFunction" --principal s3.amazonaws.com `
  --source-arn "arn:aws:s3:::$BUCKET" --source-account $ACCOUNT_ID 2>$null | Out-Null

Write-Host "── 2) 버킷 알림 설정(original/ prefix) ──"
$notif = @"
{
  "LambdaFunctionConfigurations": [
    { "LambdaFunctionArn": "$ThumbArn",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": { "Key": { "FilterRules": [ { "Name": "prefix", "Value": "gallery/original/" } ] } } }
  ]
}
"@
$notif | Set-Content .state\notif.json
aws s3api put-bucket-notification-configuration --bucket $BUCKET --notification-configuration "file://.state/notif.json"
Write-Host "✅ 다음: scripts\90_smoke_test.ps1"
