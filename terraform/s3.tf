# =============================================================================
# s3.tf — S3 버킷 + 퍼블릭 차단 + CORS   (기존 01_create_bucket.sh 대체)
# =============================================================================

resource "aws_s3_bucket" "album" {
  bucket = local.bucket

  # 교육용: destroy 시 객체가 남아 있어도 비우고 삭제한다.
  # (기존 99_teardown.sh 의 's3 rm --recursive' 단계를 대체)
  force_destroy = true
}

# 퍼블릭 액세스 전체 차단 — 조회는 presigned GET 으로만
resource "aws_s3_bucket_public_access_block" "album" {
  bucket = aws_s3_bucket.album.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# 브라우저 직접 PUT/GET 허용 — config/s3-cors.json 과 동일 값
resource "aws_s3_bucket_cors_configuration" "album" {
  bucket = aws_s3_bucket.album.id

  cors_rule {
    allowed_origins = ["*"] # 교육 한정. 운영이라면 EC2 DNS 로 좁힌다.
    allowed_methods = ["PUT", "GET", "HEAD"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}
