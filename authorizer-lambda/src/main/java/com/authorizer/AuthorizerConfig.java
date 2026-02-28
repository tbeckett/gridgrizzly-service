package com.example.authorizer;

/**
 * Reads and validates all configuration from environment variables at cold-start time.
 * Failing fast here surfaces misconfiguration in Lambda logs immediately rather than
 * on the first live request.
 *
 * Required environment variables:
 *   AUTH0_DOMAIN   - e.g. "your-tenant.us.auth0.com"
 *   AUTH0_AUDIENCE - e.g. "https://api.yourapp.com"
 */
public record AuthorizerConfig(
        String auth0Domain,
        String auth0Audience,
        String jwksUri
) {
    private static final String ENV_DOMAIN   = "AUTH0_DOMAIN";
    private static final String ENV_AUDIENCE = "AUTH0_AUDIENCE";

    /**
     * Constructs config by reading environment variables. Throws at cold start if any
     * required variable is missing or blank, which immediately surfaces as a Lambda
     * initialisation error in CloudWatch Logs.
     */
    public static AuthorizerConfig fromEnvironment() {
        String domain   = requireEnv(ENV_DOMAIN);
        String audience = requireEnv(ENV_AUDIENCE);

        // Strip any trailing slash to produce a consistent base URL.
        if (domain.endsWith("/")) {
            domain = domain.substring(0, domain.length() - 1);
        }

        String jwksUri = "https://" + domain + "/.well-known/jwks.json";

        return new AuthorizerConfig(domain, audience, jwksUri);
    }

    private static String requireEnv(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(
                "Missing required environment variable: " + name
            );
        }
        return value.trim();
    }

    /** The Auth0 issuer claim, e.g. "https://your-tenant.us.auth0.com/" */
    public String issuer() {
        return "https://" + auth0Domain + "/";
    }
}
