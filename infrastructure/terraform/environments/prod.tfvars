# =============================================================================
# environments/prod.tfvars — Production environment variable values
#
# Usage:
#   terraform plan  -var-file=environments/prod.tfvars
#   terraform apply -var-file=environments/prod.tfvars
#
# Auth0 values point to the production tenant.
# DAX is enabled with a 3-node multi-AZ cluster.
# Throttle limits, retention, and memory are set for production workloads.
# Authorizer cache TTL is 300s — reduces Lambda invocations for valid tokens.
# =============================================================================

environment    = "prod"
aws_region     = "us-east-2"

# Auth0 — production tenant
auth0_domain   = "auth.gridgrizzly.com"
auth0_audience = "https://api.gridgrizly.com"

# Lambda
lambda_jar_path              = "../../authorizer-lambda/target/lambda-authorizer-1.0.0.jar"
lambda_memory_mb             = 512
lambda_timeout_seconds       = 10
authorizer_cache_ttl_seconds = 300   # 5-minute cache; covers JWTs with 1-hour expiry comfortably

# API Gateway
api_stage_name           = "v1"
api_throttle_rate_limit  = 100
api_throttle_burst_limit = 200

# DynamoDB
dynamodb_table_name  = "prod-app-data"
dynamodb_enable_dax  = true
dax_node_type        = "dax.t3.small"
dax_node_count       = 3   # Multi-AZ for production availability

# Networking — replace with actual VPC/subnet IDs from your production account
vpc_id             = "vpc-0abc1234prod0000"
private_subnet_ids = [
  "subnet-0abc1234prod0001",   # us-east-1a
  "subnet-0abc1234prod0002",   # us-east-1b
  "subnet-0abc1234prod0003",   # us-east-1c
]

# Observability
log_retention_days   = 90     # 90-day retention for compliance
xray_tracing_enabled = true
