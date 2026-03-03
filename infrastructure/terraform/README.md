## main.tf
Provider config and S3 remote backend. default_tags on the provider block means every resource automatically inherits Project, Environment, and ManagedBy tags without repeating them. Two data sources (aws_caller_identity, aws_region) are available to all other files for dynamic ARN construction.

## variables.tf
Every configurable value is declared here with a description, type, default where sensible, and a validation block where the value space is bounded. The environment variable uses a validation to prevent typos from creating orphaned resources. The Auth0 variables are plain strings — no sensitive = true because they are not secrets (the domain and audience are public values embedded in every JWT). Actual secrets live in Secrets Manager.

## api_gateway.tf
Uses the TOKEN authorizer type, which is correct for Authorization: Bearer header validation. The triggers map on aws_api_gateway_deployment is a well-known Terraform pattern to force a redeployment when any upstream resource changes — without it, API Gateway deployments don't automatically update when method or authorizer definitions change. Throttling is applied at both the stage level (via aws_api_gateway_method_settings) and the Usage Plan level, which is the correct two-layer approach.

## lambda_authorizer.tf
snap_start is enabled and set to PublishedVersions, which is the configuration required for it to actually take effect — enabling SnapStart without publishing a version has no impact. The security group allows outbound 443 only, which covers both Auth0's JWKS endpoint and AWS service endpoints via VPC. CloudWatch alarms are wired for both error rate and p99 duration — the duration alarm is specifically calibrated to catch JWKS cache miss latency before it becomes a timeout.

## dynamodb.tf
The entire DAX block is conditional on var.dynamodb_enable_dax using count = var.dynamodb_enable_dax ? 1 : 0. The DynamoDB VPC endpoint is a Gateway type (free) rather than Interface type (hourly charge), which is the correct choice for DynamoDB. DAX uses port 9111 (TLS) not 8111 (plain) — enforced in both the security group ingress rule and the cluster_endpoint_encryption_type setting.

## environments/dev.tfvars and prod.tfvars
authorizer_cache_ttl_seconds = 0 in dev disables the Authorizer cache so every request validates against Auth0 — essential for testing token changes during development. Production sets 300 seconds. DAX is off in dev, 3-node multi-AZ in prod. The subnet IDs are clearly marked as placeholders.
