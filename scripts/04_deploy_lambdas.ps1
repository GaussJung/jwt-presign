# =============================================================================
# 04_deploy_lambdas.ps1  —  Lambda 3종 배포 (Windows)
# 멱등성: 있으면 코드 업데이트, 없으면 생성
# =============================================================================
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot ".."); . .\config\env.ps1; . .\scripts\_load_state.ps1

function Package($dir) {
  $name = Split-Path $dir -Leaf
  Write-Host "  · 패키징 $name"
  Push-Location $dir; npm install --omit=dev 2>$null | Out-Null; Pop-Location
  New-Item -ItemType Directory -Force -Path build | Out-Null
  $zip = "build\$name.zip"; Remove-Item $zip -ErrorAction SilentlyContinue
  Compress-Archive -Path "$dir\*" -DestinationPath $zip -Force
}

function Deploy($fn, $handler, $zip, $extra) {
  $envVars = "Variables={BUCKET=$BUCKET,REGION=$REGION,ISSUER=$ISSUER,AUDIENCE=$AUDIENCE}"
  aws lambda get-function --function-name $fn --region $REGION 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "  · 업데이트 $fn"
    aws lambda update-function-code --function-name $fn --zip-file "fileb://$zip" --region $REGION | Out-Null
    aws lambda wait function-updated --function-name $fn --region $REGION
    # 코드만이 아니라 설정(env/메모리/타임아웃/레이어)도 재반영 → 재실행 멱등성 보장.
    aws lambda update-function-configuration --function-name $fn `
      --runtime nodejs20.x --role $ROLE_ARN --handler $handler --region $REGION `
      --environment $envVars @extra | Out-Null
    aws lambda wait function-updated --function-name $fn --region $REGION
  } else {
    Write-Host "  · 생성 $fn"
    aws lambda create-function --function-name $fn --zip-file "fileb://$zip" `
      --runtime nodejs20.x --role $ROLE_ARN --handler $handler --region $REGION `
      --environment $envVars @extra | Out-Null
    aws lambda wait function-active --function-name $fn --region $REGION
  }
}

Package "lambdas\presign-creator"
Deploy $FN_PRESIGN "index.handler" "build\presign-creator.zip" @("--timeout","10","--memory-size","256")
Package "lambdas\album-list"
Deploy $FN_LIST "index.handler" "build\album-list.zip" @("--timeout","10","--memory-size","256")
Package "lambdas\thumbnailer"
Deploy $FN_THUMB "index.handler" "build\thumbnailer.zip" @("--timeout","30","--memory-size","512","--layers",$SHARP_LAYER_ARN)
Write-Host "✅ 다음: scripts\05_create_http_api.ps1"
