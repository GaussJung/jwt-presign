# 강사용 노트

## 사전 인수 테스트 (비협상)
수업 전, **학생과 동일 AMI(Ubuntu 24.04 x86_64)** 로 강사용 EC2 1대를 띄워
`git clone` → `00`~`90` 을 끝까지 통과시킨다. 이 라이브 통과가 진짜 '완료' 기준.

## 1순위 리스크 — 중앙 issuer (단일 장애점)
- `auth-lab.nexioengine.com` 이 7~10명 전원의 검증을 책임진다. 미스컨피그 시 전원 동시 401.
- 점검: `curl .../.well-known/openid-configuration` 과 `.../.well-known/jwks.json` 의
  JSON 응답 + `content-type: application/json` + `issuer` 정확 일치(끝 슬래시 없음).
- 비상책: 정상 토큰 1개 + `lambdas/_backup-authorizer` 를 준비해 두면 escape hatch.

## 타임테이블(3시간, 스크립트 실행+코드읽기 중심)
- 0:00 개념(JWT) · 0:20 아키텍처/환경 · 0:35 인프라(00~04)
- 1:20 API+Authorizer(05) · 1:45 업로드(웹) · 2:05 이벤트→썸네일(06)
- 2:30 조회/aud 실패 데모 · 2:45 트러블슈팅·teardown

## 환경별 주의
- Windows 작성: 셸 스크립트 LF 유지(.gitattributes), sharp는 `--os=linux --cpu=x64`
- 학생 EC2: 보안그룹 3000 포트 인바운드(웹 접속용) 임시 개방, 수업 후 닫기
- 비용: t3.micro × 인원수 + Lambda/S3 소액. 반드시 teardown + EC2 종료 안내
