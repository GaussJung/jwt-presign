# =============================================================================
# 03_publish_layer.ps1  —  sharp 레이어 빌드 & 게시 (Windows)
# ⚠️ Windows에서 빌드하므로 Lambda(linux-x64) 타깃 바이너리를 강제로 받아야 한다:
#    npm install --os=linux --cpu=x64 sharp
# =============================================================================
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot ".."); . .\config\env.ps1

# resources.env 키 업서트 헬퍼(재실행 시 SHARP_LAYER_ARN 라인 중복 누적 방지).
function Put-State($key, $val) {
  New-Item -ItemType Directory -Force -Path .state | Out-Null
  $f = ".state\resources.env"
  if (Test-Path $f) { (Get-Content $f) | Where-Object { $_ -notmatch "^$key=" } | Set-Content $f }
  Add-Content $f "$key=$val"
}

Write-Host "── sharp 빌드(nodejs/node_modules 구조, linux-x64 타깃) ──"
Remove-Item -Recurse -Force build\layer -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path build\layer\nodejs | Out-Null
Push-Location build\layer\nodejs
npm init -y | Out-Null
npm install --os=linux --cpu=x64 sharp | Out-Null   # ← Windows 빌드 핵심 플래그
Pop-Location

Write-Host "── zip 패키징 ──"
Compress-Archive -Path build\layer\nodejs -DestinationPath build\sharp-layer.zip -Force

Write-Host "── 레이어 게시 ──"
$LayerArn = (aws lambda publish-layer-version --layer-name $SHARP_LAYER_NAME `
  --zip-file "fileb://build/sharp-layer.zip" `
  --compatible-runtimes nodejs24.x --compatible-architectures x86_64 `
  --region $REGION --query 'LayerVersionArn' --output text)
Put-State "SHARP_LAYER_ARN" $LayerArn
Write-Host "  ✓ $LayerArn"
Write-Host "✅ 다음: scripts\04_deploy_lambdas.ps1"
