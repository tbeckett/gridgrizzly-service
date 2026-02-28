# =============================================================================
# outputs.tf — Exported values for use by other Terraform workspaces,
#              CI/CD pipelines, and developer reference.
# =============================================================================

# ── API Gateway ───────────────────────────────────────────────────────────────

output "api_gateway_id" {
  description = "The ID of the REST API."
  value       = aws_api_gateway_rest_api.main.id
}

output "api_base_url" {
  description = "Base invocation URL for the deployed API stage, e.g. 'https://<id>.execute-api.us-east-1.amazonaws.com/v1'."
  value       = aws_api_gateway_stage.main.invoke_url
}

output "api_stage_name" {
  description = "The name of the deployed API Gateway stage."
  value       = aws_api_gateway_stage.main.stage_name
}

output "authorizer_id" {
  description = "The ID of the Lambda Authorizer. Reference this in method definitions for any additional Terraform-managed API methods."
  value       = aws_api_gateway_authorizer.jwt.id
}

# ── Lambda Authorizer ─────────────────────────────────────────────────────────

output "authorizer_lambda_arn" {
  description = "ARN of the JWT Authorizer Lambda function."
  value       = aws_lambda_function.authorizer.arn
}

output "authorizer_lambda_name" {
  description = "Name of the JWT Authorizer Lambda function."
  value       = aws_lambda_function.authorizer.function_name
}

output "authorizer_lambda_version" {
  description = "Published version of the JWT Authorizer Lambda function (used by SnapStart)."
  value       = aws_lambda_function.authorizer.version
}

output "authorizer_log_group_name" {
  description = "CloudWatch Log Group name for the Authorizer Lambda. Use this in log queries and CloudWatch Insights."
  value       = aws_cloudwatch_log_group.authorizer_lambda.name
}

# ── DynamoDB ──────────────────────────────────────────────────────────────────

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  value       = aws_dynamodb_table.main.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table. Use this in IAM policies for business logic Lambda functions."
  value       = aws_dynamodb_table.main.arn
}

output "dax_cluster_endpoint" {
  description = "DAX cluster endpoint. Null if DAX is not enabled. Configure this as the DynamoDB endpoint in business logic Lambda environment variables."
  value       = var.dynamodb_enable_dax ? aws_dax_cluster.main[0].cluster_address : null
}

output "dax_cluster_port" {
  description = "DAX cluster port (9111 for TLS). Null if DAX is not enabled."
  value       = var.dynamodb_enable_dax ? aws_dax_cluster.main[0].port : null
}

# ── Networking ────────────────────────────────────────────────────────────────

output "authorizer_security_group_id" {
  description = "Security group ID of the Authorizer Lambda. Reference this in DAX and other resource security group ingress rules."
  value       = aws_security_group.authorizer_lambda.id
}

output "dynamodb_vpc_endpoint_id" {
  description = "ID of the DynamoDB Gateway VPC endpoint."
  value       = aws_vpc_endpoint.dynamodb.id
}
