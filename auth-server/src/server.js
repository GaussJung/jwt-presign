// =============================================================================
// src/server.js  —  Express 진입점 (EC2에서 npm start)
// -----------------------------------------------------------------------------
// 제공:
//   - POST /login        : RS256 JWT 발행
//   - GET  /config.json  : 웹 클라이언트가 읽는 API 엔드포인트(환경변수로 주입)
//   - 정적 파일(public/) : 간편앨범 웹 클라이언트
// 실행: API_ENDPOINT=https://xxxx.execute-api.ap-northeast-2.amazonaws.com npm start
// =============================================================================
import express from "express";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import loginRoute from "./routes/login.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PORT = process.env.PORT || 3000;
const API_ENDPOINT = process.env.API_ENDPOINT || ""; // 05 스크립트 출력값을 넣는다.

const app = express();
app.use(express.json());

// 웹 클라이언트가 API 주소를 알 수 있도록 런타임 설정 노출(코드에 하드코딩하지 않기 위함)
app.get("/config.json", (_req, res) => res.json({ apiEndpoint: API_ENDPOINT }));

app.use(loginRoute);
app.use(express.static(join(__dirname, "..", "public")));

app.listen(PORT, () => {
  console.log(`[auth-server] http://localhost:${PORT}  (API_ENDPOINT=${API_ENDPOINT || "미설정"})`);
});
