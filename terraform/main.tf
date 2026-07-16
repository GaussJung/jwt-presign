# =============================================================================
# main.tf — 데이터 소스 + 공통 로컬 값
# -----------------------------------------------------------------------------
# 여기서 '조회'만 하고 리소스는 만들지 않는다.
#   - 계정ID: 하드코딩 금지 → 실행 시점 자격증명에서 동적 취득 (env.sh 와 동일 원리)
#   - sharp 레이어: Terraform 이 만들지 않는다. 03_publish_layer.sh 가 EC2에서
#     네이티브 빌드 후 게시한 '최신 버전'을 이름으로 조회해 참조만 한다.
#     → 레이어가 없으면 plan 단계에서 실패한다 = 03 을 먼저 실행할 것.
# =============================================================================

data "aws_caller_identity" "current" {}

data "aws_lambda_layer_version" "sharp" {
  layer_name = var.sharp_layer_name
}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # 버킷명 규칙: myalbum-{계정ID} (계정 격리라 접미사 불필요) — env.sh BUCKET 과 동일
  bucket = "myalbum-${local.account_id}"

  # Lambda 코드가 process.env 로 읽는 공통 환경변수 (04 스크립트와 동일)
  lambda_env = {
    BUCKET   = local.bucket
    REGION   = var.region
    ISSUER   = var.issuer
    AUDIENCE = var.audience
  }

  # 이 모듈(terraform/)에서 리포 루트까지의 상대 경로
  repo_root = "${path.module}/.."
}
