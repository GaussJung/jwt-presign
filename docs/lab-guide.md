# 학생용 실습 가이드 (3시간)

> 본인 AWS 계정 + 본인 EC2(Ubuntu 24.04, x86_64)에서 진행합니다.

## 0. 준비 (수업 전/도입)
- EC2 접속(기본 사용자 `ubuntu`), Node 20·AWS CLI v2·jq·zip 설치 확인
- 커뮤니티에서 받은 `private.pem` 을 `auth-server/keys/` 에 복사
- `git clone` 후 프로젝트 루트로 이동

## 1. JWT 개념 (이해)
- iss / aud / sub / role 의 의미, RS256(비대칭) 검증 원리
- 발행은 EC2(개인키), 검증은 API Gateway(중앙 공개키 JWKS)

## 2. 인프라 만들기 (스크립트 실행 + 코드 읽기)
| 단계 | 명령 | 만드는 것 |
|---|---|---|
| 00 | `bash scripts/00_prereqs.sh` | 환경 점검 |
| 01 | `bash scripts/01_create_bucket.sh` | S3 버킷 + CORS |
| 02 | `bash scripts/02_create_iam_roles.sh` | Lambda 실행 역할 |
| 03 | `bash scripts/03_publish_layer.sh` | sharp 레이어 |
| 04 | `bash scripts/04_deploy_lambdas.sh` | Lambda 3종 |
| 05 | `bash scripts/05_create_http_api.sh` | API + JWT Authorizer |
| 06 | `bash scripts/06_wire_s3_event.sh` | S3 이벤트 → 썸네일 |

각 단계 후 해당 `lambdas/*/index.mjs` 또는 스크립트를 열어 **왜 그렇게 했는지** 주석을 읽습니다.

## 3. 동작 확인
- 인증/웹 서버 실행: `cd auth-server && npm install && API_ENDPOINT=<05주소> npm start`
- 브라우저 `http://<EC2-public>:3000` → 로그인 → 업로드 → 앨범에서 썸네일 확인
- (선택) 잘못된 aud 토큰으로 401 이 나는 것 관찰 → Authorizer의 역할 체감

## 4. 자주 막히는 곳
- **403 SignatureDoesNotMatch**: presign의 contentType ≠ PUT의 Content-Type
- **CORS 에러**: 버킷/API CORS 미적용 (01·05에서 설정됨, 재확인)
- **썸네일이 안 생김**: 06 트리거 prefix(original/) 확인, 람다 로그(CloudWatch)
- **401**: 토큰 iss/aud/kid 가 합의값과 일치하는지

## 5. 정리
- `bash scripts/99_teardown.sh` → `DELETE` 입력
- EC2 종료(비용 방지)
