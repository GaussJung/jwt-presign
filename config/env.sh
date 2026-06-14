#!/usr/bin/env bash
# =============================================================================
# config/env.sh  —  프로젝트 환경 변수 단일 출처 (bash: mac / ubuntu / EC2)
# =============================================================================
# [사용법] 모든 스크립트가 맨 위에서 'source ./config/env.sh' 로 읽어들인다.
#
# [원칙]
#   - 실제 계정ID/시크릿은 여기에 '하드코딩하지 않는다'. 런타임에 동적으로 얻는다.
#   - 공개 GitHub 리포에 올라가는 파일이므로 민감정보 금지.
# =============================================================================

# --- 고정 합의값 (전 수강생 공통) ---------------------------------------------
export REGION="ap-northeast-2"                              # 서울 리전
export ISSUER="https://auth-lab.nexioengine.com"            # JWT 발행자(중앙). 끝 슬래시 없음!
export AUDIENCE="myalbum1"                                  # JWT aud
export JWT_KID="easyalbum-jwt-key-v2"                       # JWKS와 동일해야 함

# --- 동적 취득값 (실행 시점 계정에 맞춰 자동 결정) ----------------------------
# aws sts get-caller-identity → 현재 자격증명의 12자리 계정ID
#   예시 출력: { "Account": "111122223333", "Arn": "arn:aws:iam::111122223333:user/..." }
export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# --- 위 값으로 파생되는 리소스 이름 ------------------------------------------
export BUCKET="myalbum-${ACCOUNT_ID}"                       # S3 버킷명(계정별 유일)
export LAMBDA_ROLE_NAME="simple-album-lambda-role"
export SHARP_LAYER_NAME="sharp-x64"
export API_NAME="simple-album"

# 람다 함수 이름
export FN_PRESIGN="simple-album-presign-creator"
export FN_THUMB="simple-album-thumbnailer"
export FN_LIST="simple-album-album-list"
export FN_AUTHZ_BACKUP="simple-album-backup-authorizer"

# 스크립트가 생성한 리소스 ID를 저장/공유하는 로컬 캐시 파일(.gitignore 처리됨)
export STATE_FILE=".state/resources.env"

echo "[env] REGION=${REGION} ACCOUNT_ID=${ACCOUNT_ID} BUCKET=${BUCKET}"
