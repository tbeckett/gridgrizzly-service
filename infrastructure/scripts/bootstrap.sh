#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — One-time Terraform remote state infrastructure setup
#
# Run this ONCE per AWS account before the first `terraform init`.
# It creates the S3 bucket and DynamoDB table that Terraform uses for
# remote state storage and state locking respectively.
#
# These resources are intentionally managed outside of Terraform — if they
# were managed by Terraform, a chicken-and-egg problem would prevent the
# first `terraform init` from succeeding.
#
# Prerequisites:
#   - AWS CLI v2 installed and on PATH
#   - Credentials configured for the target account (env vars, SSO, or profile)
#   - jq installed (used for output parsing)
#
# Usage:
#   ./bootstrap.sh --region us-east-1 --org my-org
#   ./bootstrap.sh --region eu-west-1 --org my-org --profile my-aws-profile
#
# Idempotent: safe to re-run. Existing resources are detected and skipped.
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}"; }

# ── Defaults ──────────────────────────────────────────────────────────────────
REGION="us-east-1"
ORG=""
AWS_PROFILE=""

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --region   AWS region to bootstrap (default: us-east-1)
  --org      Organisation or project prefix used in resource names (required)
  --profile  AWS CLI profile to use (optional; defaults to current environment)
  --help     Show this help message
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)   REGION="$2";      shift 2 ;;
    --org)      ORG="$2";         shift 2 ;;
    --profile)  AWS_PROFILE="$2"; shift 2 ;;
    --help)     usage ;;
    *) die "Unknown argument: $1. Run with --help for usage." ;;
  esac
done

[[ -z "${ORG}" ]] && die "--org is required. Example: --org my-company"

# Build the AWS CLI profile flag if a profile was supplied.
PROFILE_FLAG=""
[[ -n "${AWS_PROFILE}" ]] && PROFILE_FLAG="--profile ${AWS_PROFILE}"

# ── Dependency checks ─────────────────────────────────────────────────────────
header "Checking prerequisites"

command -v aws  &>/dev/null || die "aws CLI not found. Install from https://aws.amazon.com/cli/"
command -v jq   &>/dev/null || die "jq not found. Install with: brew install jq  OR  apt install jq"

AWS_VERSION=$(aws --version 2>&1 | awk '{print $1}')
info "AWS CLI: ${AWS_VERSION}"

# ── Resolve account identity ──────────────────────────────────────────────────
header "Resolving AWS identity"

IDENTITY=$(aws sts get-caller-identity ${PROFILE_FLAG} --output json 2>&1) \
  || die "Failed to call sts:GetCallerIdentity. Check your credentials.\n${IDENTITY}"

ACCOUNT_ID=$(echo "${IDENTITY}" | jq -r '.Account')
CALLER_ARN=$(echo "${IDENTITY}" | jq -r '.Arn')

# Resource names derived from org, account, and region.
# Account ID is included in the bucket name to guarantee global uniqueness —
# S3 bucket names are shared across all AWS accounts worldwide.
STATE_BUCKET="${ORG}-terraform-state-${ACCOUNT_ID}-${REGION}"
LOCK_TABLE="${ORG}-terraform-locks"

info "Account ID : ${ACCOUNT_ID}"
info "Caller ARN : ${CALLER_ARN}"
info "Region     : ${REGION}"
info ""
info "Will create:"
info "  S3 bucket      : ${STATE_BUCKET}"
info "  DynamoDB table : ${LOCK_TABLE}"

echo ""
read -rp "$(echo -e "${YELLOW}Proceed?${RESET} [y/N] ")" CONFIRM
[[ "${CONFIRM:-N}" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }

# ── S3 bucket — remote state storage ─────────────────────────────────────────
header "S3 State Bucket"

if aws s3api head-bucket --bucket "${STATE_BUCKET}" ${PROFILE_FLAG} 2>/dev/null; then
  warn "Bucket '${STATE_BUCKET}' already exists — skipping creation."
else
  info "Creating S3 bucket: ${STATE_BUCKET}"

  # us-east-1 requires no LocationConstraint — all other regions require one.
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "${STATE_BUCKET}" \
      --region "${REGION}" \
      ${PROFILE_FLAG} \
      --output json > /dev/null
  else
    aws s3api create-bucket \
      --bucket "${STATE_BUCKET}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}" \
      ${PROFILE_FLAG} \
      --output json > /dev/null
  fi

  success "Bucket created."
fi

# Block all public access — state files must never be publicly readable.
info "Enforcing public access block..."
aws s3api put-public-access-block \
  --bucket "${STATE_BUCKET}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  ${PROFILE_FLAG}
success "Public access blocked."

# Enable versioning — allows recovery of a previous state file if corruption occurs.
info "Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "${STATE_BUCKET}" \
  --versioning-configuration Status=Enabled \
  ${PROFILE_FLAG}
success "Versioning enabled."

# Enable server-side encryption with AES-256.
# Upgrade to aws:kms and provide a KMS key ARN for compliance-sensitive environments.
info "Enabling server-side encryption (AES-256)..."
aws s3api put-bucket-encryption \
  --bucket "${STATE_BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }' \
  ${PROFILE_FLAG}
success "Encryption enabled."

# Lifecycle rule: expire non-current (old) state versions after 90 days.
# Without this, every terraform apply accumulates a new version indefinitely.
info "Configuring lifecycle rule for non-current version expiry (90 days)..."
aws s3api put-bucket-lifecycle-configuration \
  --bucket "${STATE_BUCKET}" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "expire-old-state-versions",
      "Status": "Enabled",
      "Filter": { "Prefix": "" },
      "NoncurrentVersionExpiration": { "NoncurrentDays": 90 }
    }]
  }' \
  ${PROFILE_FLAG}
success "Lifecycle rule configured."

# Bucket policy: deny any request that is not encrypted in transit (HTTPS only).
info "Applying bucket policy (enforce HTTPS)..."
aws s3api put-bucket-policy \
  --bucket "${STATE_BUCKET}" \
  --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"DenyNonTLS\",
      \"Effect\": \"Deny\",
      \"Principal\": \"*\",
      \"Action\": \"s3:*\",
      \"Resource\": [
        \"arn:aws:s3:::${STATE_BUCKET}\",
        \"arn:aws:s3:::${STATE_BUCKET}/*\"
      ],
      \"Condition\": {
        \"Bool\": { \"aws:SecureTransport\": \"false\" }
      }
    }]
  }" \
  ${PROFILE_FLAG}
success "Bucket policy applied."

# ── DynamoDB table — state locking ────────────────────────────────────────────
header "DynamoDB Lock Table"

if aws dynamodb describe-table \
    --table-name "${LOCK_TABLE}" \
    --region "${REGION}" \
    ${PROFILE_FLAG} \
    --output json &>/dev/null; then
  warn "Table '${LOCK_TABLE}' already exists — skipping creation."
else
  info "Creating DynamoDB table: ${LOCK_TABLE}"

  # Terraform requires a table with a partition key named exactly "LockID" (type String).
  # On-demand billing: this table receives at most one write per terraform operation,
  # making on-demand far cheaper than any provisioned capacity.
  aws dynamodb create-table \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}" \
    ${PROFILE_FLAG} \
    --output json > /dev/null

  info "Waiting for table to become ACTIVE..."
  aws dynamodb wait table-exists \
    --table-name "${LOCK_TABLE}" \
    --region "${REGION}" \
    ${PROFILE_FLAG}

  success "Table created and active."
fi

# Enable point-in-time recovery on the lock table.
# Overkill for a lock table, but cheap and guards against accidental deletion.
info "Enabling point-in-time recovery..."
aws dynamodb update-continuous-backups \
  --table-name "${LOCK_TABLE}" \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
  --region "${REGION}" \
  ${PROFILE_FLAG} \
  --output json > /dev/null
success "Point-in-time recovery enabled."

# ── Summary ───────────────────────────────────────────────────────────────────
header "Bootstrap Complete"

success "Remote state infrastructure is ready."
echo ""
echo -e "  ${BOLD}S3 bucket${RESET}      : ${STATE_BUCKET}"
echo -e "  ${BOLD}DynamoDB table${RESET} : ${LOCK_TABLE}"
echo -e "  ${BOLD}Region${RESET}         : ${REGION}"
echo ""
info "Initialise Terraform with the generated backend config:"
echo ""
echo -e "  ${BOLD}cd infrastructure/terraform${RESET}"
echo -e "  ${BOLD}terraform init \\${RESET}"
echo -e "  ${BOLD}  -backend-config=\"bucket=${STATE_BUCKET}\" \\${RESET}"
echo ""
