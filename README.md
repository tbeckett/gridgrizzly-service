# GridGrizzly Service Layer

LambdaAuthorizer.java — The Lambda handler. It implements RequestHandler<APIGatewayCustomAuthorizerEvent, IamPolicyResponse> — the correct AWS type contract for a TOKEN type authorizer. Static fields hold the config and JWKS provider so they survive warm invocations. A second package-private constructor accepts injected collaborators specifically for unit testing without touching env vars.

## AuthorizerConfig.java
A Java 21 record that reads AUTH0_DOMAIN and AUTH0_AUDIENCE from environment variables at cold start and fails fast with a clear message if either is missing. Two env vars is all that's needed to deploy this to any environment.

## CachingJwksKeyProvider.java
Wraps Auth0's JwkProviderBuilder with a two-level protection strategy: an in-memory LRU cache (5 keys, 10-minute TTL) eliminates repeat JWKS fetches on warm invocations, and a rate limiter (10 fetches/minute) guards against thundering herds on burst cold starts or malicious key-rotation attacks.

## PolicyBuilder.java
Constructs the IAM policy document that API Gateway evaluates. The Allow policy uses a wildcard resource ARN (arn:aws:execute-api:*:*:*) so a single cached authorizer response covers the full API surface for a valid token. The context map is how the verified userId reaches downstream Lambda functions — read via event.getRequestContext().getAuthorizer().get("userId").

## LambdaAuthorizerTest.java
Eight unit tests covering the happy path, all header malformation cases, expired/wrong-issuer/wrong-audience tokens, a missing kid claim, and JWKS provider failure. Tests use a locally generated RSA key pair — no network calls, no env vars required.
pom.xml — Java 21, Maven Shade plugin to produce a fat JAR for Lambda deployment. Build with mvn clean package and deploy target/lambda-authorizer-1.0.0.jar.

## Setup

Ensure the AWS CLI is configured with a profile that has access to the target account.

If your AWS CLI has more than one profile, specify the desired profile using the 
--profile option. Otherwise, it can be omitted.

```
> ./bootstrap.sh --region us-east-1 --org gridgrizzly --profile <your-dev-profile>
```

Ensure that [Terraform is installed](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) and configured.
Update the backend block in main.tf
The S3 bucket name and DynamoDB table name in the backend "s3" block must match exactly what bootstrap.sh created. They follow the pattern <org>-terraform-state-<region> and <org>-terraform-locks. If you used a different org prefix, update these two values in main.tf before running terraform init.

### Create a VPC with private subnets
The Lambda Authorizer and DAX cluster run inside a VPC. If you do not already have a suitable VPC, create one with at least two private subnets across two availability zones (three for production). The subnet IDs go into private_subnet_ids in your tfvars and the VPC ID into vpc_id. The subnets must have a route to the internet (via a NAT Gateway) for the Authorizer Lambda to reach Auth0's JWKS endpoint on its first cold start or after cache expiry.

```
> cd infrastructure/terraform
> terraform init
```

### Set up OIDC for GitHub Actions
Rather than storing static AWS access keys as GitHub secrets, the deploy workflow assumes an IAM role via GitHub's OIDC provider. This requires a one-time setup in each AWS account:

In IAM → Identity Providers, create an OpenID Connect provider with the URL https://token.actions.githubusercontent.com and audience sts.amazonaws.com.
Create an IAM role for each environment (dev and prod). The trust policy should allow the GitHub OIDC provider to assume the role, scoped to your specific repository and the main branch:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:your-org/lambda-authorizer-service:ref:refs/heads/main"
      }
    }
  }]
}
```

Attach a permissions policy to each role that allows the Terraform operations it needs — at minimum, permissions to manage Lambda, API Gateway, DynamoDB, DAX, IAM roles, CloudWatch, and S3 state access. In practice this is a broad set; scope it as tightly as your team's workflow allows.
Record both role ARNs — they become the AWS_ROLE_ARN_DEV and AWS_ROLE_ARN_PROD GitHub secrets.


. Deployment Order
When doing this for the first time, the order matters:

Complete Auth0 setup first — you need the domain and audience before filling in tfvars.
Run bootstrap.sh to create remote state infrastructure.
Fill in tfvars files with real values.
Set up GitHub OIDC roles and add secrets to the repository.
Create GitHub Environments with appropriate protection rules.
Open a pull request — CI runs automatically. Merge when green.
The deploy-dev job runs automatically after merge. Review its output.
A reviewer approves the deploy-prod gate in the GitHub Actions UI.
deploy-prod runs and deploys to production.