// =============================================================================
// thumbnailer / index.mjs
// -----------------------------------------------------------------------------
// 역할: 원본 이미지가 업로드되면 자동으로 썸네일을 만들어 저장한다.
// 트리거: S3 ObjectCreated 이벤트 (prefix=gallery/original/ 에만 연결됨 — 06 스크립트).
//
// ⚠️ 무한루프 주의: 썸네일을 gallery/thumb/ 로 '쓰는' 동작이 다시 이벤트를 일으키지 않도록,
//    트리거는 original/ prefix 에만 걸려 있다(06_wire_s3_event). 코드에서도 thumb/는 무시.
//
// [입력] S3 이벤트(요약):
//   { "Records": [ {
//       "s3": {
//         "bucket": { "name": "myalbum-111122223333" },
//         "object": { "key": "gallery/original/james/20260615_1718....jpg" }
//       } } ] }
//   참고: object.key 는 URL 인코딩되어 올 수 있다(공백→'+', 한글→%xx) → 디코딩 필요.
//
// [출력] 없음(S3에 thumb 객체 생성). 실패 시 throw → CloudWatch Logs 기록.
// =============================================================================
import { S3Client, GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import sharp from "sharp"; // ← Lambda 레이어(sharp-x64)에서 제공됨. 함수 zip에는 넣지 않는다.

const REGION = process.env.REGION;
const s3 = new S3Client({ region: REGION });

const THUMB_WIDTH = 320; // 썸네일 가로 px (세로는 비율 유지)

export const handler = async (event) => {
  for (const record of event.Records ?? []) {
    const bucket = record.s3.bucket.name;
    // S3 key 디코딩(+ → space, %xx → char)
    const srcKey = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));

    // 안전장치: 혹시 thumb/ 키가 들어오면 건너뛴다(이중 방어).
    if (!srcKey.startsWith("gallery/original/")) {
      console.log("skip non-original key:", srcKey);
      continue;
    }

    // 대상 키: gallery/original/... → gallery/thumb/...  (같은 파일명 유지)
    const dstKey = srcKey.replace("gallery/original/", "gallery/thumb/");

    console.log(`thumbnail: ${srcKey} → ${dstKey}`);

    // 1) 원본 다운로드 (스트림 → 버퍼)
    const obj = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: srcKey }));
    const inputBuffer = await streamToBuffer(obj.Body);

    // 2) 리사이즈 (가로 320, 비율 유지, jpeg 품질 80)
    const outputBuffer = await sharp(inputBuffer)
      .resize({ width: THUMB_WIDTH, withoutEnlargement: true })
      .jpeg({ quality: 80 })
      .toBuffer();

    // 3) 썸네일 업로드
    await s3.send(new PutObjectCommand({
      Bucket: bucket, Key: dstKey, Body: outputBuffer, ContentType: "image/jpeg",
    }));
  }
  return { ok: true };
};

// Node 스트림을 Buffer로 모으는 헬퍼
async function streamToBuffer(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  return Buffer.concat(chunks);
}
