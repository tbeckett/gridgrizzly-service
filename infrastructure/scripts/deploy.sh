#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Manual deployment script for local developer use
#
# Builds the Maven project, runs tests, and deploys the infrastructure to a
# target environment using Terraform. Intended for developer use outside of CI;
# CI/CD pipelines should use the GitHub Actions workflows in .github/workflows/.
#
# Prerequisites:
#   - AWS CLI v2 installed and on PATH, credentials configured
#   - Terraform >= 1.7 installed and on PATH
#   - Java 21 (Amazon Corretto recommended) and Maven 3.9+ installed
#   - jq installed
#   - bootstrap.sh has been run at least once for the target account
#
# Usage:
#   ./deploy.sh --env dev
#   ./deploy.sh --env prod --skip-tests
#   ./deploy.sh --env dev  --plan-only
#   ./deploy.sh --env dev  --profile my-aws-profile
#
# Flags:
#   --env          Target environment: dev or prod (required)
#   --skip-tests   Skip Maven test phase (not recommended for prod)
#   --plan-only    Run terraform plan but do not apply
#   --profile      AWS CLI profile to use
#   --help         Show this help message
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

# ── Resolve script root ───────────────────────────────────────────────────────
# Always run relative to the repository root regardless of where the script
# is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"
MAVEN_MODULE="${REPO_ROOT}/authorizer-lambda"
TF_DIR="${REPO_ROOT}/infrastructure/terraform"

# ── Defaults ──────────────────────────────────────────────────────────────────
ENV=""
SKIP_TESTS=false
PLAN_ONLY=false
AWS_PROFILE=""

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --env          Target environment: dev or prod (required)
  --skip-tests   Skip Maven test phase (strongly discouraged for prod)
  --plan-only    Run terraform plan but do not apply changes
  --profile      AWS CLI profile (optional; defaults to current environment)
  --help         Show this help message

Examples:
  $(basename "$0") --env dev
  $(basename "$0") --env prod --plan-only
  $(basename "$0") --env dev  --skip-tests --profile sandbox
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)         ENV="$2";        shift 2 ;;
    --skip-tests)  SKIP_TESTS=true; shift ;;
    --plan-only)   PLAN_ONLY=true;  shift ;;
    --profile)     AWS_PROFILE="$2";shift 2 ;;
    --help)        usage ;;
    *) die "Unknown argument: $1. Run with --help for usage." ;;
  esac
done

# ── Validation ────────────────────────────────────────────────────────────────
[[ -z "${ENV}" ]] && die "--env is required. Use: --env dev  or  --env prod"
[[ "${ENV}" =~ ^(dev|prod)$ ]] || die "--env must be 'dev' or 'prod', got: '${ENV}'"

TFVARS_FILE="${TF_DIR}/environments/${ENV}.tfvars"
[[ -f "${TFVARS_FILE}" ]] || die "tfvars file not found: ${TFVARS_FILE}"

# Guard: require explicit acknowledgement for production deploys.
if [[ "${ENV}" == "prod" && "${PLAN_ONLY}" == "false" ]]; then
  warn "You are about to deploy to PRODUCTION."
  warn "Ensure the dev environment has been validated first."
  echo ""
  read -rp "$(echo -e "${YELLOW}Type 'yes' to continue:${RESET} ")" PROD_CONFIRM
  [[ "${PROD_CONFIRM}" == "yes" ]] || { info "Aborted."; exit 0; }
fi

if [[ "${SKIP_TESTS}" == "true" && "${ENV}" == "prod" ]]; then
  warn "--skip-tests is set for a prod deploy. Tests will still run."
  warn "Remove this guard in deploy.sh only if you have a strong reason."
  SKIP_TESTS=false
fi

PROFILE_FLAG=""
[[ -n "${AWS_PROFILE}" ]] && PROFILE_FLAG="--profile ${AWS_PROFILE}"

# ── Dependency checks ─────────────────────────────────────────────────────────
header "Checking prerequisites"

command -v aws       &>/dev/null || die "aws CLI not found."
command -v terraform &>/dev/null || die "terraform not found. Install from https://developer.hashicorp.com/terraform/install"
command -v mvn       &>/dev/null || die "mvn not found. Install Maven 3.9+."
command -v java      &>/dev/null || die "java not found. Install Java 21 (Amazon Corretto recommended)."
command -v jq        &>/dev/null || die "jq not found."

JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d. -f1)
[[ "${JAVA_VERSION}" -ge 21 ]] 2>/dev/null \
  || warn "Java 21+ is required. Detected: $(java -version 2>&1 | head -1)"

TF_VERSION=$(terraform version -json | jq -r '.terraform_version')
info "Terraform  : ${TF_VERSION}"
info "Java       : $(java -version 2>&1 | head -1)"
info "Maven      : $(mvn -version | head -1)"
info "AWS CLI    : $(aws --version 2>&1)"

# ── AWS identity ──────────────────────────────────────────────────────────────
header "Resolving AWS identity"

IDENTITY=$(aws sts get-caller-identity ${PROFILE_FLAG} --output json 2>&1) \
  || die "Failed to resolve AWS identity. Check your credentials.\n${IDENTITY}"

ACCOUNT_ID=$(echo "${IDENTITY}" | jq -r '.Account')
CALLER_ARN=$(echo "${IDENTITY}" | jq -r '.Arn')

info "Account ID : ${ACCOUNT_ID}"
info "Caller ARN : ${CALLER_ARN}"
info "Environment: ${ENV}"
info "Plan only  : ${PLAN_ONLY}"
info "Skip tests : ${SKIP_TESTS}"

# ── Maven build ───────────────────────────────────────────────────────────────
header "Maven Build"

cd "${MAVEN_MODULE}"

MVN_GOALS="clean package"
MVN_FLAGS="-B -T 1C"

if [[ "${SKIP_TESTS}" == "true" ]]; then
  warn "Skipping tests as requested. The deployed JAR has not been verified by the test suite."
  MVN_FLAGS="${MVN_FLAGS} -DskipTests"
fi

info "Running: mvn ${MVN_FLAGS} ${MVN_GOALS}"
mvn ${MVN_FLAGS} ${MVN_GOALS}

# Resolve the exact JAR path produced by the shade plugin.
JAR_PATH=$(ls "${MAVEN_MODULE}/target/lambda-authorizer-"*.jar 2>/dev/null | head -1)
[[ -z "${JAR_PATH}" ]] && die "No shaded JAR found in ${MAVEN_MODULE}/target/. Did the Maven build succeed?"

JAR_SIZE=$(du -h "${JAR_PATH}" | cut -f1)
success "JAR built: $(basename "${JAR_PATH}") (${JAR_SIZE})"

# ── Terraform ─────────────────────────────────────────────────────────────────
header "Terraform — ${ENV}"

cd "${TF_DIR}"

# Export AWS profile for Terraform's AWS provider if one was specified.
[[ -n "${AWS_PROFILE}" ]] && export AWS_PROFILE="${AWS_PROFILE}"

info "Running: terraform init"
terraform init -reconfigure

info "Selecting workspace: ${ENV}"
# Create the workspace if it does not already exist.
terraform workspace select "${ENV}" 2>/dev/null \
  || terraform workspace new "${ENV}"

TF_PLAN_FILE="tfplan-${ENV}-$(date +%Y%m%d%H%M%S)"

info "Running: terraform plan"
terraform plan \
  -var-file="${TFVARS_FILE}" \
  -var="lambda_jar_path=${JAR_PATH}" \
  -out="${TF_PLAN_FILE}" \
  -no-color

if [[ "${PLAN_ONLY}" == "true" ]]; then
  success "Plan complete. No changes applied (--plan-only was set)."
  info "To apply this plan:"
  echo ""
  echo -e "  cd ${TF_DIR}"
  echo -e "  terraform apply ${TF_PLAN_FILE}"
  echo ""
  # Clean up the saved plan file — it is only valid for the current state version.
  rm -f "${TF_PLAN_FILE}"
  exit 0
fi

# ── Confirm before applying ───────────────────────────────────────────────────
echo ""
read -rp "$(echo -e "${YELLOW}Apply the plan above?${RESET} [y/N] ")" APPLY_CONFIRM
if [[ ! "${APPLY_CONFIRM:-N}" =~ ^[Yy]$ ]]; then
  info "Apply cancelled. Plan file removed."
  rm -f "${TF_PLAN_FILE}"
  exit 0
fi

# ── Terraform apply ───────────────────────────────────────────────────────────
header "Applying changes"

terraform apply "${TF_PLAN_FILE}"
rm -f "${TF_PLAN_FILE}"

success "Terraform apply complete."

# ── Outputs ───────────────────────────────────────────────────────────────────
header "Deployment Outputs"

terraform output

# ── Smoke test ────────────────────────────────────────────────────────────────
header "Smoke Test"

BASE_URL=$(terraform output -raw api_base_url 2>/dev/null) || {
  warn "Could not read api_base_url from Terraform outputs — skipping smoke test."
  exit 0
}

info "API base URL: ${BASE_URL}"
info "Sending unauthenticated request to ${BASE_URL}/fasteners..."

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  --max-time 10 \
  "${BASE_URL}/fasteners")

echo "HTTP status: ${HTTP_STATUS}"

if [[ "${HTTP_STATUS}" == "401" ]]; then
  success "Smoke test passed — Authorizer is live and rejecting unauthenticated requests."
elif [[ "${HTTP_STATUS}" == "403" ]]; then
  warn "Received 403 Forbidden. The Authorizer may be attached but the IAM policy may be misconfigured."
  warn "Check the Lambda Authorizer CloudWatch logs for details."
  exit 1
else
  error "Unexpected HTTP status: ${HTTP_STATUS}. Expected 401."
  error "Check API Gateway and Lambda Authorizer logs in CloudWatch."
  exit 1
fi

# ── Done ──────────────────────────────────────────────────────────────────────
header "Done"
success "Deployment to '${ENV}' complete."
echo ""
info "Useful commands:"
echo -e "  View Authorizer logs : aws logs tail /aws/lambda/${ENV}-jwt-authorizer --follow"
echo -e "  Terraform outputs    : cd ${TF_DIR} && terraform output"
echo -e "  Destroy environment  : cd ${TF_DIR} && terraform destroy -var-file=environments/${ENV}.tfvars"
echo ""
