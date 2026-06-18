# =============================================================================
# 90_smoke_test.ps1  —  end-to-end 점검 (Windows)
# 전제: auth-server 가 떠 있어야 함(별도 창에서 npm start). 기본 http://localhost:3000
# =============================================================================
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot ".."); . .\config\env.ps1; . .\scripts\_load_state.ps1
$AuthUrl = if ($env:AUTH_URL) { $env:AUTH_URL } else { "http://localhost:3000" }

Write-Host "── 1) 로그인 → JWT ──"
$login = Invoke-RestMethod -Method Post -Uri "$AuthUrl/login" -ContentType 'application/json' `
  -Body (@{ username="james"; password="demo" } | ConvertTo-Json)
$Token = $login.token
Write-Host ("  ✓ 토큰 앞 20자: " + $Token.Substring(0,20) + "...")

Write-Host "── 2) presigned URL ──"
$presign = Invoke-RestMethod -Method Post -Uri "$API_ENDPOINT/presign" `
  -Headers @{ Authorization = "Bearer $Token" } -ContentType 'application/json' `
  -Body (@{ contentType="image/png" } | ConvertTo-Json)
Write-Host "  ✓ key=$($presign.keyName)"

Write-Host "── 3) S3 직접 업로드(PUT) ──"
# ⚠️ Content-Type 은 presign 값(image/png)과 일치해야 서명이 맞는다.
# ⚠️ thumbnailer(sharp)가 디코드 가능한 '진짜' 이미지여야 썸네일이 생성된다 → 1x1 PNG 사용.
$png = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')
[IO.File]::WriteAllBytes((Join-Path (Get-Location) '.state\sample.png'), $png)
Invoke-RestMethod -Method Put -Uri $presign.uploadUrl -ContentType 'image/png' -InFile .state\sample.png
Write-Host "  ✓ 업로드 완료. 썸네일 대기..."; Start-Sleep -Seconds 5

Write-Host "── 4) 앨범 목록 ──"
Invoke-RestMethod -Uri "$API_ENDPOINT/albums" -Headers @{ Authorization = "Bearer $Token" } | ConvertTo-Json -Depth 5
Write-Host "✅ thumb 항목이 보이면 성공."
