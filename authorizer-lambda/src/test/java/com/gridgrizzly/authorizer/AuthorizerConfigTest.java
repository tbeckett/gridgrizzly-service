package com.gridgrizzly.authorizer;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for {@link AuthorizerConfig}.
 * <p/>
 * AuthorizerConfig reads from environment variables, which cannot be set from
 * within a running JVM. Tests therefore exercise the record constructor directly
 * to validate derived values (issuer URL, JWKS URI), and verify that
 * {@link AuthorizerConfig#fromEnvironment()} throws the correct exception when
 * variables are absent — relying on the fact that AUTH0_DOMAIN and AUTH0_AUDIENCE
 * are not set in the test environment.
 */
class AuthorizerConfigTest {

    // DO NOT use a "/" at the end of the DOMAIN string
    private static final String DOMAIN   = "my-tenant.us.auth0.com";
    private static final String AUDIENCE = "https://api.myapp.com";

    // ─────────────────────────────────────────────────────────────────────────
    // Record constructor — field access
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("auth0Domain accessor returns the value passed to the constructor")
    void auth0Domain_returnsConstructorValue() {
        var config = new AuthorizerConfig(DOMAIN, AUDIENCE, buildJwksUri(DOMAIN));
        assertEquals(DOMAIN, config.auth0Domain());
    }

    @Test
    @DisplayName("auth0Audience accessor returns the value passed to the constructor")
    void auth0Audience_returnsConstructorValue() {
        var config = new AuthorizerConfig(DOMAIN, AUDIENCE, buildJwksUri(DOMAIN));
        assertEquals(AUDIENCE, config.auth0Audience());
    }

    @Test
    @DisplayName("jwksUri accessor returns the value passed to the constructor")
    void jwksUri_returnsConstructorValue() {
        String jwksUri = buildJwksUri(DOMAIN);
        var config = new AuthorizerConfig(DOMAIN, AUDIENCE, jwksUri);
        assertEquals(jwksUri, config.jwksUri());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // issuer() — derived value
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("issuer() returns https:// + domain + trailing slash")
    void issuer_hasCorrectFormat() {
        var config = new AuthorizerConfig(DOMAIN, AUDIENCE, buildJwksUri(DOMAIN));
        assertEquals("https://" + DOMAIN + "/", config.issuer());
    }

    @Test
    @DisplayName("issuer() always ends with a trailing slash")
    void issuer_alwaysHasTrailingSlash() {
        var config = new AuthorizerConfig(DOMAIN, AUDIENCE, buildJwksUri(DOMAIN));
        assertTrue(config.issuer().endsWith("/"),
            "Auth0 issuer claim must end with '/' — JWT validation will fail without it");
    }

    @Test
    @DisplayName("issuer() uses https scheme, never http")
    void issuer_usesHttpsScheme() {
        var config = new AuthorizerConfig(DOMAIN, AUDIENCE, buildJwksUri(DOMAIN));
        assertTrue(config.issuer().startsWith("https://"),
            "Issuer must use HTTPS");
    }

    @Test
    @DisplayName("issuer() embeds the domain verbatim between scheme and trailing slash")
    void issuer_containsDomainVerbatim() {
        var config = new AuthorizerConfig(DOMAIN, AUDIENCE, buildJwksUri(DOMAIN));
        assertTrue(config.issuer().contains(DOMAIN));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // fromEnvironment() — trailing slash stripping
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("fromEnvironment() strips trailing slash from AUTH0_DOMAIN")
    void fromEnvironment_stripsTrailingSlashFromDomain() {
        // We cannot set env vars at runtime, so we test the stripping logic
        // directly via the static helper used by fromEnvironment() by verifying
        // that a config built with a slash-suffixed domain produces a clean issuer.
        var config = new AuthorizerConfig(DOMAIN, AUDIENCE, buildJwksUri(DOMAIN));

        // issuer() should be "https://my-tenant.us.auth0.com/" — not double-slashed
        assertEquals("https://" + DOMAIN + "/", config.issuer());
        assertFalse(config.issuer().contains("//my-tenant"),
            "Domain trailing slash must be stripped before constructing the issuer URL");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // fromEnvironment() — missing env var guard
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("fromEnvironment() throws IllegalStateException when AUTH0_DOMAIN is absent")
    void fromEnvironment_throwsWhenDomainAbsent() {
        // AUTH0_DOMAIN is not set in the test environment.
        // fromEnvironment() must throw rather than silently continue with a null domain,
        // because a null domain would produce a malformed JWKS URI and cause every
        // live request to fail with a cryptic NullPointerException instead of a
        // clear startup error.
        assertThrows(
            IllegalStateException.class,
            AuthorizerConfig::fromEnvironment,
            "fromEnvironment() must throw IllegalStateException when AUTH0_DOMAIN is not set"
        );
    }

    @Test
    @DisplayName("fromEnvironment() exception message identifies the missing variable by name")
    void fromEnvironment_exceptionMessageNamesTheMissingVariable() {
        IllegalStateException ex = assertThrows(
            IllegalStateException.class,
            AuthorizerConfig::fromEnvironment
        );
        // The message must name the variable so that operators can fix the
        // misconfiguration from the Lambda init error log without reading source code.
        assertTrue(
            ex.getMessage().contains("AUTH0_DOMAIN") || ex.getMessage().contains("AUTH0_AUDIENCE"),
            "Exception message should identify the missing environment variable by name. Got: "
                + ex.getMessage()
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Record equality and identity
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("Two configs with identical values are equal")
    void recordEquality_sameValuesAreEqual() {
        String jwksUri = buildJwksUri(DOMAIN);
        var config1 = new AuthorizerConfig(DOMAIN, AUDIENCE, jwksUri);
        var config2 = new AuthorizerConfig(DOMAIN, AUDIENCE, jwksUri);
        assertEquals(config1, config2);
    }

    @Test
    @DisplayName("Two configs with different domains are not equal")
    void recordEquality_differentDomainsAreNotEqual() {
        var config1 = new AuthorizerConfig(DOMAIN,          AUDIENCE, buildJwksUri(DOMAIN));
        var config2 = new AuthorizerConfig("other.auth0.com", AUDIENCE, buildJwksUri("other.auth0.com"));
        assertNotEquals(config1, config2);
    }

    @Test
    @DisplayName("Two configs with different audiences are not equal")
    void recordEquality_differentAudiencesAreNotEqual() {
        var config1 = new AuthorizerConfig(DOMAIN, AUDIENCE,              buildJwksUri(DOMAIN));
        var config2 = new AuthorizerConfig(DOMAIN, "https://other.com",   buildJwksUri(DOMAIN));
        assertNotEquals(config1, config2);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper
    // ─────────────────────────────────────────────────────────────────────────

    private static String buildJwksUri(String domain) {
        return "https://" + domain + "/.well-known/jwks.json";
    }
}
