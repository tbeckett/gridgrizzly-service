# =============================================================================
# api_gateway.tf — REST API, Lambda Authorizer attachment, Usage Plan
# =============================================================================

# ── REST API ──────────────────────────────────────────────────────────────────

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.environment}-authorizer-service-api"
  description = "Serverless REST API with Auth0 JWT authorisation"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${var.environment}-authorizer-service-api"
  }
}

# ── Lambda Authorizer ─────────────────────────────────────────────────────────

resource "aws_api_gateway_authorizer" "jwt" {
  name                             = "${var.environment}-jwt-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.main.id
  authorizer_uri                   = aws_lambda_function.authorizer.invoke_arn
  authorizer_credentials           = aws_iam_role.api_gateway_invoker.arn
  type                             = "TOKEN"
  identity_source                  = "method.request.header.Authorization"

  # API Gateway caches a successful Authorizer response for this TTL.
  # Requests arriving with the same token within the window skip Lambda invocation entirely.
  # Set to 0 during development to disable caching and see fresh validation on every call.
  authorizer_result_ttl_in_seconds = var.authorizer_cache_ttl_seconds
}

# ── IAM role — API Gateway → Lambda Authorizer invocation ─────────────────────

resource "aws_iam_role" "api_gateway_invoker" {
  name               = "${var.environment}-apigw-authorizer-invoker"
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
}

data "aws_iam_policy_document" "apigw_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "apigw_invoke_authorizer" {
  name   = "invoke-authorizer-lambda"
  role   = aws_iam_role.api_gateway_invoker.id
  policy = data.aws_iam_policy_document.apigw_invoke_authorizer.json
}

data "aws_iam_policy_document" "apigw_invoke_authorizer" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.authorizer.arn]
  }
}

# ── Example resource: /items ──────────────────────────────────────────────────
# Replace or extend this block with your actual API resources.
# Every method that requires authentication must reference the JWT authorizer.

resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "items"
}

resource "aws_api_gateway_method" "items_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.items.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.jwt.id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

# ── Deployment and Stage ──────────────────────────────────────────────────────

# A new deployment is created whenever the REST API definition changes.
# The triggers map forces a redeployment when any resource or method changes.
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_rest_api.main.body,
      aws_api_gateway_resource.items.id,
      aws_api_gateway_method.items_get.id,
      aws_api_gateway_authorizer.jwt.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.api_stage_name

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      sourceIp       = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      userId         = "$context.authorizer.userId"
    })
  }

  # "Active" sampling traces every request. Switch to false at high volume and
  # rely on X-Ray sampling rules to reduce tracing cost.
  xray_tracing_enabled = var.xray_tracing_enabled

  tags = {
    Name = "${var.environment}-api-stage-${var.api_stage_name}"
  }

  depends_on = [aws_cloudwatch_log_group.api_gateway_access]
}

resource "aws_api_gateway_method_settings" "throttle" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.main.stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = var.api_throttle_rate_limit
    throttling_burst_limit = var.api_throttle_burst_limit

    # Emit execution metrics (latency, errors) to CloudWatch for all methods.
    metrics_enabled = true

    # Log full request/response data at ERROR level only.
    # Set to "INFO" to log all requests — useful in dev, costly in production.
    logging_level = "ERROR"
  }
}

# ── Usage Plan ────────────────────────────────────────────────────────────────
# Usage Plans enforce quotas and throttling at the API key level, independently
# of the stage-level throttling above. This is the correct mechanism for
# per-client rate limiting in production.

resource "aws_api_gateway_usage_plan" "main" {
  name        = "${var.environment}-usage-plan"
  description = "Default usage plan for ${var.environment}"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.main.stage_name
  }

  throttle_settings {
    rate_limit  = var.api_throttle_rate_limit
    burst_limit = var.api_throttle_burst_limit
  }

  # Optional: add a quota block here to enforce daily/weekly/monthly request caps.
  # quota_settings { limit = 10000; period = "DAY" }
}

# ── CloudWatch log group — API Gateway access logs ────────────────────────────

resource "aws_cloudwatch_log_group" "api_gateway_access" {
  name              = "/aws/apigateway/${var.environment}-authorizer-service-access"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.environment}-api-gateway-access-logs"
  }
}

# ── IAM — allow API Gateway to write to CloudWatch Logs ──────────────────────
# This is a regional account-level setting. If another Terraform workspace has
# already set this, it is safe to import the existing resource rather than
# creating a new one.

resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn
}

resource "aws_iam_role" "api_gateway_cloudwatch" {
  name               = "${var.environment}-apigw-cloudwatch-role"
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}
