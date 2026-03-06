# =============================================================================
# variables.tf — Input variable declarations
#
# Values are supplied via environment-specific .tfvars files in environments/.
# Sensitive values (Auth0 secrets) are never stored in .tfvars — they are
# read from AWS Secrets Manager at Lambda runtime.
# =============================================================================

# ── Deployment context ────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy all resources into."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment name. Used in resource names and tags."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

# ── Auth0 ─────────────────────────────────────────────────────────────────────

variable "auth0_domain" {
  description = "Auth0 tenant domain, e.g. 'my-tenant.us.auth0.com'. Injected into the Lambda Authorizer as an environment variable."
  type        = string
}

variable "auth0_audience" {
  description = "Auth0 API audience identifier, e.g. 'https://api.myapp.com'. Must match the audience configured in the Auth0 API settings."
  type        = string
}

# ── Lambda ────────────────────────────────────────────────────────────────────

variable "lambda_jar_path" {
  description = "Local path to the shaded JAR produced by 'mvn package'. Example: '../../authorizer-lambda/target/lambda-authorizer-1.0.0.jar'."
  type        = string
}

variable "api_lambda_jar_path" {
  description = "Local path to the shaded api-lambda fat JAR (produced by mvn package in api-lambda/)"
  type        = string
}

variable "lambda_memory_mb" {
  description = "Memory allocated to the Lambda Authorizer in MB. 512 MB is sufficient for JWT validation workloads. Increase if cold-start latency is a concern."
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory_mb >= 128 && var.lambda_memory_mb <= 10240
    error_message = "lambda_memory_mb must be between 128 and 10240."
  }
}

variable "lambda_timeout_seconds" {
  description = "Maximum execution time for the Lambda Authorizer in seconds. Kept low — authorisation should be fast. API Gateway will time out the request if this is exceeded."
  type        = number
  default     = 10

  validation {
    condition     = var.lambda_timeout_seconds >= 1 && var.lambda_timeout_seconds <= 29
    error_message = "lambda_timeout_seconds must be between 1 and 29. API Gateway's own timeout is 29s."
  }
}

variable "authorizer_cache_ttl_seconds" {
  description = "How long API Gateway caches a successful Authorizer response (in seconds). Cached responses skip the Lambda invocation entirely, reducing cost and latency. 300s (5 minutes) is a sensible default for JWT expiry windows of 1 hour or more."
  type        = number
  default     = 300

  validation {
    condition     = var.authorizer_cache_ttl_seconds >= 0 && var.authorizer_cache_ttl_seconds <= 3600
    error_message = "authorizer_cache_ttl_seconds must be between 0 (disabled) and 3600."
  }
}

# ── API Gateway ───────────────────────────────────────────────────────────────

variable "api_stage_name" {
  description = "API Gateway deployment stage name, e.g. 'v1'."
  type        = string
  default     = "v1"
}

variable "api_throttle_rate_limit" {
  description = "API Gateway steady-state request rate limit (requests per second) applied at the stage level."
  type        = number
  default     = 100
}

variable "api_throttle_burst_limit" {
  description = "API Gateway burst request limit (maximum concurrent requests) applied at the stage level."
  type        = number
  default     = 200
}

variable "api_cache_enabled" {
  description = "Whether to enable API Gateway response caching. Disable in dev to avoid the per-hour cache cluster cost."
  type        = bool
  default     = false
}

variable "api_cache_size_gb" {
  description = "Size of the API Gateway cache cluster in GB. Valid values: 0.5, 1.6, 6.1, 13.5, 28.4, 58.2, 118, 237."
  type        = string
  default     = "0.5"

  validation {
    condition     = contains(["0.5", "1.6", "6.1", "13.5", "28.4", "58.2", "118", "237"], var.api_cache_size_gb)
    error_message = "api_cache_size_gb must be one of the valid API Gateway cache cluster sizes."
  }
}


variable "api_cache_ttl_seconds" {
  description = "Default TTL in seconds for cached API Gateway responses."
  type        = number
  default     = 300

  validation {
    condition     = var.api_cache_ttl_seconds >= 0 && var.api_cache_ttl_seconds <= 3600
    error_message = "api_cache_ttl_seconds must be between 0 and 3600."
  }
}

# ── DynamoDB ──────────────────────────────────────────────────────────────────

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table used by business logic Lambda functions."
  type        = string
}

variable "dynamodb_enable_dax" {
  description = "Whether to provision a DAX cluster in front of DynamoDB. Set to false for dev environments to reduce cost."
  type        = bool
  default     = false
}

variable "dax_node_type" {
  description = "DAX node instance type. dax.t3.small is cost-effective for low-to-moderate workloads."
  type        = string
  default     = "dax.t3.small"
}

variable "dax_node_count" {
  description = "Number of DAX nodes. 1 for dev/staging; 3 (multi-AZ) for production."
  type        = number
  default     = 1

  validation {
    condition     = var.dax_node_count >= 1 && var.dax_node_count <= 10
    error_message = "dax_node_count must be between 1 and 10."
  }
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vpc_id" {
  description = "ID of the VPC in which Lambda and DAX will run."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for Lambda and DAX placement. Use subnets across multiple AZs in production."
  type        = list(string)
}

# ── Observability ─────────────────────────────────────────────────────────────

variable "application_log_level" {
  description = "Log level applied to application_log_level in the Lambda logging_config block. Must be a value accepted by both: DEBUG, INFO, or WARN."
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"], var.log_level)
    error_message = "application_log_level must be one of: TRACE, DEBUG, INFO, WARN, ERROR, FATAL."
  }
}

variable "system_log_level" {
  description = "Log level applied to system_log_level in the Lambda logging_config block."
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARN"], var.log_level)
    error_message = "system_log_level must be one of: DEBUG, INFO, WARN."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Log Group retention period in days."
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value accepted by CloudWatch Logs."
  }
}

variable "xray_tracing_enabled" {
  description = "Whether to enable AWS X-Ray active tracing on Lambda functions and API Gateway."
  type        = bool
  default     = true
}
