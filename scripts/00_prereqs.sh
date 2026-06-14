#!/usr/bin/env bash
# =============================================================================
# 00_prereqs.sh  —  실습 시작 전 환경 점검 (mac / ubuntu / EC2)
# -----------------------------------------------------------------------------
# 무엇을: 도구 설치 여부, AWS 자격증명, 리전, 계정ID 를 확인한다.
# 왜: 뒤 단계에서 실패하기 전에 "준비 안 된 것"을 먼저 잡아야 시간 낭비가 없다.
# 실행: bash scripts/00_prereqs.sh   (프로젝트 루트에서)
# =============================================================================
set -euo pipefail   # -e 오류시 중단 / -u 미정의 변수 금지 / -o pipefail 파이프 오류 전파

# 프로젝트 루트로 이동(스크립트 위치 기준)
cd "$(dirname "$0")/.."
source ./config/env.sh

echo "── 1) 필수 도구 확인 ───────────────────────────────"
need() { command -v "$1" >/dev/null 2>&1 || { echo "  ✗ $1 없음 → $2"; MISSING=1; }; }
MISSING=0
need aws  "AWS CLI v2 설치 필요"
need node "Node.js 20.x 설치 필요"
need jq   "jq 설치 필요 (sudo apt-get install -y jq)"
need zip  "zip 설치 필요 (sudo apt-get install -y zip)"
[ "$MISSING" = "1" ] && { echo "필수 도구를 설치한 뒤 다시 실행하세요."; exit 1; }

# AWS CLI 버전 확인(v2 권장). 예시 출력: aws-cli/2.15.0 Python/3.11 ...
echo "  aws: $(aws --version 2>&1)"
echo "  node: $(node --version)"

echo "── 2) AWS 자격증명 / 계정 확인 ─────────────────────"
# get-caller-identity 가 실패하면 자격증명이 없거나 만료된 것.
#   예시 출력(JSON): {"UserId":"AID...","Account":"111122223333","Arn":"arn:aws:iam::111122223333:role/..."}
aws sts get-caller-identity >/dev/null || { echo "  ✗ AWS 자격증명 없음. EC2 인스턴스 프로파일 또는 aws configure 확인."; exit 1; }
echo "  ✓ ACCOUNT_ID = ${ACCOUNT_ID}"
echo "  ✓ REGION     = ${REGION}"
echo "  ✓ BUCKET(예정) = ${BUCKET}"

# 상태 캐시 디렉토리 준비(.gitignore 처리됨)
mkdir -p .state

echo "✅ 사전 점검 통과. 다음: bash scripts/01_create_bucket.sh"
