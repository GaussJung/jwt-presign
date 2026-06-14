# =============================================================================
# config/env.ps1  —  프로젝트 환경 변수 단일 출처 (PowerShell: Windows)
# =============================================================================
# [사용법] 각 *.ps1 스크립트 상단에서  . .\config\env.ps1  (점-소스)로 읽는다.
#   주의: ' . ' 와 경로 사이에 공백. 그래야 변수들이 현재 세션에 로드된다.
# =============================================================================

# --- 고정 합의값 -------------------------------------------------------------
$Global:REGION   = "ap-northeast-2"
$Global:ISSUER   = "https://auth-lab.nexioengine.com"   # 끝 슬래시 없음
$Global:AUDIENCE = "myalbum1"
$Global:JWT_KID  = "easyalbum-jwt-key-v2"

# --- 동적 취득값 -------------------------------------------------------------
$Global:ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)

# --- 파생 리소스 이름 --------------------------------------------------------
$Global:BUCKET            = "myalbum-$ACCOUNT_ID"
$Global:LAMBDA_ROLE_NAME  = "simple-album-lambda-role"
$Global:SHARP_LAYER_NAME  = "sharp-x64"
$Global:API_NAME          = "simple-album"
$Global:FN_PRESIGN        = "simple-album-presign-creator"
$Global:FN_THUMB          = "simple-album-thumbnailer"
$Global:FN_LIST           = "simple-album-album-list"
$Global:FN_AUTHZ_BACKUP   = "simple-album-backup-authorizer"

Write-Host "[env] REGION=$REGION ACCOUNT_ID=$ACCOUNT_ID BUCKET=$BUCKET"
