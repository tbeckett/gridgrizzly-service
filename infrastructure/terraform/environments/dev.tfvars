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
aws_region     = "us-east-2"

# Auth0 — dev tenant
auth0_domain   = "auth0.gridgrizzly.com"
auth0_audience = "https://api.gridgrizzly.com"

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
vpc_id             = "vpc-0b53f2432a066aeda"
private_subnet_ids = ["subnet-0dbb14f9c04f9678f", "subnet-0de603c248d1996cc"]

# Observability
log_retention_days   = 7      # Short retention in dev
xray_tracing_enabled = true
