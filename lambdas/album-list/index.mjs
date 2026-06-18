// =============================================================================
// album-list / index.mjs
// -----------------------------------------------------------------------------
// 역할: 로그인한 사용자 본인의 썸네일 목록을 돌려준다. 비공개 버킷이므로,
//       각 객체에 대해 'presigned GET URL'을 만들어 브라우저가 직접 볼 수 있게 한다.
// 트리거: API Gateway (GET /albums), JWT Authorizer 통과 후 호출.
//
// [입력] 이벤트의 requestContext.authorizer.jwt.claims.sub 로 사용자 식별.
// [출력] 200 JSON:
//   { "items": [
//       { "key": "gallery/thumb/james/20260615_....jpg",
//         "url": "https://<bucket>.s3...amazonaws.com/...?X-Amz-... (presigned GET)" }
//   ] }
// =============================================================================
import { S3Client, ListObjectsV2Command, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const REGION = process.env.REGION;
const BUCKET = process.env.BUCKET;
const VIEW_EXPIRES = 300;

const s3 = new S3Client({ region: REGION });

export const handler = async (event) => {
  try {
    const sub = event?.requestContext?.authorizer?.jwt?.claims?.sub;
    if (!sub) return json(401, { message: "no subject in token" });

    // 본인 썸네일 prefix 만 조회 — 사용자 간 데이터 격리.
    const prefix = `gallery/thumb/${sub}/`;

    // ListObjectsV2: prefix 하위 객체 키 목록. 응답은 한 번에 최대 1000개이므로,
    // IsTruncated 면 NextContinuationToken 으로 끝까지 이어 받는다(대량 대비).
    const list = async (pfx) => {
      const contents = [];
      let token;
      do {
        const listed = await s3.send(new ListObjectsV2Command({
          Bucket: BUCKET, Prefix: pfx, ContinuationToken: token,
        }));
        contents.push(...(listed.Contents ?? []));
        token = listed.IsTruncated ? listed.NextContinuationToken : undefined;
      } while (token);
      return contents;
    };

    // 썸네일·원본을 병렬로 목록 조회.
    const [thumbs, origs] = await Promise.all([
      list(`gallery/thumb/${sub}/`),
      list(`gallery/original/${sub}/`),
    ]);

    // 원본 파일명 줄기(확장자 제거) → S3 키 맵. 썸네일과 1:1 매핑에 사용.
    // 예: "gallery/original/james/20260618_1718....png" → "20260618_1718..." → key
    const stem = (key) => key.split("/").pop().replace(/\.[^.]+$/, "");
    const origMap = new Map(origs.map((o) => [stem(o.Key), o.Key]));

    // 각 썸네일: presigned GET URL + 매칭된 원본의 presigned GET URL 도 함께 반환.
    const items = await Promise.all(
      thumbs.map(async (o) => {
        const origKey = origMap.get(stem(o.Key));
        const [url, originalUrl] = await Promise.all([
          getSignedUrl(s3, new GetObjectCommand({ Bucket: BUCKET, Key: o.Key }), { expiresIn: VIEW_EXPIRES }),
          origKey
            ? getSignedUrl(s3, new GetObjectCommand({ Bucket: BUCKET, Key: origKey }), { expiresIn: VIEW_EXPIRES })
            : Promise.resolve(null),
        ]);
        return { key: o.Key, url, originalUrl };
      })
    );

    return json(200, { items });
  } catch (err) {
    console.error("list error:", err);
    return json(500, { message: "failed to list albums" });
  }
};

function json(statusCode, obj) {
  return { statusCode, headers: { "content-type": "application/json" }, body: JSON.stringify(obj) };
}
