#!/usr/bin/env bash
# =============================================================================
# 03_publish_layer.sh  —  sharp(이미지 리사이즈) Lambda 레이어 빌드 & 게시
# -----------------------------------------------------------------------------
# 왜 레이어인가: sharp 는 네이티브 바이너리라 함수 코드와 분리해 레이어로 두면
#               배포가 가볍고 재사용이 쉽다.
# 왜 EC2에서 빌드하나: 학생 EC2(Ubuntu x86_64, glibc)는 Lambda(AL2023)와 같은
#               linux-x64 타깃이라, 여기서 받은 sharp 바이너리가 Lambda에서 그대로 동작.
#               (Windows/mac 작성 박스에서 빌드한다면 04번 주석의 --os/--cpu 플래그 필요)
# 레이어 디렉토리 규칙(중요): Node 레이어는 'nodejs/node_modules' 구조여야 인식된다.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./config/env.sh

# STATE_FILE 키 갱신 헬퍼(재실행 시 SHARP_LAYER_ARN 라인 중복 누적 방지).
mkdir -p "$(dirname "$STATE_FILE")"; touch "$STATE_FILE"
put_state() {  # $1=KEY $2=VALUE
  grep -v "^$1=" "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null || true
  mv -f "$STATE_FILE.tmp" "$STATE_FILE"
  echo "$1=$2" >> "$STATE_FILE"
}

echo "── sharp 빌드(nodejs/node_modules 구조) ─────────────"
rm -rf build/layer && mkdir -p build/layer/nodejs
( cd build/layer/nodejs && npm init -y >/dev/null && npm install sharp >/dev/null )

echo "── zip 패키징 ───────────────────────────────────────"
( cd build/layer && zip -qr ../sharp-layer.zip nodejs )

echo "── 레이어 게시 ──────────────────────────────────────"
# publish-layer-version 응답 예시(JSON):
#   { "LayerVersionArn":"arn:aws:lambda:ap-northeast-2:1111...:layer:sharp-x64:1", "Version":1, ... }
LAYER_ARN="$(aws lambda publish-layer-version \
  --layer-name "$SHARP_LAYER_NAME" \
  --zip-file "fileb://build/sharp-layer.zip" \
  --compatible-runtimes nodejs24.x \
  --compatible-architectures x86_64 \
  --region "$REGION" \
  --query 'LayerVersionArn' --output text)"

put_state SHARP_LAYER_ARN "$LAYER_ARN"
echo "  ✓ ${LAYER_ARN}"
echo "✅ 레이어 게시 완료. 다음: bash scripts/04_deploy_lambdas.sh"
