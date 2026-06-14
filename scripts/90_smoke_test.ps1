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
  -Body (@{ contentType="image/jpeg" } | ConvertTo-Json)
Write-Host "  ✓ key=$($presign.keyName)"

Write-Host "── 3) S3 직접 업로드(PUT) ──"
# Content-Type 은 presign 시 값과 일치해야 함
"test-image" | Set-Content .state\sample.jpg
Invoke-RestMethod -Method Put -Uri $presign.uploadUrl -ContentType 'image/jpeg' -InFile .state\sample.jpg
Write-Host "  ✓ 업로드 완료. 썸네일 대기..."; Start-Sleep -Seconds 5

Write-Host "── 4) 앨범 목록 ──"
Invoke-RestMethod -Uri "$API_ENDPOINT/albums" -Headers @{ Authorization = "Bearer $Token" } | ConvertTo-Json -Depth 5
Write-Host "✅ thumb 항목이 보이면 성공."
