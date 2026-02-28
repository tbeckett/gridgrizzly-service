# =============================================================================
# environments/dev.tfvars — Development environment variable values
#
# Usage:
#   terraform plan  -var-file=environments/dev.tfvars
#   terraform apply -var-file=environments/dev.tfvars
#
# Auth0 values point to a dedicated dev tenant.
# DAX is disabled to reduce cost. Throttle limits are relaxed.
# Log retention is short. All other settings favour cost over resilience.
# =============================================================================

environment    = "dev"
aws_region     = "us-east-1"

# Auth0 — dev tenant
auth0_domain   = "my-org-dev.us.auth0.com"
auth0_audience = "https://api.dev.myapp.com"

# Lambda
lambda_jar_path            = "../../authorizer-lambda/target/lambda-authorizer-1.0.0.jar"
lambda_memory_mb           = 512
lambda_timeout_seconds     = 10
authorizer_cache_ttl_seconds = 0   # Disabled in dev — every request hits the Authorizer

# API Gateway
api_stage_name           = "v1"
api_throttle_rate_limit  = 50
api_throttle_burst_limit = 100

# DynamoDB
dynamodb_table_name  = "dev-app-data"
dynamodb_enable_dax  = false   # DAX off in dev

# Networking — replace with actual VPC/subnet IDs from your dev account
vpc_id             = "vpc-0abc1234dev00000"
private_subnet_ids = ["subnet-0abc1234dev00001", "subnet-0abc1234dev00002"]

# Observability
log_retention_days   = 7      # Short retention in dev
xray_tracing_enabled = true
