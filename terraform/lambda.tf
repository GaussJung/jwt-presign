# =============================================================================
# lambda.tf — Lambda 함수 3종 배포   (기존 04_deploy_lambdas.sh 대체)
# -----------------------------------------------------------------------------
# 패키징: archive_file 데이터 소스가 lambdas/{함수}/ 디렉토리를 zip 으로 만든다.
#   - node_modules 는 제외한다: nodejs24.x 런타임에 AWS SDK v3 가 내장되어
#     있고(각 package.json 의 _note 참조), sharp 는 레이어에서 공급되기 때문.
#   - source_code_hash 덕분에 코드가 바뀐 경우에만 재배포된다(멱등성 자동).
# =============================================================================

# --- presign-creator: PUT presigned URL 발급 --------------------------------
data "archive_file" "presign" {
  type        = "zip"
  source_dir  = "${local.repo_root}/lambdas/presign-creator"
  output_path = "${path.module}/build/presign-creator.zip"
  excludes    = ["node_modules", "node_modules/**", "package-lock.json"]
}

resource "aws_lambda_function" "presign" {
  function_name = var.fn_presign
  role          = aws_iam_role.lambda.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  architectures = ["x86_64"]

  filename         = data.archive_file.presign.output_path
  source_code_hash = data.archive_file.presign.output_base64sha256

  timeout     = 10
  memory_size = 256

  environment {
    variables = local.lambda_env
  }
}

# --- album-list: 본인 썸네일 목록 + GET presigned URL ------------------------
data "archive_file" "list" {
  type        = "zip"
  source_dir  = "${local.repo_root}/lambdas/album-list"
  output_path = "${path.module}/build/album-list.zip"
  excludes    = ["node_modules", "node_modules/**", "package-lock.json"]
}

resource "aws_lambda_function" "list" {
  function_name = var.fn_list
  role          = aws_iam_role.lambda.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  architectures = ["x86_64"]

  filename         = data.archive_file.list.output_path
  source_code_hash = data.archive_file.list.output_base64sha256

  timeout     = 10
  memory_size = 256

  environment {
    variables = local.lambda_env
  }
}

# --- thumbnailer: S3 이벤트 → sharp 리사이즈 (레이어 부착, 메모리/타임아웃 ↑) --
data "archive_file" "thumb" {
  type        = "zip"
  source_dir  = "${local.repo_root}/lambdas/thumbnailer"
  output_path = "${path.module}/build/thumbnailer.zip"
  excludes    = ["node_modules", "node_modules/**", "package-lock.json"]
}

resource "aws_lambda_function" "thumb" {
  function_name = var.fn_thumb
  role          = aws_iam_role.lambda.arn
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  architectures = ["x86_64"]

  filename         = data.archive_file.thumb.output_path
  source_code_hash = data.archive_file.thumb.output_base64sha256

  timeout     = 30
  memory_size = 512

  # 03_publish_layer.sh 가 게시한 최신 레이어 버전(main.tf 의 data 소스)
  layers = [data.aws_lambda_layer_version.sharp.arn]

  environment {
    variables = local.lambda_env
  }
}
