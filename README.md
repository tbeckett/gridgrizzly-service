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
