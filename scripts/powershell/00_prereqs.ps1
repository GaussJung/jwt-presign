# =============================================================================
# 00_prereqs.ps1  —  실습 시작 전 환경 점검 (Windows / PowerShell)
# 실행:  powershell -ExecutionPolicy Bypass -File scripts\00_prereqs.ps1
# =============================================================================
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..\..")   # 프로젝트 루트로 이동
. .\config\env.ps1

Write-Host "── 1) 필수 도구 확인 ───────────────────────────────"
function Need($cmd, $hint) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { Write-Host "  ✗ $cmd 없음 → $hint"; $script:Missing = $true }
}
$script:Missing = $false
Need aws  "AWS CLI v2 설치 필요"
Need node "Node.js 24.x 설치 필요"
if ($script:Missing) { throw "필수 도구 설치 후 다시 실행하세요." }
Write-Host ("  aws: " + (aws --version)); Write-Host ("  node: " + (node --version))

Write-Host "── 2) AWS 자격증명 / 계정 확인 ─────────────────────"
# get-caller-identity 실패 시 자격증명 없음/만료
aws sts get-caller-identity | Out-Null
# 네이티브 명령은 실패해도 throw 하지 않으므로 종료코드로 친절히 안내(=.sh의 set -e 보완과 동일 의도).
if ($LASTEXITCODE -ne 0) { throw "AWS 자격증명 없음/만료. 'aws configure' 또는 EC2 인스턴스 프로파일을 확인하세요." }
Write-Host "  ✓ ACCOUNT_ID = $ACCOUNT_ID"
Write-Host "  ✓ REGION     = $REGION"
Write-Host "  ✓ BUCKET(예정) = $BUCKET"

New-Item -ItemType Directory -Force -Path .state | Out-Null
Write-Host "✅ 사전 점검 통과. 다음: scripts\01_create_bucket.ps1"
