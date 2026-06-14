# config/ — 설정 파일 설명

AWS CLI가 직접 읽는 JSON에는 주석을 넣을 수 없어, 설명은 여기에 둔다.

- **env.sh / env.ps1** — 환경변수 단일 출처(bash / PowerShell). 실제 계정ID·시크릿 하드코딩 금지.
  `ACCOUNT_ID`는 `aws sts get-caller-identity`로 런타임에 취득.
- **s3-cors.json** — S3 버킷 CORS. 브라우저가 presigned URL로 직접 PUT/GET 할 때 필요.
  교육용이라 `AllowedOrigins:["*"]`(운영에서는 실제 도메인으로 제한).
- **lambda-trust-policy.json** — Lambda 실행 역할의 신뢰 정책('lambda 서비스가 이 역할을 맡는다').
- **lambda-s3-policy.json** — Lambda 최소권한(우리 버킷 `gallery/*` 한정).
  `__BUCKET__` 은 `02_create_iam_roles` 스크립트가 실제 버킷명으로 치환한다.
