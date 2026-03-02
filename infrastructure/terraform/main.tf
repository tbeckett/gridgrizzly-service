# =============================================================================
# main.tf — Provider configuration and backend
# =============================================================================
#
# Usage:
#   terraform init
#   terraform workspace new dev   # or staging / prod
#   terraform plan -var-file=environments/dev.tfvars
#   terraform apply -var-file=environments/dev.tfvars

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # Remote state in S3 with DynamoDB locking.
  # Bootstrap these resources once manually (or via a separate bootstrap script)
  # before running terraform init for the first time.
  # The bucket and table names follow the pattern: <org>-terraform-state-<region>
  backend "s3" {
    bucket         = "gridgrizzly-terraform-state-us-east-1"
    key            = "lambda-authorizer-service/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    # dynamodb_table   = "gridgrizzly-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  shared_config_files      = ["~/.aws/conf"]
  profile = "dev"

  default_tags {
    tags = {
      Project     = "lambda-authorizer-service"
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "lambda-authorizer-service"
    }
  }
}

# =============================================================================
# Data sources
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
