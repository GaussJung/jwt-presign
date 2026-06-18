// =============================================================================
// presign-creator / index.mjs
// -----------------------------------------------------------------------------
// 역할: 인증된 사용자가 S3에 '직접' 업로드할 수 있는 presigned PUT URL을 만든다.
// 왜 presigned URL인가:
//   - 이미지 바이너리가 Lambda/API Gateway를 통과하지 않는다(비용·용량·지연 절감).
//   - 클라이언트가 S3로 바로 PUT 한다. 서버는 '서명된 임시 URL'만 발급.
//
// 트리거: API Gateway HTTP API (POST /presign), 네이티브 JWT Authorizer 통과 후 호출.
//
// [입력] HTTP API payload v2.0 이벤트(요약). 검증된 JWT 클레임이 들어있다:
//   {
//     "requestContext": {
//       "authorizer": { "jwt": { "claims": {
//         "sub": "james", "aud": "myalbum1",
//         "iss": "https://auth-lab.nexioengine.com", "role": "member"
//       } } }
//     },
//     "body": "{\"contentType\":\"image/jpeg\"}"
//   }
//
// [출력] 200 JSON:
//   { "uploadUrl": "https://<bucket>.s3...amazonaws.com/gallery/original/james/20260615_1718...jpg?X-Amz-...",
//     "keyName":   "gallery/original/james/20260615_1718....jpg",
//     "expiresIn": 300 }
// =============================================================================
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
// 참고: nodejs20.x 런타임에는 AWS SDK v3가 기본 포함되어 있어 별도 번들 없이 import 가능.

const REGION = process.env.REGION;
const BUCKET = process.env.BUCKET;
const EXPIRES_IN = 300; // presigned URL 유효시간(초). 짧게 유지하는 것이 안전.

const s3 = new S3Client({ region: REGION });

// content-type → 확장자 매핑(허용 목록). 허용 외 타입은 거부한다.
const EXT_BY_TYPE = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" };

export const handler = async (event) => {
  try {
    // 1) 검증된 JWT 클레임에서 sub 취득 — 절대 클라이언트 body의 값을 신뢰하지 않는다.
    const claims = event?.requestContext?.authorizer?.jwt?.claims ?? {};
    const sub = claims.sub;
    if (!sub) return json(401, { message: "no subject in token" });

    // 2) 업로드할 파일 타입 확인
    const body = event.body ? JSON.parse(event.body) : {};
    const contentType = body.contentType ?? "image/jpeg";
    const ext = EXT_BY_TYPE[contentType];
    if (!ext) return json(400, { message: `unsupported contentType: ${contentType}` });

    // 3) S3 key 생성 — 규칙: gallery/original/{sub}/{yyyyMMdd}_{ms}.{ext}
    //    예: gallery/original/james/20260615_1718456789012.jpg
    //    날짜는 UTC 기준으로 생성(Lambda 기본 TZ=UTC, 로컬TZ 의존 제거).
    const now = new Date();
    const yyyyMMdd =
      now.getUTCFullYear().toString() +
      String(now.getUTCMonth() + 1).padStart(2, "0") +
      String(now.getUTCDate()).padStart(2, "0");
    const keyName = `gallery/original/${sub}/${yyyyMMdd}_${now.getTime()}.${ext}`;

    // 4) presigned PUT URL 발급
    //    ⚠️ 여기서 ContentType을 지정하면, 클라이언트 PUT 시 동일 Content-Type 헤더를 보내야
    //       서명이 일치한다(불일치 시 SignatureDoesNotMatch).
    const cmd = new PutObjectCommand({ Bucket: BUCKET, Key: keyName, ContentType: contentType });
    const uploadUrl = await getSignedUrl(s3, cmd, { expiresIn: EXPIRES_IN });

    return json(200, { uploadUrl, keyName, expiresIn: EXPIRES_IN });
  } catch (err) {
    console.error("presign error:", err);
    return json(500, { message: "failed to create presigned url" });
  }
};

// HTTP API 응답 헬퍼
function json(statusCode, obj) {
  return { statusCode, headers: { "content-type": "application/json" }, body: JSON.stringify(obj) };
}
