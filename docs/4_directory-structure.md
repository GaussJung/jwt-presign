# 디렉토리 구조도

> Simple Album 실습 프로젝트(JWT + Presigned URL 서버리스 업로드)의 리포 구조.
> 작성 환경(Windows)에서 push → 실습자가 본인 EC2(Ubuntu 24.04)에서 `git pull` 후 실행한다.

## 전체 트리

```
jwt-presign/
├── README.md                     # 프로젝트 개요 + 빠른 시작
├── .gitignore                    # *.pem · .env · *.zip · node_modules/ · refdoc/ · requests/ 제외
├── .gitattributes                # *.sh → eol=lf 강제(CRLF 혼입 방지)
│
├── auth-server/                  # ── EC2 Node 서버: /login(JWT 발행) + 웹 클라이언트 서빙 ──
│   ├── package.json              #   deps: express, jose
│   ├── src/
│   │   ├── server.js             #   Express 진입점 · /config.json · 정적(public/) 서빙
│   │   ├── jwt.js                #   RS256 JWT 발행(개인키 서명, iss/aud/kid 설정)
│   │   └── routes/
│   │       └── login.js          #   POST /login (데모 인증 → issueToken)
│   ├── public/                   #   간편앨범 웹 클라이언트(정적)
│   │   ├── index.html
│   │   └── app.js                #   로그인 → presign → S3 업로드 → 목록 조회
│   └── keys/                     #   개인키 배치 위치(리포에 키 없음)
│       ├── README.md             #   jwt_private_key.pem 배치 안내
│       └── .gitkeep              #   빈 디렉토리 유지용
│
├── lambdas/                      # ── 서버리스 함수(Node 24.x, ESM) ──
│   ├── presign-creator/          #   POST /presign → presigned PUT URL 생성(expiresIn=300)
│   │   ├── index.mjs
│   │   └── package.json
│   ├── thumbnailer/              #   S3 Event(original/) → sharp 썸네일 자동 생성
│   │   ├── index.mjs
│   │   └── package.json
│   ├── album-list/               #   GET /albums → ListObjectsV2 + presigned GET URL
│   │   ├── index.mjs
│   │   └── package.json
│   └── _backup-authorizer/       #   비상용 Lambda Authorizer(기본 경로는 네이티브 JWT Authorizer)
│       ├── index.mjs
│       └── package.json
│
├── scripts/                      # ── 프로비저닝 스크립트(EC2/Ubuntu bash) ──
│   ├── 00_prereqs.sh             #   CLI/자격증명/리전/ACCOUNT_ID 사전 점검
│   ├── 01_create_bucket.sh       #   S3 버킷 + CORS
│   ├── 02_create_iam_roles.sh
│   ├── 03_publish_layer.sh       #   EC2에서 sharp 빌드 → 레이어 publish(x86_64)
│   ├── 04_deploy_lambdas.sh
│   ├── 05_create_http_api.sh     #   HTTP API + 네이티브 JWT Authorizer + 라우트/CORS
│   ├── 06_wire_s3_event.sh       #   S3 이벤트 트리거(prefix=gallery/original/)
│   ├── 90_smoke_test.sh          #   로그인→presign→업로드→썸네일→목록 end-to-end
│   ├── 99_teardown.sh            #   파괴적 — 사용자 명시 확인 후에만
│   └── powershell/               # ── Windows(.ps1) 동일 스크립트 세트 ──
│       ├── 00_prereqs.ps1 · 01_create_bucket.ps1 · 02_create_iam_roles.ps1
│       ├── 03_publish_layer.ps1 · 04_deploy_lambdas.ps1 · 05_create_http_api.ps1
│       ├── 06_wire_s3_event.ps1 · 90_smoke_test.ps1 · 99_teardown.ps1
│       └── _load_state.ps1       #   스크립트 간 리소스 ID 상태 로드(Windows용 헬퍼)
│
├── terraform/                    # ── 심화 과제: 01·02·04·05·06 을 Terraform(선언형)으로 ──
│   ├── *.tf                      #   s3/iam/lambda/apigw/s3_event 등(기존 sh와 1:1 매핑)
│   ├── tf_00_install.sh          #   Terraform 설치(Ubuntu, HashiCorp apt)
│   ├── tf_10_apply.sh            #   env.sh 주입 → init/apply → .state 브리지(90 호환)
│   ├── tf_99_destroy.sh          #   파괴적 — DELETE 입력 후에만
│   ├── .gitignore                #   tfstate/.terraform 커밋 방지
│   └── doc/                      #   README(매뉴얼) + apply 순서 다이어그램(png)
│
├── config/                       # ── 환경값 단일 출처 + 정책 템플릿 ──
│   ├── env.sh / env.ps1          #   계정ID·리전·issuer·audience 등(런타임 로드)
│   ├── lambda-trust-policy.json  #   Lambda 신뢰 정책
│   ├── lambda-s3-policy.json     #   Lambda 실행 권한(버킷/프리픽스 최소화)
│   ├── s3-cors.json              #   S3 버킷 CORS(PUT)
│   └── README.md
│
├── docs/                         # ── 문서(공개) ──
│   ├── 1_lab-guide.md                         #   실습자용 실습 가이드(3시간)
│   ├── 2_JWT_Presigned_URL_개념설명_v1.0.pdf  #   개념 교육 자료(외부 배포물)
│   ├── 3_jwt_presign_practice_guide.md        #   실습 절차서(손으로 따라 하기)
│   ├── 4_directory-structure.md               #   (이 문서) 디렉토리 구조도
│   └── 5_operation_maintenance_manual.md      #   운영/유지보수 매뉴얼
│
├── refdoc/                       # ── 참조 자료(.gitignore 제외, 공개 리포 미포함) ──
│   ├── gen-authlab.mjs           #   공개키 → JWKS + OIDC discovery 생성기
│   ├── auth-lab-keys-setup_v2.md #   중앙 issuer 키/호스팅 셋업
│   ├── files/ · files.zip
│   └── *.pdf · *.docx · *.pptx   #   교육 슬라이드/문서
│
└── requests/                     # ── 요청 세션 시스템(.gitignore 제외) ──
    ├── CHANGELOG.md              #   요청 처리 로그(append-only)
    └── sessions/
        ├── R01_A_초기화.md       #   R{NN}_{X}_{slug}: 라운드 · 관심사 · 슬러그
        └── R01_B_환경설정.md
```

## 컴포넌트 한눈에

| 영역 | 위치 | 실행 주체 | 역할 |
|---|---|---|---|
| 인증/웹 서버 | `auth-server/` | 실습자 EC2 | RS256 JWT 발행 + 웹 클라이언트 서빙 |
| 서버리스 함수 | `lambdas/` | AWS Lambda | presign 발급 · 썸네일 · 목록 |
| 프로비저닝 | `scripts/` (bash) · `scripts/powershell/` (.ps1) | EC2 / Windows | 인프라 생성·배포·정리 |
| IaC 심화 과제 | `terraform/` | 배포서버 EC2 | 01·02·04·05·06 을 선언형으로 배포(매뉴얼: `terraform/doc/`) |
| 설정/정책 | `config/` | 스크립트가 로드 | 환경값 단일 출처 + IAM/CORS 템플릿 |
| 문서 | `docs/` | — | 실습자/강사 가이드 |

## 공개 리포 위생 (요약)

- **리포에 절대 미포함:** 개인키(`*.pem`), `.env`, 바이너리 `*.zip`, `node_modules/`.
- **`.gitignore`로 제외(로컬 전용):** `refdoc/`, `requests/`, `CLAUDE.md`.
- 개인키 `jwt_private_key.pem`은 폐쇄 커뮤니티로만 전달 → `auth-server/keys/`에 직접 배치.
- JWKS는 EC2가 아닌 **중앙 issuer**(`https://auth-lab.nexioengine.com`)가 호스팅.
