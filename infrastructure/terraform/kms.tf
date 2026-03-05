# =============================================================================
# kms.tf — Customer-managed KMS keys
# =============================================================================

# ── CloudWatch Logs CMK ───────────────────────────────────────────────────────
# CloudWatch Logs requires explicit key policy grants — the default key policy
# alone is not sufficient. The logs service principal must be allowed to use
# the key on behalf of the account.

data "aws_iam_policy_document" "cloudwatch_logs_kms" {
  # Allow the account root full control (required for all CMKs).
  statement {
    sid     = "EnableRootAccess"
    effect  = "Allow"
    actions = ["kms:*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    resources = ["*"]
  }

  # Allow CloudWatch Logs to encrypt and decrypt log data using this key.
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_kms_key" "cloudwatch_logs" {
  description             = "CMK for CloudWatch Log Group encryption (${var.environment})"
  deletion_window_in_days = 14
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.cloudwatch_logs_kms.json

  tags = {
    Name = "${var.environment}-cloudwatch-logs-cmk"
  }
}

resource "aws_kms_alias" "cloudwatch_logs" {
  name          = "alias/${var.environment}-cloudwatch-logs"
  target_key_id = aws_kms_key.cloudwatch_logs.key_id
}
