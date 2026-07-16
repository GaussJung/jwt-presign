# =============================================================================
# outputs.tf — 출력값
# -----------------------------------------------------------------------------
# tf_10_apply.sh 가 이 출력을 .state/resources.env 로 내보낸다(브리지).
# → 기존 90_smoke_test.sh 가 무수정으로 동작한다(API_ENDPOINT 를 source 하므로).
# =============================================================================

output "api_id" {
  description = "HTTP API ID"
  value       = aws_apigatewayv2_api.album.id
}

output "api_endpoint" {
  description = "호출 URL (90_smoke_test.sh 가 사용)"
  value       = aws_apigatewayv2_api.album.api_endpoint
}

output "bucket" {
  description = "S3 버킷명"
  value       = aws_s3_bucket.album.id
}

output "role_arn" {
  description = "Lambda 실행 역할 ARN"
  value       = aws_iam_role.lambda.arn
}

output "sharp_layer_arn" {
  description = "참조 중인 sharp 레이어 버전 ARN (03 이 게시한 최신)"
  value       = data.aws_lambda_layer_version.sharp.arn
}

output "authorizer_id" {
  description = "JWT Authorizer ID"
  value       = aws_apigatewayv2_authorizer.jwt.id
}
