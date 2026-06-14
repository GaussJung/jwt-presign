# =============================================================================
# 01_create_bucket.ps1  —  S3 버킷 생성 + 퍼블릭 차단 + CORS (Windows)
# 멱등성: 이미 있으면 생성 건너뜀
# =============================================================================
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot ".."); . .\config\env.ps1

Write-Host "── 버킷 $BUCKET 확인/생성 ──"
# head-bucket: 성공 시 존재. PowerShell은 비0 종료코드를 예외로 보지 않으므로 $LASTEXITCODE 확인.
aws s3api head-bucket --bucket $BUCKET 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Host "  이미 존재 → 건너뜀"
} else {
  # ap-northeast-2 는 LocationConstraint 필수
  aws s3api create-bucket --bucket $BUCKET --region $REGION `
    --create-bucket-configuration "LocationConstraint=$REGION"
  Write-Host "  ✓ 생성됨"
}

Write-Host "── 퍼블릭 액세스 차단 ──"
aws s3api put-public-access-block --bucket $BUCKET `
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

Write-Host "── CORS 적용 ──"
aws s3api put-bucket-cors --bucket $BUCKET --cors-configuration "file://config/s3-cors.json"
Write-Host "✅ 버킷 준비 완료. 다음: scripts\02_create_iam_roles.ps1"
