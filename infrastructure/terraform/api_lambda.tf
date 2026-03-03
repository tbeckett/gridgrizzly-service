# =============================================================================
# api_lambda.tf — Business logic Lambda functions
# =============================================================================

# ── GET /fasteners Lambda ─────────────────────────────────────────────────────

resource "aws_lambda_function" "fasteners_api" {
  function_name = "${var.environment}-fasteners-api"
  description   = "Returns a list of fasteners"

  filename         = var.lambda_jar_path
  source_code_hash = filebase64sha256(var.lambda_jar_path)

  handler = "com.gridgrizzly.api.FastenersHandler::handleRequest"
  runtime = "java21"

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  role = aws_iam_role.fasteners_lambda.arn

  depends_on = [aws_cloudwatch_log_group.fasteners_lambda]

  tags = {
    Name = "${var.environment}-fasteners-api"
  }
}

# ── IAM role ──────────────────────────────────────────────────────────────────

resource "aws_iam_role" "fasteners_lambda" {
  name               = "${var.environment}-fasteners-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "fasteners_basic_execution" {
  role       = aws_iam_role.fasteners_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "fasteners_lambda" {
  name              = "/aws/lambda/${var.environment}-fasteners-api"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.environment}-fasteners-api-logs"
  }
}
