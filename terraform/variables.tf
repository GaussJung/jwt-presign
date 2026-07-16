# =============================================================================
# variables.tf — 입력 변수
# -----------------------------------------------------------------------------
# 단일 출처 원칙: 프로젝트 환경값의 단일 출처는 config/env.sh 다.
#   tf_10_apply.sh 래퍼가 env.sh 를 source 한 뒤 TF_VAR_* 로 주입한다.
#   아래 default 는 env.sh 와 '동일한 값'의 안전망일 뿐, 값 변경은 env.sh 에서만.
# ACCOUNT_ID 는 변수로 받지 않는다 — main.tf 의 aws_caller_identity 로 동적 취득
#   (계정ID 하드코딩 금지 규칙과 동일한 원리).
# =============================================================================

variable "region" {
  description = "AWS 리전 (env.sh REGION)"
  type        = string
  default     = "ap-northeast-2"
}

variable "issuer" {
  description = "JWT 발행자 — 토큰 iss 와 끝 슬래시까지 정확히 일치해야 함 (env.sh ISSUER)"
  type        = string
  default     = "https://auth-lab.nexioengine.com"
}

variable "audience" {
  description = "JWT aud (env.sh AUDIENCE)"
  type        = string
  default     = "myalbum1"
}

variable "api_name" {
  description = "HTTP API 이름 (env.sh API_NAME)"
  type        = string
  default     = "simple-album"
}

variable "lambda_role_name" {
  description = "Lambda 실행 역할 이름 (env.sh LAMBDA_ROLE_NAME)"
  type        = string
  default     = "simple-album-lambda-role"
}

variable "sharp_layer_name" {
  description = "sharp 레이어 이름 — 03_publish_layer.sh 가 먼저 게시해 두어야 함 (env.sh SHARP_LAYER_NAME)"
  type        = string
  default     = "sharp-x64"
}

variable "fn_presign" {
  description = "presign-creator 함수 이름 (env.sh FN_PRESIGN)"
  type        = string
  default     = "simple-album-presign-creator"
}

variable "fn_thumb" {
  description = "thumbnailer 함수 이름 (env.sh FN_THUMB)"
  type        = string
  default     = "simple-album-thumbnailer"
}

variable "fn_list" {
  description = "album-list 함수 이름 (env.sh FN_LIST)"
  type        = string
  default     = "simple-album-album-list"
}
