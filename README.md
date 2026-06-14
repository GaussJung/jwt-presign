# Simple Album — AWS 서버리스 업로드 실습

JWT(RS256) + Presigned URL 기반 서버리스 파일 업로드를 직접 구현하는 3시간 교육용 프로젝트.

로그인 → JWT 발행 → presigned URL → S3 직접 업로드 → 썸네일 자동 생성 → 목록/원본 조회

## 디렉토리 구조
```
simple-album/
├── CLAUDE.md              # Claude Code 작업 기준(프로젝트 규칙)
├── config/                # env.sh / env.ps1(설정 단일 출처), CORS·IAM 정책
├── scripts/               # 프로비저닝 스크립트 (.sh = mac/ubuntu, .ps1 = windows)
│   ├── 00_prereqs · 01_create_bucket · 02_create_iam_roles
│   ├── 03_publish_layer · 04_deploy_lambdas · 05_create_http_api · 06_wire_s3_event
│   └── 90_smoke_test · 99_teardown
├── lambdas/               # presign-creator · thumbnailer · album-list · _backup-authorizer
├── auth-server/           # EC2 Node: /login(JWT 발행) + 웹 클라이언트(public/)
│   └── keys/              # private.pem 을 여기 둔다(폐쇄 커뮤니티 배포, 리포에 없음)
└── docs/                  # lab-guide(학생용) · instructor-notes(강사용)
```

## 빠른 시작 (학생, 본인 EC2 / Ubuntu 24.04)
```bash
git clone <this-repo> && cd simple-album
# 0) private.pem 을 auth-server/keys/ 에 배치 (커뮤니티에서 받은 파일)
# 1) 프로비저닝 (mac/ubuntu)
bash scripts/00_prereqs.sh
bash scripts/01_create_bucket.sh
bash scripts/02_create_iam_roles.sh
bash scripts/03_publish_layer.sh
bash scripts/04_deploy_lambdas.sh
bash scripts/05_create_http_api.sh   # 출력된 API 주소를 메모
bash scripts/06_wire_s3_event.sh
# 2) 인증/웹 서버 실행 (05에서 받은 API 주소 주입)
cd auth-server && npm install
API_ENDPOINT=<05에서 출력된 주소> npm start
# 3) 브라우저에서 http://<EC2-public>:3000 접속 → 로그인/업로드/조회
# 4) 실습 후 정리(비용 방지)
bash scripts/99_teardown.sh
```
> Windows에서 실행한다면 `scripts\00_prereqs.ps1` … 처럼 .ps1 버전을 쓴다.

## 보안 (교육 한정)
- `private.pem` 은 **공개 리포 금지**. 폐쇄 커뮤니티 배포, 수업 후 폐기.
- EC2 IAM 관리자 권한은 샌드박스 전용. 실습 후 `99_teardown` + EC2 종료.

자세한 단계는 `docs/lab-guide.md`, 강사용은 `docs/instructor-notes.md` 참고.
