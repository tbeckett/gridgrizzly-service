package com.gridgrizzly.authorizer;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayCustomAuthorizerEvent;
import com.amazonaws.services.lambda.runtime.events.IamPolicyResponse;
import com.auth0.jwt.JWT;
import com.auth0.jwt.JWTVerifier;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.exceptions.JWTVerificationException;
import com.auth0.jwt.interfaces.DecodedJWT;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.MalformedURLException;
import java.security.interfaces.RSAPublicKey;

/**
 * AWS Lambda Authorizer for API Gateway.
 * <p/>
 * Invocation flow
 * ───────────────
 * 1. API Gateway receives a request with an "Authorization: Bearer <token>" header.
 * 2. API Gateway invokes this Lambda before routing to any business logic function.
 * 3. This handler validates the JWT against Auth0's JWKS public keys.
 * 4. On success → returns an Allow IAM policy with the userId in the context map.
 *    On failure → throws RuntimeException("Unauthorized") which API Gateway maps to 401.
 * <p/>
 * Cold-start vs. warm invocation
 * ─────────────────────────────
 * The static initialiser block runs once per execution environment (cold start).
 * It reads environment variables, constructs the config, and creates the JWKS
 * key provider with its in-memory cache. All subsequent warm invocations reuse
 * these static instances — no re-initialisation or network calls until the
 * JWKS cache TTL expires (10 minutes).
 * <p/>
 * Lambda handler configuration
 * ─────────────────────────────
 * Set the Lambda handler to:
 *   com.example.authorizer.LambdaAuthorizer::handleRequest
 * <p/>
 * Required environment variables:
 *   AUTH0_DOMAIN   - your Auth0 tenant domain, e.g. "your-tenant.us.auth0.com"
 *   AUTH0_AUDIENCE - the API identifier registered in Auth0, e.g. <a href="https://api.yourapp.com">https://api.yourapp.com</a>
 */
public class LambdaAuthorizer
        implements RequestHandler<APIGatewayCustomAuthorizerEvent, IamPolicyResponse> {

    private static final Logger log = LoggerFactory.getLogger(LambdaAuthorizer.class);

    // ── Instance fields — initialised once at cold start, reused on warm invocations ──
    private final AuthorizerConfig config;
    private final JwksKeyProvider  jwksProvider;

    /** Production constructor — used by the Lambda runtime. */
    public LambdaAuthorizer() {
        log.info("Lambda Authorizer cold start — initialising config and JWKS provider");
        this.config = AuthorizerConfig.fromEnvironment();
        try {
            this.jwksProvider = new CachingJwksKeyProvider(this.config);
        } catch (MalformedURLException mue) {
            throw new RuntimeException("Failed to create CachingJwksKeyProvider.", mue);
        }
        log.info("Initialisation complete. Issuer={}, Audience={}",
                this.config.issuer(), this.config.auth0Audience());
    }

    /**
     * Package-private constructor for unit testing.
     * Allows injection of mock collaborators without an env-var dependency.
     */
    LambdaAuthorizer(AuthorizerConfig config, JwksKeyProvider jwksProvider) {
        this.config       = config;
        this.jwksProvider = jwksProvider;
    }

    // ─────────────────────────────────────────────────────────────────────────

    @Override
    public IamPolicyResponse handleRequest(
            APIGatewayCustomAuthorizerEvent event,
            Context context
    ) {
        String methodArn = event.getMethodArn();
        log.info("Authorizer invoked. methodArn={}", methodArn);

        String token = extractBearerToken(event);

        try {
            String userId = validateToken(token);
            log.info("Token valid. userId={} methodArn={}", userId, methodArn);
            return PolicyBuilder.allow(userId, methodArn);

        } catch (JWTVerificationException e) {
            // JWT is structurally valid but failed signature/claim checks.
            // Throwing RuntimeException("Unauthorized") causes API Gateway to return 401.
            log.warn("JWT verification failed: {}", e.getMessage());
            throw new RuntimeException("Unauthorized");

        } catch (Exception e) {
            // Unexpected error (e.g. JWKS network failure). Log fully; return 401.
            // Never expose internal error details to the caller.
            log.error("Unexpected error during authorisation", e);
            throw new RuntimeException("Unauthorized");
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Token extraction
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Extracts the raw JWT string from the Authorization header.
     * Throws immediately (producing a 401) if the header is absent or malformed.
     */
    private String extractBearerToken(APIGatewayCustomAuthorizerEvent event) {
        String authHeader = event.getAuthorizationToken();

        if (authHeader == null || authHeader.isBlank()) {
            log.warn("Missing Authorization header");
            throw new RuntimeException("Unauthorized");
        }

        // Expected format: "Bearer <token>"
        String[] parts = authHeader.split(" ", 2);
        if (parts.length != 2 || !"Bearer".equalsIgnoreCase(parts[0]) || parts[1].isBlank()) {
            log.warn("Malformed Authorization header — expected 'Bearer <token>'");
            throw new RuntimeException("Unauthorized");
        }

        return parts[1].trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // JWT validation
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Validates the JWT and returns the verified userId.
     * <p/>
     * Validation steps performed by the Auth0 java-jwt library:
     *   1. Decode the token and extract the "kid" (key ID) from the header.
     *   2. Fetch the matching RSA public key from the JWKS provider (cached).
     *   3. Verify the RS256 signature.
     *   4. Verify "iss" (issuer) matches the configured Auth0 domain.
     *   5. Verify "aud" (audience) contains the configured API identifier.
     *   6. Verify "exp" (expiry) has not passed.
     * <p/>
     * @param token the raw JWT string extracted from the Authorization header
     * @return the "sub" claim value — the unique userId from Auth0
     * @throws Exception on any validation failure or key-fetch error
     */
    private String validateToken(String token) throws Exception {
        // Decode without verification first — only to read the "kid" header claim.
        // Cryptographic verification happens in the verifier below.
        DecodedJWT unverified = JWT.decode(token);
        String keyId = unverified.getKeyId();

        if (keyId == null || keyId.isBlank()) {
            throw new JWTVerificationException("JWT is missing 'kid' header claim");
        }

        RSAPublicKey publicKey = (RSAPublicKey) jwksProvider.getPublicKey(keyId);
        Algorithm algorithm = Algorithm.RSA256(publicKey, null);

        JWTVerifier verifier = JWT.require(algorithm)
                .withIssuer(config.issuer())
                .withAudience(config.auth0Audience())
                .build();

        DecodedJWT verified = verifier.verify(token);

        String userId = verified.getSubject();
        if (userId == null || userId.isBlank()) {
            throw new JWTVerificationException("JWT 'sub' claim is missing or empty");
        }

        return userId;
    }
}
