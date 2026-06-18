#!/usr/bin/env bash
# =============================================================================
# 90_smoke_test.sh  —  전체 흐름 end-to-end 점검
# -----------------------------------------------------------------------------
# 로그인(토큰) → /presign(업로드URL) → S3 PUT → (이벤트→썸네일) → /albums(목록)
# 전제: auth-server 가 로컬에서 떠 있어야 함(별도 터미널에서 npm start).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./config/env.sh
source "$STATE_FILE"

AUTH_URL="${AUTH_URL:-http://localhost:3000}"   # 필요시 환경변수로 덮어쓰기
API="$API_ENDPOINT"

echo "── 1) 로그인 → JWT 발행 ────────────────────────────"
# /login 응답 예시: { "token":"eyJhbGciOi...", "sub":"james" }
TOKEN="$(curl -s -X POST "${AUTH_URL}/login" \
  -H 'content-type: application/json' \
  -d '{"username":"james","password":"demo"}' | jq -r '.token')"
[ -n "$TOKEN" ] && echo "  ✓ 토큰 수신(앞 20자): ${TOKEN:0:20}..."

echo "── 2) presigned URL 요청 ───────────────────────────"
# 응답 예시: { "uploadUrl":"https://...amazonaws.com/gallery/original/james/...jpg?X-Amz-...",
#             "keyName":"gallery/original/james/20260615_1718...jpg", "expiresIn":300 }
PRESIGN="$(curl -s -X POST "${API}/presign" \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  -d '{"contentType":"image/png"}')"
UPLOAD_URL="$(echo "$PRESIGN" | jq -r '.uploadUrl')"
KEY="$(echo "$PRESIGN" | jq -r '.keyName')"
echo "  ✓ key=${KEY}"

echo "── 3) S3 직접 업로드(PUT) ──────────────────────────"
# Python3 로 400×300 RGB 그라디언트 PNG 생성.
# base64 heredoc은 line-ending 등 환경 차이에 취약해 Python3 직접 생성으로 교체.
# 400px > THUMB_WIDTH(320px) → 실제 리사이즈 발생해 썸네일 검증 의미 있음.
# 색상: 좌상=빨강, 우상=파랑, 좌하=초록, 우하=청록 — 2색 이상 섞인 그라디언트.
python3 - << 'PYEOF'
import struct, zlib
w, h = 640, 480
def chunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
sig  = b'\x89PNG\r\n\x1a\n'
ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
rows = bytearray()
for y in range(h):
    rows.append(0)  # filter byte (None)
    for x in range(w):
        rows += bytes([
            int(255 * (1 - x / (w - 1))),   # R: 좌→우 255→0
            int(255 * (y / (h - 1))),         # G: 상→하 0→255
            int(255 * (x / (w - 1))),         # B: 좌→우 0→255
        ])
idat = chunk(b'IDAT', zlib.compress(bytes(rows), 1))
iend = chunk(b'IEND', b'')
data = sig + ihdr + idat + iend
with open('.state/sample.png', 'wb') as f:
    f.write(data)
print('  · sample.png: %dx%d px, %d bytes' % (w, h, len(data)))
PYEOF
# ⚠️ Content-Type 은 presign 시 지정한 값(image/png)과 '정확히' 일치해야 서명이 맞는다.
curl -s -X PUT "$UPLOAD_URL" -H 'content-type: image/png' --data-binary @.state/sample.png
echo "  ✓ 업로드 완료(원본). 썸네일 생성까지 잠시 대기..."
sleep 5

echo "── 4) 앨범 목록 조회 ───────────────────────────────"
# 응답 예시: { "items":[ { "key":"gallery/thumb/james/...jpg", "url":"https://...presigned-get..." } ] }
curl -s "${API}/albums" -H "authorization: Bearer ${TOKEN}" | jq '.'

echo "✅ 스모크 테스트 종료(위 목록에 thumb 항목이 보이면 성공)."
