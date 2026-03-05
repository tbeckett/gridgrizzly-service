# =============================================================================
# api_lambda.tf — Business logic Lambda functions
# =============================================================================

# ── GET /fasteners Lambda ─────────────────────────────────────────────────────

resource "aws_lambda_function" "fasteners_api" {
  function_name = "${var.environment}-fasteners-api"
  description   = "Returns a list of fasteners"

  filename         = var.api_lambda_jar_path
  source_code_hash = filebase64sha256(var.api_lambda_jar_path)

  handler = "com.gridgrizzly.api.FastenersHandler::handleRequest"
  runtime = "java21"

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  role = aws_iam_role.fasteners_lambda.arn

  dynamic "tracing_config" {
    for_each = var.xray_tracing_enabled ? [1] : []
    content {
      mode = "Active"
    }
  }

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

resource "aws_iam_role_policy_attachment" "fasteners_xray" {
  role       = aws_iam_role.fasteners_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "fasteners_lambda" {
  name              = "/aws/lambda/${var.environment}-fasteners-api"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.environment}-fasteners-api-logs"
  }
}

# =============================================================================
# POST /fasteners — CreateFastenerHandler
# =============================================================================

resource "aws_lambda_function" "create_fastener" {
  function_name = "${var.environment}-create-fastener"
  description   = "Validates and persists a new fastener, associated with the authenticated user"

  filename         = var.api_lambda_jar_path
  source_code_hash = filebase64sha256(var.api_lambda_jar_path)

  handler = "com.gridgrizzly.api.CreateFastenerHandler::handleRequest"
  runtime = "java21"

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  role = aws_iam_role.create_fastener_lambda.arn

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
    }
  }

  dynamic "tracing_config" {
    for_each = var.xray_tracing_enabled ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [aws_cloudwatch_log_group.create_fastener_lambda]

  tags = {
    Name = "${var.environment}-create-fastener"
  }
}

# ── IAM role ──────────────────────────────────────────────────────────────────

resource "aws_iam_role" "create_fastener_lambda" {
  name               = "${var.environment}-create-fastener-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "create_fastener_basic_execution" {
  role       = aws_iam_role.create_fastener_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "create_fastener_xray" {
  role       = aws_iam_role.create_fastener_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "create_fastener_dynamodb" {
  name   = "dynamodb-put-fastener"
  role   = aws_iam_role.create_fastener_lambda.id
  policy = data.aws_iam_policy_document.create_fastener_dynamodb.json
}

data "aws_iam_policy_document" "create_fastener_dynamodb" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.main.arn]
  }
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "create_fastener_lambda" {
  name              = "/aws/lambda/${var.environment}-create-fastener"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.environment}-create-fastener-logs"
  }
}

# =============================================================================
# GET /fasteners/{id} — GetFastenerHandler
# =============================================================================

resource "aws_lambda_function" "get_fastener" {
  function_name = "${var.environment}-get-fastener"
  description   = "Retrieves a specific fastener by ID for the authenticated user"

  filename         = var.api_lambda_jar_path
  source_code_hash = filebase64sha256(var.api_lambda_jar_path)

  handler = "com.gridgrizzly.api.GetFastenerHandler::handleRequest"
  runtime = "java21"

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  role = aws_iam_role.get_fastener_lambda.arn

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
    }
  }

  dynamic "tracing_config" {
    for_each = var.xray_tracing_enabled ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [aws_cloudwatch_log_group.get_fastener_lambda]

  tags = {
    Name = "${var.environment}-get-fastener"
  }
}

resource "aws_iam_role" "get_fastener_lambda" {
  name               = "${var.environment}-get-fastener-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "get_fastener_basic_execution" {
  role       = aws_iam_role.get_fastener_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "get_fastener_xray" {
  role       = aws_iam_role.get_fastener_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "get_fastener_dynamodb" {
  name   = "dynamodb-query-fastener-by-id"
  role   = aws_iam_role.get_fastener_lambda.id
  policy = data.aws_iam_policy_document.get_fastener_dynamodb.json
}

data "aws_iam_policy_document" "get_fastener_dynamodb" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:Query"]
    resources = ["${aws_dynamodb_table.main.arn}/index/fastenerId-index"]
  }
}

resource "aws_cloudwatch_log_group" "get_fastener_lambda" {
  name              = "/aws/lambda/${var.environment}-get-fastener"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.environment}-get-fastener-logs"
  }
}

# =============================================================================
# DELETE /fasteners/{id} — DeleteFastenerHandler
# =============================================================================

resource "aws_lambda_function" "delete_fastener" {
  function_name = "${var.environment}-delete-fastener"
  description   = "Deletes a specific fastener owned by the authenticated user"

  filename         = var.api_lambda_jar_path
  source_code_hash = filebase64sha256(var.api_lambda_jar_path)

  handler = "com.gridgrizzly.api.DeleteFastenerHandler::handleRequest"
  runtime = "java21"

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  role = aws_iam_role.delete_fastener_lambda.arn

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
    }
  }

  dynamic "tracing_config" {
    for_each = var.xray_tracing_enabled ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [aws_cloudwatch_log_group.delete_fastener_lambda]

  tags = {
    Name = "${var.environment}-delete-fastener"
  }
}

resource "aws_iam_role" "delete_fastener_lambda" {
  name               = "${var.environment}-delete-fastener-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "delete_fastener_basic_execution" {
  role       = aws_iam_role.delete_fastener_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "delete_fastener_xray" {
  role       = aws_iam_role.delete_fastener_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "delete_fastener_dynamodb" {
  name   = "dynamodb-delete-fastener"
  role   = aws_iam_role.delete_fastener_lambda.id
  policy = data.aws_iam_policy_document.delete_fastener_dynamodb.json
}

data "aws_iam_policy_document" "delete_fastener_dynamodb" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:Query"]
    resources = ["${aws_dynamodb_table.main.arn}/index/fastenerId-index"]
  }
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.main.arn]
  }
}

resource "aws_cloudwatch_log_group" "delete_fastener_lambda" {
  name              = "/aws/lambda/${var.environment}-delete-fastener"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.environment}-delete-fastener-logs"
  }
}

# =============================================================================
# PUT /fasteners/{id} — UpdateFastenerHandler
# =============================================================================

resource "aws_lambda_function" "update_fastener" {
  function_name = "${var.environment}-update-fastener"
  description   = "Replaces a specific fastener owned by the authenticated user"

  filename         = var.api_lambda_jar_path
  source_code_hash = filebase64sha256(var.api_lambda_jar_path)

  handler = "com.gridgrizzly.api.UpdateFastenerHandler::handleRequest"
  runtime = "java21"

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  role = aws_iam_role.update_fastener_lambda.arn

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
    }
  }

  dynamic "tracing_config" {
    for_each = var.xray_tracing_enabled ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [aws_cloudwatch_log_group.update_fastener_lambda]

  tags = {
    Name = "${var.environment}-update-fastener"
  }
}

resource "aws_iam_role" "update_fastener_lambda" {
  name               = "${var.environment}-update-fastener-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "update_fastener_basic_execution" {
  role       = aws_iam_role.update_fastener_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "update_fastener_xray" {
  role       = aws_iam_role.update_fastener_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "update_fastener_dynamodb" {
  name   = "dynamodb-update-fastener"
  role   = aws_iam_role.update_fastener_lambda.id
  policy = data.aws_iam_policy_document.update_fastener_dynamodb.json
}

data "aws_iam_policy_document" "update_fastener_dynamodb" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:Query"]
    resources = ["${aws_dynamodb_table.main.arn}/index/fastenerId-index"]
  }
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.main.arn]
  }
}

resource "aws_cloudwatch_log_group" "update_fastener_lambda" {
  name              = "/aws/lambda/${var.environment}-update-fastener"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.environment}-update-fastener-logs"
  }
}
