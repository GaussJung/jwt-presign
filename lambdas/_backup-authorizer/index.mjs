// =============================================================================
// _backup-authorizer / index.mjs   (비상용 — 기본 경로 아님)
// -----------------------------------------------------------------------------
// 언제 쓰나: 중앙 issuer(auth-lab) 문제로 '네이티브' JWT Authorizer가 동작하지 않을 때의
//            escape hatch. 평소에는 사용하지 않는다(05 스크립트는 네이티브를 연결한다).
//
// 동작: HTTP API Lambda Authorizer(payload v2.0, simple response)로서
//       Authorization 헤더의 RS256 JWT를 'jose'로 직접 검증한다.
//       - JWKS는 issuer의 /.well-known/jwks.json 에서 가져온다.
//       - iss/aud/exp/서명 검증 후 { isAuthorized: true, context:{ ...claims } } 반환.
//
// [입력] (HTTP API authorizer payload v2.0 요약):
//   { "headers": { "authorization": "Bearer eyJ..." },
//     "routeArn": "arn:aws:execute-api:...:.../$default/POST/presign" }
//
// [출력] simple response:
//   { "isAuthorized": true,  "context": { "sub":"james", "role":"member" } }   // 허용
//   { "isAuthorized": false }                                                   // 거부
//
// ※ 의존성 jose 는 런타임에 없으므로 이 함수는 zip 에 node_modules(jose)를 포함해야 한다.
// =============================================================================
import { createRemoteJWKSet, jwtVerify } from "jose";

const ISSUER = process.env.ISSUER;       // https://auth-lab.nexioengine.com
const AUDIENCE = process.env.AUDIENCE;   // myalbum1

// JWKS를 원격에서 가져와 캐시(콜드스타트 외에는 재사용).
const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks.json`));

export const handler = async (event) => {
  try {
    // 'Bearer eyJ...' 에서 토큰만 추출
    const auth = event.headers?.authorization ?? event.headers?.Authorization ?? "";
    const token = auth.startsWith("Bearer ") ? auth.slice(7) : auth;
    if (!token) return { isAuthorized: false };

    // 서명 + iss + aud + exp 검증
    const { payload } = await jwtVerify(token, JWKS, { issuer: ISSUER, audience: AUDIENCE });

    // 통과: 다운스트림 람다가 쓸 수 있도록 클레임을 context로 전달
    return { isAuthorized: true, context: { sub: payload.sub, role: payload.role ?? "member" } };
  } catch (err) {
    console.warn("authz reject:", err.code ?? err.message);
    return { isAuthorized: false };
  }
};
