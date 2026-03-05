# =============================================================================
# kms.tf — Customer-managed KMS keys
# =============================================================================

# ── CloudWatch Logs CMK ───────────────────────────────────────────────────────
# CloudWatch Logs requires explicit key policy grants — the default key policy
# alone is not sufficient. The logs service principal must be allowed to use
# the key on behalf of the account.

resource "aws_kms_key" "cloudwatch_logs" {
  description             = "CMK for CloudWatch Log Group encryption (${var.environment})"
  deletion_window_in_days = 14
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-cloudwatch-logs-cmk"
  }
}

resource "aws_kms_alias" "cloudwatch_logs" {
  name          = "alias/${var.environment}-cloudwatch-logs"
  target_key_id = aws_kms_key.cloudwatch_logs.key_id
}
