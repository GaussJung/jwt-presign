// =============================================================================
// app.js  —  간편앨범 웹 클라이언트 (교육용)
// 라이트박스: 썸네일 클릭 → 원본 이미지 전체화면 팝업 / ✕ 버튼·ESC·오버레이 클릭으로 닫기
// -----------------------------------------------------------------------------
// 전체 흐름(아키텍처와 1:1):
//   1) POST /login            → JWT 토큰 수신(sessionStorage에 보관, 탭 닫으면 삭제)
//   2) GET  /config.json      → API Gateway 주소(코드 하드코딩 대신 런타임 주입)
//   3) POST {api}/presign     → presigned PUT URL + keyName 수신   (Authorization: Bearer)
//   4) PUT  {uploadUrl}       → S3로 이미지 직접 업로드 (Content-Type 일치 필수!)
//   5) GET  {api}/albums      → 본인 썸네일 목록 + presigned GET URL
// =============================================================================

const TOKEN_KEY = "session_token"; // sessionStorage 키 이름(하드코딩 분산 방지)
const SUB_KEY   = "session_sub";   // sub를 함께 보관해 복원 시 JWT 디코딩 없이 표시

let token = null;     // 현재 유효한 JWT (메모리 + sessionStorage에 동기화)
let apiEndpoint = ""; // /config.json 에서 주입

const $ = (id) => document.getElementById(id);
const log = (msg, cls = "") => {
  const el = $("log");
  el.innerHTML += `\n${cls ? `<span class="${cls}">${msg}</span>` : msg}`;
  el.scrollTop = el.scrollHeight;
};

function showLoggedIn(sub) {
  $("who").textContent = `로그인: ${sub}`;
  $("uploadBtn").disabled = false;
  $("refreshBtn").disabled = false;
  $("logoutBtn").style.display = "";
}

function showLoggedOut() {
  token = null;
  $("who").textContent = "로그아웃 상태";
  $("uploadBtn").disabled = true;
  $("refreshBtn").disabled = true;
  $("logoutBtn").style.display = "none";
  $("grid").innerHTML = "";
  $("emptyMsg").style.display = "block";
}

// 페이지 로드 시 API 주소를 서버 설정에서 읽어오고, sessionStorage를 복원한다.
(async () => {
  try {
    const cfg = await (await fetch("/config.json")).json();
    apiEndpoint = cfg.apiEndpoint || "";
    log(apiEndpoint ? `[config] API = ${apiEndpoint}` : "[config] API_ENDPOINT 미설정 — auth-server 실행 시 환경변수 필요", apiEndpoint ? "" : "log-err");
  } catch { log("[config] /config.json 로드 실패", "log-err"); }

  // 새로고침 후 세션 복원
  const saved = sessionStorage.getItem(TOKEN_KEY);
  const savedSub = sessionStorage.getItem(SUB_KEY);
  if (saved) {
    token = saved;
    showLoggedIn(savedSub || "unknown");
    log(`[session] 세션 복원 · sub=${savedSub}`, "log-ok");
    loadAlbums();
  }
})();

// --- 1) 로그인 ---------------------------------------------------------------
$("loginBtn").onclick = async () => {
  try {
    const res = await fetch("/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: $("username").value, password: $("password").value }),
    });
    if (!res.ok) throw new Error((await res.json()).message);
    const data = await res.json();
    token = data.token;
    sessionStorage.setItem(TOKEN_KEY, token);
    sessionStorage.setItem(SUB_KEY, data.sub);
    showLoggedIn(data.sub);
    log(`[login] OK · sub=${data.sub} · token=${token.slice(0, 24)}...`, "log-ok");
    loadAlbums();
  } catch (e) { log(`[login] 실패: ${e.message}`, "log-err"); }
};

// --- 로그아웃 ----------------------------------------------------------------
$("logoutBtn").onclick = () => {
  sessionStorage.removeItem(TOKEN_KEY);
  sessionStorage.removeItem(SUB_KEY);
  showLoggedOut();
  log("[logout] 로그아웃 완료. 탭을 닫으면 세션이 완전히 만료됩니다.", "log-ok");
};

// --- 3·4) 업로드: presign → S3 PUT ------------------------------------------
$("uploadBtn").onclick = async () => {
  const file = $("file").files[0];
  if (!file) return log("[upload] 파일을 먼저 선택하세요.", "log-err");
  try {
    // 3) presigned URL 요청 — contentType 은 실제 파일 타입과 같게 보낸다.
    const pres = await fetch(`${apiEndpoint}/presign`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
      body: JSON.stringify({ contentType: file.type }),
    });
    if (!pres.ok) throw new Error(`presign ${pres.status}`);
    const { uploadUrl, keyName } = await pres.json();
    log(`[presign] OK · key=${keyName}`, "log-ok");

    // 4) S3로 직접 PUT — ⚠️ Content-Type 이 presign 시점과 다르면 서명 불일치(403)
    const put = await fetch(uploadUrl, { method: "PUT", headers: { "content-type": file.type }, body: file });
    if (!put.ok) throw new Error(`S3 PUT ${put.status}`);
    log("[upload] S3 업로드 완료. 썸네일 생성까지 잠시 대기...", "log-ok");

    setTimeout(loadAlbums, 2500); // 썸네일 람다가 처리할 시간을 잠깐 준다
  } catch (e) { log(`[upload] 실패: ${e.message}`, "log-err"); }
};

$("refreshBtn").onclick = () => loadAlbums();

// --- 라이트박스 (원본 이미지 전체화면 팝업) ------------------------------------
function openLightbox(url) {
  $("lb-img").src = url;
  $("lightbox").classList.add("open");
}
function closeLightbox() {
  $("lightbox").classList.remove("open");
  $("lb-img").src = ""; // 메모리 해제
}
$("lb-close").onclick = closeLightbox;
$("lightbox").onclick = (e) => { if (e.target === $("lightbox")) closeLightbox(); }; // 오버레이 클릭
document.addEventListener("keydown", (e) => { if (e.key === "Escape") closeLightbox(); }); // ESC

// --- 5) 앨범 조회 ------------------------------------------------------------
async function loadAlbums() {
  try {
    const res = await fetch(`${apiEndpoint}/albums`, { headers: { authorization: `Bearer ${token}` } });
    if (!res.ok) throw new Error(`albums ${res.status}`);
    const { items } = await res.json();
    const grid = $("grid"); grid.innerHTML = "";
    $("emptyMsg").style.display = items.length ? "none" : "block";
    items.forEach((it) => {
      const img = document.createElement("img");
      img.src = it.url; img.alt = it.key; // presigned GET URL(썸네일)
      if (it.originalUrl) {
        img.classList.add("clickable");
        img.title = "클릭 — 원본 보기";
        img.onclick = () => openLightbox(it.originalUrl);
      }
      grid.appendChild(img);
    });
    log(`[albums] ${items.length}개 항목`, "log-ok");
  } catch (e) { log(`[albums] 실패: ${e.message}`, "log-err"); }
}
