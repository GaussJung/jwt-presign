// =============================================================================
// src/routes/login.js  —  POST /login
// -----------------------------------------------------------------------------
// 데모용 인증: 비밀번호가 'demo' 이면 통과(실습 단순화). 운영에서는 실제 사용자 저장소 검증.
// [요청] { "username": "james", "password": "demo" }
// [응답] { "token": "eyJhbGciOi...", "sub": "james" }
// =============================================================================
import { Router } from "express";
import { issueToken } from "../jwt.js";

const router = Router();

router.post("/login", async (req, res) => {
  const { username, password } = req.body ?? {};
  if (!username || password !== "demo") {
    return res.status(401).json({ message: "invalid credentials (데모: password는 'demo')" });
  }
  const token = await issueToken(username, "member");
  res.json({ token, sub: username });
});

export default router;
