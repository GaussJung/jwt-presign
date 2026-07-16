#!/usr/bin/env bash
# =============================================================================
# tf_00_install.sh — 배포서버 EC2(Ubuntu 24.04)에 Terraform 설치
# -----------------------------------------------------------------------------
# 멱등성: 이미 설치되어 있으면 버전만 출력하고 종료.
# 설치 방식: HashiCorp 공식 apt 저장소(서명키 검증) — 스냅/수동 바이너리보다
#            업데이트 관리가 쉽다.
# =============================================================================
set -euo pipefail

if command -v terraform >/dev/null 2>&1; then
  echo "이미 설치됨 → 건너뜀"
  terraform version
  exit 0
fi

echo "── HashiCorp apt 저장소 등록 ────────────────────────"
sudo apt-get update -y
sudo apt-get install -y gnupg curl lsb-release

# 서명키 등록(--batch --yes: 재실행 시 기존 키 파일 덮어쓰기 허용 = 멱등)
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor --batch --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

echo "── Terraform 설치 ───────────────────────────────────"
sudo apt-get update -y
sudo apt-get install -y terraform

terraform version
echo "✅ 설치 완료. 다음: bash terraform/tf_10_apply.sh"
