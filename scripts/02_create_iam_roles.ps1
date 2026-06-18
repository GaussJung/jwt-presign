# =============================================================================
# 02_create_iam_roles.ps1  —  Lambda 실행 역할 + 최소권한 정책 (Windows)
# =============================================================================
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot ".."); . .\config\env.ps1

# .state 자기완결 보장 + resources.env 키 업서트 헬퍼(절단/중복 라인 방지).
function Put-State($key, $val) {
  New-Item -ItemType Directory -Force -Path .state | Out-Null
  $f = ".state\resources.env"
  if (Test-Path $f) { (Get-Content $f) | Where-Object { $_ -notmatch "^$key=" } | Set-Content $f }
  Add-Content $f "$key=$val"
}

Write-Host "── 역할 $LAMBDA_ROLE_NAME 생성/확인 ──"
aws iam get-role --role-name $LAMBDA_ROLE_NAME 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  aws iam create-role --role-name $LAMBDA_ROLE_NAME `
    --assume-role-policy-document "file://config/lambda-trust-policy.json" | Out-Null
  Write-Host "  ✓ 역할 생성"
} else { Write-Host "  이미 존재 → 건너뜀" }

Write-Host "── 기본 로깅 권한 부착 ──"
aws iam attach-role-policy --role-name $LAMBDA_ROLE_NAME `
  --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

Write-Host "── S3 인라인 권한(__BUCKET__ 치환) ──"
(Get-Content config\lambda-s3-policy.json) -replace '__BUCKET__', $BUCKET | Set-Content .state\lambda-s3-policy.json
aws iam put-role-policy --role-name $LAMBDA_ROLE_NAME `
  --policy-name "s3-gallery-rw" --policy-document "file://.state/lambda-s3-policy.json"

$RoleArn = (aws iam get-role --role-name $LAMBDA_ROLE_NAME --query 'Role.Arn' --output text)
Put-State "ROLE_ARN" $RoleArn
Write-Host "  ✓ ROLE_ARN=$RoleArn"
Write-Host "  (IAM 전파 대기 10초)"; Start-Sleep -Seconds 10
Write-Host "✅ 역할 준비 완료. 다음: scripts\03_publish_layer.ps1"
