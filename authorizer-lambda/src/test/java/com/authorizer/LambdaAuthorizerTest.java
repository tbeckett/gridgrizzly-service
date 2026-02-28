package com.example.authorizer;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.events.APIGatewayCustomAuthorizerEvent;
import com.amazonaws.services.lambda.runtime.events.IamPolicyResponse;
import com.auth0.jwk.JwkException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.time.Instant;
import java.util.Date;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * Unit tests for the Lambda Authorizer.
 *
 * Strategy: we test the validation logic directly by injecting a mock
 * CachingJwksKeyProvider and constructing real signed JWTs in-process
 * using a locally generated RSA key pair. No network calls are made.
 *
 * The LambdaAuthorizer class uses static initialisation that reads env vars,
 * so we test the validation logic via a package-private constructor that
 * accepts explicit collaborators (config + key provider). This follows the
 * Dependency Injection principle without requiring a DI framework.
 */
@ExtendWith(MockitoExtension.class)
class LambdaAuthorizerTest {

    private static final String TEST_DOMAIN   = "test-tenant.auth0.com";
    private static final String TEST_AUDIENCE = "https://api.test.com";
    private static final String TEST_USER_ID  = "auth0|user-abc-123";
    private static final String TEST_KID      = "test-key-id-001";
    private static final String TEST_METHOD   = "arn:aws:execute-api:us-east-1:123:abc/prod/GET/items";

    private RSAPublicKey  publicKey;
    private RSAPrivateKey privateKey;
    private Algorithm     algorithm;

    @Mock
    private CachingJwksKeyProvider mockKeyProvider;

    @Mock
    private Context mockContext;

    private AuthorizerConfig config;

    @BeforeEach
    void setUp() throws Exception {
        // Generate a fresh RSA key pair for each test
        KeyPairGenerator gen = KeyPairGenerator.getInstance("RSA");
        gen.initialize(2048);
        KeyPair kp = gen.generateKeyPair();
        publicKey  = (RSAPublicKey)  kp.getPublic();
        privateKey = (RSAPrivateKey) kp.getPrivate();
        algorithm  = Algorithm.RSA256(publicKey, privateKey);

        config = new AuthorizerConfig(TEST_DOMAIN, TEST_AUDIENCE,
                "https://" + TEST_DOMAIN + "/.well-known/jwks.json");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Happy path
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("Valid JWT → Allow policy with userId in context")
    void validToken_returnsAllowPolicy() throws Exception {
        String token = buildValidToken();
        when(mockKeyProvider.getPublicKey(TEST_KID)).thenReturn(publicKey);

        IamPolicyResponse response = invokeAuthorizer("Bearer " + token);

        assertEquals(TEST_USER_ID, response.getPrincipalId());
        assertNotNull(response.getPolicyDocument());

        var statements = response.getPolicyDocument().getStatement();
        assertEquals(1, statements.size());
        assertEquals(IamPolicyResponse.ALLOW, statements.get(0).getEffect());

        assertEquals(TEST_USER_ID, response.getContext().get("userId"));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Failure cases
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("Missing Authorization header → Unauthorized")
    void missingAuthHeader_throwsUnauthorized() {
        var event = buildEvent(null);
        var authorizer = new LambdaAuthorizer(config, mockKeyProvider);
        assertThrowsUnauthorized(() -> authorizer.handleRequest(event, mockContext));
    }

    @Test
    @DisplayName("Blank Authorization header → Unauthorized")
    void blankAuthHeader_throwsUnauthorized() {
        var event = buildEvent("   ");
        var authorizer = new LambdaAuthorizer(config, mockKeyProvider);
        assertThrowsUnauthorized(() -> authorizer.handleRequest(event, mockContext));
    }

    @Test
    @DisplayName("Non-Bearer scheme → Unauthorized")
    void nonBearerScheme_throwsUnauthorized() {
        var event = buildEvent("Basic dXNlcjpwYXNz");
        var authorizer = new LambdaAuthorizer(config, mockKeyProvider);
        assertThrowsUnauthorized(() -> authorizer.handleRequest(event, mockContext));
    }

    @Test
    @DisplayName("Expired JWT → Unauthorized")
    void expiredToken_throwsUnauthorized() throws Exception {
        String token = buildExpiredToken();
        when(mockKeyProvider.getPublicKey(TEST_KID)).thenReturn(publicKey);

        var event = buildEvent("Bearer " + token);
        var authorizer = new LambdaAuthorizer(config, mockKeyProvider);
        assertThrowsUnauthorized(() -> authorizer.handleRequest(event, mockContext));
    }

    @Test
    @DisplayName("Wrong audience → Unauthorized")
    void wrongAudience_throwsUnauthorized() throws Exception {
        String token = JWT.create()
                .withKeyId(TEST_KID)
                .withIssuer(config.issuer())
                .withAudience("https://wrong-audience.com")
                .withSubject(TEST_USER_ID)
                .withExpiresAt(Date.from(Instant.now().plusSeconds(3600)))
                .sign(algorithm);

        when(mockKeyProvider.getPublicKey(TEST_KID)).thenReturn(publicKey);

        var event = buildEvent("Bearer " + token);
        var authorizer = new LambdaAuthorizer(config, mockKeyProvider);
        assertThrowsUnauthorized(() -> authorizer.handleRequest(event, mockContext));
    }

    @Test
    @DisplayName("Wrong issuer → Unauthorized")
    void wrongIssuer_throwsUnauthorized() throws Exception {
        String token = JWT.create()
                .withKeyId(TEST_KID)
                .withIssuer("https://attacker.fake.com/")
                .withAudience(TEST_AUDIENCE)
                .withSubject(TEST_USER_ID)
                .withExpiresAt(Date.from(Instant.now().plusSeconds(3600)))
                .sign(algorithm);

        when(mockKeyProvider.getPublicKey(TEST_KID)).thenReturn(publicKey);

        var event = buildEvent("Bearer " + token);
        var authorizer = new LambdaAuthorizer(config, mockKeyProvider);
        assertThrowsUnauthorized(() -> authorizer.handleRequest(event, mockContext));
    }

    @Test
    @DisplayName("JWKS network failure → Unauthorized (does not expose internal error)")
    void jwksProviderFailure_throwsUnauthorized() throws Exception {
        String token = buildValidToken();
        when(mockKeyProvider.getPublicKey(TEST_KID))
                .thenThrow(new JwkException("JWKS endpoint unreachable"));

        var event = buildEvent("Bearer " + token);
        var authorizer = new LambdaAuthorizer(config, mockKeyProvider);
        assertThrowsUnauthorized(() -> authorizer.handleRequest(event, mockContext));
    }

    @Test
    @DisplayName("JWT missing kid header → Unauthorized")
    void missingKid_throwsUnauthorized() throws Exception {
        String token = JWT.create()
                // deliberately omit withKeyId()
                .withIssuer(config.issuer())
                .withAudience(TEST_AUDIENCE)
                .withSubject(TEST_USER_ID)
                .withExpiresAt(Date.from(Instant.now().plusSeconds(3600)))
                .sign(algorithm);

        var event = buildEvent("Bearer " + token);
        var authorizer = new LambdaAuthorizer(config, mockKeyProvider);
        assertThrowsUnauthorized(() -> authorizer.handleRequest(event, mockContext));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private String buildValidToken() {
        return JWT.create()
                .withKeyId(TEST_KID)
                .withIssuer(config.issuer())
                .withAudience(TEST_AUDIENCE)
                .withSubject(TEST_USER_ID)
                .withExpiresAt(Date.from(Instant.now().plusSeconds(3600)))
                .withIssuedAt(Date.from(Instant.now()))
                .sign(algorithm);
    }

    private String buildExpiredToken() {
        return JWT.create()
                .withKeyId(TEST_KID)
                .withIssuer(config.issuer())
                .withAudience(TEST_AUDIENCE)
                .withSubject(TEST_USER_ID)
                .withExpiresAt(Date.from(Instant.now().minusSeconds(60)))
                .sign(algorithm);
    }

    private APIGatewayCustomAuthorizerEvent buildEvent(String authHeader) {
        var event = new APIGatewayCustomAuthorizerEvent();
        event.setAuthorizationToken(authHeader);
        event.setMethodArn(TEST_METHOD);
        return event;
    }

    private IamPolicyResponse invokeAuthorizer(String authHeader) {
        var event      = buildEvent(authHeader);
        var authorizer = new LambdaAuthorizer(config, mockKeyProvider);
        return authorizer.handleRequest(event, mockContext);
    }

    private void assertThrowsUnauthorized(org.junit.jupiter.api.function.Executable executable) {
        RuntimeException ex = assertThrows(RuntimeException.class, executable);
        assertEquals("Unauthorized", ex.getMessage());
    }
}
