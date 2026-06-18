#!/usr/bin/env bash
# =============================================================================
# operation/startup.sh  —  auth-server 백그라운드 기동
# -----------------------------------------------------------------------------
# 동작:
#   1) 이미 떠 있으면(PID 살아있음) 중복 기동 없이 안내 후 종료
#   2) config/env.sh + .state/resources.env 에서 API_ENDPOINT 로드
#   3) nohup 으로 node를 직접 실행 → PID 파일 기록 + 로그 출력
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."          # 프로젝트 루트 기준

source ./config/env.sh
# STATE_FILE(.state/resources.env)에 API_ENDPOINT가 기록돼 있으면 로드
[ -f "${STATE_FILE:-}" ] && source "$STATE_FILE"

RUN_DIR="operation/.run"
PID_FILE="${RUN_DIR}/auth-server.pid"
LOG_FILE="${RUN_DIR}/auth-server.log"

mkdir -p "$RUN_DIR"

# ── 중복 기동 방지 ──────────────────────────────────────────────────────────
if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE")"
  if kill -0 "$PID" 2>/dev/null; then
    echo "  ℹ 이미 실행 중 (PID ${PID}). 중복 기동 생략."
    echo "    로그: tail -f ${LOG_FILE}"
    exit 0
  fi
  # PID 파일은 있지만 프로세스가 없는 경우(비정상 종료 잔재) → 정리 후 재기동
  echo "  · 이전 PID(${PID}) 없음 — PID 파일 정리 후 재기동"
  rm -f "$PID_FILE"
fi

# ── API_ENDPOINT 필수 확인 ───────────────────────────────────────────────────
if [ -z "${API_ENDPOINT:-}" ]; then
  echo "  ✗ API_ENDPOINT 가 비어 있습니다."
  echo "    bash scripts/05_create_http_api.sh 실행 후 .state/resources.env 에 기록되거나,"
  echo "    API_ENDPOINT=https://... bash operation/startup.sh 로 직접 주입하세요."
  exit 1
fi

# ── auth-server 기동 ─────────────────────────────────────────────────────────
# node 직접 실행: npm 경유 없이 PID가 실제 node 프로세스를 가리키게 한다.
# server.js 는 import.meta.url 기반 경로 계산 → 어느 디렉토리에서 실행해도 안전.
nohup env API_ENDPOINT="$API_ENDPOINT" node auth-server/src/server.js \
  > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

echo "  ✓ auth-server 기동 완료"
echo "    PID : $(cat "$PID_FILE")"
echo "    로그: tail -f ${LOG_FILE}"
echo "    주소: http://<EC2-PUBLIC-IP>:3000"
