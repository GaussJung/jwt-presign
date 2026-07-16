# =============================================================================
# iam.tf — Lambda 실행 역할 + 최소권한 정책   (기존 02_create_iam_roles.sh 대체)
# -----------------------------------------------------------------------------
# 기존 스크립트의 'IAM 전파 대기 10초(sleep)' 는 필요 없다 — Terraform 의
# AWS Provider 가 역할→함수 의존 관계를 알고 자동 재시도한다.
# =============================================================================

# 역할: Lambda 서비스가 맡을 수 있는 신뢰 정책 — config/lambda-trust-policy.json 과 동일
resource "aws_iam_role" "lambda" {
  name = var.lambda_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# 기본 로깅 권한(CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "basic_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# S3 인라인 권한 — 우리 버킷 gallery/* 한정 (config/lambda-s3-policy.json 과 동일)
# 기존 sed 의 __BUCKET__ 치환이 Terraform 참조로 자연스럽게 해결된다.
resource "aws_iam_role_policy" "s3_gallery_rw" {
  name = "s3-gallery-rw"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ObjectRW"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.album.arn}/gallery/*"
      },
      {
        Sid      = "ListGalleryOnly"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.album.arn
        Condition = {
          StringLike = { "s3:prefix" = ["gallery/*"] }
        }
      }
    ]
  })
}
