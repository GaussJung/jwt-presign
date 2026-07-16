# =============================================================================
# s3_event.tf — S3 업로드 이벤트 → thumbnailer 연결   (기존 06_wire_s3_event.sh 대체)
# -----------------------------------------------------------------------------
# ⚠️ 무한루프 방지(가장 중요): 트리거는 'gallery/original/' prefix 에만 건다.
#    썸네일은 'gallery/thumb/' 로 쓰므로 썸네일 생성이 다시 트리거되지 않는다.
# =============================================================================

# 1) S3 가 thumbnailer 를 호출할 권한
resource "aws_lambda_permission" "s3_invoke_thumb" {
  statement_id   = "s3invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.thumb.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.album.arn
  source_account = local.account_id # 다른 계정의 동명 버킷 위장 방지
}

# 2) 버킷 이벤트 알림 — original/ prefix 한정
#    depends_on: 권한이 먼저 있어야 알림 설정 검증(S3 의 test invoke)이 통과한다.
resource "aws_s3_bucket_notification" "album" {
  bucket = aws_s3_bucket.album.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.thumb.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "gallery/original/"
  }

  depends_on = [aws_lambda_permission.s3_invoke_thumb]
}
