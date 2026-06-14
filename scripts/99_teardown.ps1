# =============================================================================
# 99_teardown.ps1  —  전체 리소스 삭제 (⚠️ 파괴적, Windows)
# 안전장치: DELETE 입력해야 진행
# =============================================================================
$ErrorActionPreference = "SilentlyContinue"   # 이미 없는 리소스 삭제 시도는 무시
Set-Location (Join-Path $PSScriptRoot ".."); . .\config\env.ps1; . .\scripts\_load_state.ps1

Write-Host "⚠️  삭제 대상: 버킷 $BUCKET / API $API_ID / Lambda 3종+백업 / 역할 $LAMBDA_ROLE_NAME"
$confirm = Read-Host "정말 삭제하려면 DELETE 입력"
if ($confirm -ne "DELETE") { Write-Host "취소됨."; exit 0 }

if ($API_ID) { aws apigatewayv2 delete-api --api-id $API_ID --region $REGION }
foreach ($fn in @($FN_PRESIGN,$FN_THUMB,$FN_LIST,$FN_AUTHZ_BACKUP)) {
  aws lambda delete-function --function-name $fn --region $REGION
}
aws s3 rm "s3://$BUCKET" --recursive
aws s3api delete-bucket --bucket $BUCKET --region $REGION
aws iam delete-role-policy --role-name $LAMBDA_ROLE_NAME --policy-name "s3-gallery-rw"
aws iam detach-role-policy --role-name $LAMBDA_ROLE_NAME --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
aws iam delete-role --role-name $LAMBDA_ROLE_NAME
Write-Host "✅ 정리 완료(레이어 버전은 콘솔에서 수동 확인 권장)."
