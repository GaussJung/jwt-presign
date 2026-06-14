// =============================================================================
// src/jwt.js  —  RS256 JWT 발행 (개인키 서명)
// -----------------------------------------------------------------------------
// 개인키(private.pem)는 폐쇄 커뮤니티로 받아 auth-server/keys/ 에 직접 둔다(리포에 없음).
// 발행 토큰은 중앙 auth-lab 의 공개키(JWKS)로 검증된다 → kid/iss/aud 가 핵심.
// =============================================================================
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { importPKCS8, SignJWT } from "jose";

const __dirname = dirname(fileURLToPath(import.meta.url));

// --- 합의값(중앙 issuer와 반드시 일치) ---
const ISSUER = "https://auth-lab.nexioengine.com"; // 끝 슬래시 없음
const AUDIENCE = "myalbum1";
const KID = "easyalbum-jwt-key-v2";                // JWKS의 kid와 동일

// 개인키 로드(없으면 친절히 안내하고 종료)
let privateKey;
try {
  const pem = readFileSync(join(__dirname, "..", "keys", "private.pem"), "utf8");
  privateKey = await importPKCS8(pem, "RS256");
} catch {
  console.error("[jwt] keys/private.pem 이 없습니다. 폐쇄 커뮤니티에서 받은 개인키를 auth-server/keys/ 에 두세요.");
  process.exit(1);
}

// JWT 발행
//   예시 payload: { role, iss, sub, aud, iat, exp }
export async function issueToken(sub, role = "member") {
  return new SignJWT({ role })
    .setProtectedHeader({ alg: "RS256", kid: KID }) // ← kid 필수(검증 측이 키를 찾는 단서)
    .setIssuer(ISSUER)
    .setSubject(sub)
    .setAudience(AUDIENCE)
    .setIssuedAt()
    .setExpirationTime("3h") // 수업 길이보다 길게(중간 만료 방지). 운영에선 짧게.
    .sign(privateKey);
}
