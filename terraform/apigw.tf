# =============================================================================
# apigw.tf — HTTP API + 네이티브 JWT Authorizer   (기존 05_create_http_api.sh 대체)
# -----------------------------------------------------------------------------
# 핵심은 sh 버전과 동일: Authorizer 는 코드가 아니라 issuer + audience 설정만으로
# 동작한다. AWS 가 {issuer}/.well-known/* 를 읽어 서명/iss/aud/exp 를 검증.
# 기존 05 의 '이름으로 조회해 재사용' 멱등 로직은 tfstate 가 대신한다.
# =============================================================================

resource "aws_apigatewayv2_api" "album" {
  name          = var.api_name
  protocol_type = "HTTP"

  # CORS — 브라우저에서 Authorization 헤더 호출 허용 (기존 4) 단계와 동일)
  cors_configuration {
    allow_origins = ["*"] # 교육 한정
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
  }
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.album.id
  name             = "jwt-authorizer"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"] # Bearer 토큰 위치

  jwt_configuration {
    issuer   = var.issuer     # 토큰 iss 와 끝 슬래시까지 정확히 일치!
    audience = [var.audience] # 토큰 aud 와 일치
  }
}

# --- POST /presign → presign-creator -----------------------------------------
resource "aws_apigatewayv2_integration" "presign" {
  api_id                 = aws_apigatewayv2_api.album.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.presign.invoke_arn
  payload_format_version = "2.0" # 이벤트에 requestContext.authorizer.jwt.claims 포함
}

resource "aws_apigatewayv2_route" "presign" {
  api_id             = aws_apigatewayv2_api.album.id
  route_key          = "POST /presign"
  target             = "integrations/${aws_apigatewayv2_integration.presign.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

# --- GET /albums → album-list -------------------------------------------------
resource "aws_apigatewayv2_integration" "list" {
  api_id                 = aws_apigatewayv2_api.album.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.list.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "list" {
  api_id             = aws_apigatewayv2_api.album.id
  route_key          = "GET /albums"
  target             = "integrations/${aws_apigatewayv2_integration.list.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

# --- API Gateway → Lambda 호출 권한 -------------------------------------------
resource "aws_lambda_permission" "apigw_presign" {
  statement_id  = "apigw-POST-presign"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.presign.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.album.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_list" {
  statement_id  = "apigw-GET-albums"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.album.execution_arn}/*/*"
}

# --- 기본 스테이지(auto-deploy) ------------------------------------------------
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.album.id
  name        = "$default"
  auto_deploy = true
}
