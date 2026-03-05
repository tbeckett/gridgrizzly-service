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
variable "allowed_egress_ips" {
  description = "The list of IP CIDR blocks for allowed egress traffic"
  type        = list(string)
  default = [
    # US
    "174.129.105.183/32", "18.116.79.126/32", "18.117.64.128/32", "18.191.46.63/32",
    "18.218.158.118/32", "18.218.26.94/32", "18.232.225.224/32", "18.233.90.226/32",
    "3.131.238.180/32", "3.131.55.63/32", "3.132.201.78/32", "3.133.18.220/32",
    "3.134.176.17/32", "3.19.44.88/32", "3.20.16.23/32", "3.20.244.231/32",
    "3.21.254.195/32", "3.211.189.167/32", "34.211.191.214/32", "34.233.19.82/32",
    "34.233.190.223/32", "35.160.3.103/32", "35.162.47.8/32", "35.166.202.113/32",
    "35.167.74.121/32", "35.171.156.124/32", "35.82.131.220/32", "44.205.93.104/32",
    "44.218.235.21/32", "44.219.52.110/32", "44.224.190.45/32", "44.246.144.93/32",
    "52.12.243.90/32", "52.14.149.14/32", "52.2.61.131/32", "52.204.128.250/32",
    "52.206.34.127/32", "52.33.36.223/32", "52.43.255.209/32", "52.88.192.232/32",
    "52.89.116.72/32", "54.145.227.59/32", "54.157.101.160/32", "54.200.12.78/32",
    "54.209.32.202/32", "54.245.16.146/32", "54.245.93.221/32", "54.68.157.8/32",
    "54.69.107.228/32"
  ]
}

resource "aws_security_group" "authorizer_lambda" {
  name        = "${var.environment}-jwt-authorizer-sg"
  description = "Security group for the JWT Authorizer Lambda function"
  vpc_id      = var.vpc_id

  # No inbound rules — Lambda is invoked by the Lambda service, not directly.

  # Outbound: HTTPS to Auth0 JWKS endpoint (443) restricted to Auth0 outbound IPs.
  egress {
    description = "HTTPS outbound - Auth0 JWKS endpoint"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_egress_ips
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
  kms_key_id        = aws_kms_key.cloudwatch_logs.arn

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
