# =============================================================================
# lambda_authorizer.tf — Lambda Authorizer function, IAM, VPC, and logging
# =============================================================================

# ── Lambda function ───────────────────────────────────────────────────────────

resource "aws_lambda_function" "authorizer" {
  function_name = "${var.environment}-jwt-authorizer"
  description   = "API Gateway Token Authorizer — validates Auth0 JWTs and injects userId into request context"

  # The shaded JAR produced by 'mvn package' in the authorizer-lambda module.
  filename         = var.lambda_jar_path
  source_code_hash = filebase64sha256(var.lambda_jar_path)

  # Fully-qualified handler: package.ClassName::methodName
  handler = "com.gridgrizzly.authorizer.LambdaAuthorizer::handleRequest"

  # Java 21 Corretto runtime. Update this value as new managed runtimes are released.
  runtime = "java21"

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  role = aws_iam_role.authorizer_lambda.arn

  # SnapStart reduces cold-start latency for Java Lambdas significantly.
  # "PublishedVersions" means SnapStart applies to every published version,
  # which is the configuration required for production use.
  snap_start {
    apply_on = "PublishedVersions"
  }

  # JVM tuning: tiered compilation improves warm-invocation throughput.
  # JAVA_TOOL_OPTIONS is the correct env var for Lambda Java runtimes (not _JAVA_OPTIONS).
  environment {
    variables = {
      AUTH0_DOMAIN      = var.auth0_domain
      AUTH0_AUDIENCE    = var.auth0_audience
      JAVA_TOOL_OPTIONS = "-XX:+TieredCompilation -XX:TieredStopAtLevel=1"
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.authorizer_lambda.id]
  }

  dynamic "tracing_config" {
    for_each = var.xray_tracing_enabled ? [1] : []
    content {
      mode = "Active"
    }
  }

  # Ensure the log group exists before the function is created, so the first
  # invocation does not auto-create a log group with infinite retention.
  depends_on = [aws_cloudwatch_log_group.authorizer_lambda]

  tags = {
    Name = "${var.environment}-jwt-authorizer"
  }
}

# Published version — required for SnapStart and for stable ARN references
# (e.g. if you add a Lambda alias for blue/green deployments later).
resource "aws_lambda_alias" "authorizer_live" {
  name             = "live"
  function_name    = aws_lambda_function.authorizer.function_name
  function_version = aws_lambda_function.authorizer.version
}

# ── IAM role — Lambda execution ───────────────────────────────────────────────

resource "aws_iam_role" "authorizer_lambda" {
  name               = "${var.environment}-jwt-authorizer-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Managed policy: VPC networking permissions (ENI create/delete) and basic
# CloudWatch Logs write access (CreateLogGroup is handled by the explicit
# log group resource — this policy covers PutLogEvents and CreateLogStream).
resource "aws_iam_role_policy_attachment" "authorizer_vpc_execution" {
  role       = aws_iam_role.authorizer_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# X-Ray write permissions — only attached when tracing is enabled.
resource "aws_iam_role_policy_attachment" "authorizer_xray" {
  count      = var.xray_tracing_enabled ? 1 : 0
  role       = aws_iam_role.authorizer_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# The Authorizer Lambda does not interact with DynamoDB — it only validates tokens.
# Business logic Lambdas in api-lambda/ carry their own scoped DynamoDB policies.
# No additional inline policies are needed here.

# ── Security group — Lambda Authorizer ───────────────────────────────────────

resource "aws_security_group" "authorizer_lambda" {
  name        = "${var.environment}-jwt-authorizer-sg"
  description = "Security group for the JWT Authorizer Lambda function"
  vpc_id      = var.vpc_id

  # No inbound rules — Lambda is invoked by the Lambda service, not directly.

  # Outbound: HTTPS to Auth0 JWKS endpoint (443) and AWS services via VPC endpoints.
  egress {
    description = "HTTPS outbound - Auth0 JWKS endpoint and AWS service endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-jwt-authorizer-sg"
  }
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
# Created explicitly so that retention is set from day one.
# Lambda would auto-create this group on first invocation with infinite retention
# if it does not already exist.

resource "aws_cloudwatch_log_group" "authorizer_lambda" {
  name              = "/aws/lambda/${var.environment}-jwt-authorizer"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.environment}-jwt-authorizer-logs"
  }
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

# Alert on any Lambda errors. In production, wire this to an SNS topic
# connected to PagerDuty, OpsGenie, or a Slack webhook.
resource "aws_cloudwatch_metric_alarm" "authorizer_errors" {
  alarm_name          = "${var.environment}-jwt-authorizer-errors"
  alarm_description   = "JWT Authorizer Lambda is producing errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.authorizer.function_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  # alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.environment}-jwt-authorizer-error-alarm"
  }
}

# Alert when the p99 duration of the Authorizer approaches the timeout threshold.
# An authorizer that routinely runs close to its timeout indicates JWKS cache
# misses or network latency to Auth0.
resource "aws_cloudwatch_metric_alarm" "authorizer_duration_p99" {
  alarm_name          = "${var.environment}-jwt-authorizer-duration-p99"
  alarm_description   = "JWT Authorizer p99 duration exceeds 80% of the configured timeout"
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  dimensions          = { FunctionName = aws_lambda_function.authorizer.function_name }
  extended_statistic  = "p99"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.lambda_timeout_seconds * 1000 * 0.8 # 80% of timeout in ms
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  # alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.environment}-jwt-authorizer-duration-alarm"
  }
}
