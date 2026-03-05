# =============================================================================
# dynamodb.tf — DynamoDB table, optional DAX cluster, and VPC endpoint
# =============================================================================

# ── DynamoDB table ────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "main" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST" # On-demand: no capacity planning required

  # Primary key design: user-scoped access pattern.
  # PK = userId  → all queries are anchored to the authenticated user
  # SK = resourceId → supports range queries and filtering within a user's data
  hash_key  = "userId"
  range_key = "resourceId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "resourceId"
    type = "S"
  }

  attribute {
    name = "fastenerId"
    type = "S"
  }

  # GSI: direct lookup of any fastener by its server-assigned ID.
  # The base table (PK=userId, SK=resourceId) covers the "query by user" pattern.
  global_secondary_index {
    name            = "fastenerId-index"
    hash_key        = "fastenerId"
    projection_type = "ALL"
  }

  # Point-in-time recovery: allows table restoration to any second within the
  # last 35 days. Essential for production; low cost relative to the risk of data loss.
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption using an AWS-managed key.
  # Switch server_side_encryption.kms_key_arn to a customer-managed KMS key
  # if your compliance requirements mandate key ownership and rotation control.
  server_side_encryption {
    enabled = true
  }

  # TTL: if your data model includes time-expiring records (e.g. sessions,
  # temporary tokens), enable TTL by setting the attribute name below.
  # DynamoDB will automatically delete items whose TTL attribute value is in the past.
  # ttl {
  #   attribute_name = "expiresAt"
  #   enabled        = true
  # }

  tags = {
    Name = var.dynamodb_table_name
  }
}

# ── VPC endpoint — DynamoDB ───────────────────────────────────────────────────
# Routes DynamoDB traffic from Lambda (running in the VPC) directly to DynamoDB
# over the AWS private network. No internet gateway or NAT gateway required for
# DynamoDB access. This is a Gateway endpoint — no hourly cost.

data "aws_route_tables" "private" {
  vpc_id = var.vpc_id

  filter {
    name   = "association.subnet-id"
    values = var.private_subnet_ids
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.private.ids

  tags = {
    Name = "${var.environment}-dynamodb-vpc-endpoint"
  }
}

# ── DAX cluster (conditional) ─────────────────────────────────────────────────
# Provisioned only when var.dynamodb_enable_dax = true.
# Disabled in dev to reduce cost; enabled in staging and prod.
# The DAX client in Lambda is a drop-in replacement for the DynamoDB client —
# no business logic changes are required when toggling this flag.

resource "aws_dax_subnet_group" "main" {
  count      = var.dynamodb_enable_dax ? 1 : 0
  name       = "${var.environment}-dax-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "dax" {
  count       = var.dynamodb_enable_dax ? 1 : 0
  name        = "${var.environment}-dax-sg"
  description = "Security group for the DAX cluster - allows inbound from Lambda security groups only"
  vpc_id      = var.vpc_id

  # DAX client port: 8111 (unencrypted) or 9111 (TLS).
  # Always use 9111 in production. The cluster encryption config below enforces TLS.
  ingress {
    description     = "DAX TLS from Lambda Authorizer"
    from_port       = 9111
    to_port         = 9111
    protocol        = "tcp"
    security_groups = [aws_security_group.authorizer_lambda.id]
  }

  # Add additional security group references here for each business logic Lambda
  # that needs DAX access, e.g.:
  # security_groups = [
  #   aws_security_group.authorizer_lambda.id,
  #   aws_security_group.api_lambda.id,
  # ]

  egress {
    description = "Outbound to DynamoDB via VPC endpoint"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-dax-sg"
  }
}

resource "aws_iam_role" "dax" {
  count              = var.dynamodb_enable_dax ? 1 : 0
  name               = "${var.environment}-dax-role"
  assume_role_policy = data.aws_iam_policy_document.dax_assume[0].json
}

data "aws_iam_policy_document" "dax_assume" {
  count = var.dynamodb_enable_dax ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dax.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "dax_dynamodb" {
  count  = var.dynamodb_enable_dax ? 1 : 0
  name   = "dax-dynamodb-access"
  role   = aws_iam_role.dax[0].id
  policy = data.aws_iam_policy_document.dax_dynamodb[0].json
}

data "aws_iam_policy_document" "dax_dynamodb" {
  count = var.dynamodb_enable_dax ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [
      aws_dynamodb_table.main.arn,
      "${aws_dynamodb_table.main.arn}/index/*",
    ]
  }
}

resource "aws_dax_cluster" "main" {
  count              = var.dynamodb_enable_dax ? 1 : 0
  cluster_name       = "${var.environment}-dax-cluster"
  node_type          = var.dax_node_type
  replication_factor = var.dax_node_count
  iam_role_arn       = aws_iam_role.dax[0].arn
  subnet_group_name  = aws_dax_subnet_group.main[0].name
  security_group_ids = [aws_security_group.dax[0].id]

  # Enforce TLS between Lambda (DAX client) and the cluster.
  # tls_enabled is separate from the encryption_at_rest block below.
  cluster_endpoint_encryption_type = "TLS"

  server_side_encryption {
    enabled = true
  }

  # Parameter group: increase the query cache size for workloads with high read
  # repetition. The default group is sufficient for most starting configurations.
  # parameter_group_name = aws_dax_parameter_group.main.name

  tags = {
    Name = "${var.environment}-dax-cluster"
  }

  depends_on = [aws_iam_role_policy.dax_dynamodb]
}
