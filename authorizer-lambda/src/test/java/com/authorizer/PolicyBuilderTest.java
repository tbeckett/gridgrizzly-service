package com.example.authorizer;

import com.amazonaws.services.lambda.runtime.events.IamPolicyResponse;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for {@link PolicyBuilder}.
 *
 * PolicyBuilder is a pure function — no mocks or external dependencies needed.
 * Every test constructs a response and asserts on the exact shape that
 * API Gateway requires to evaluate the policy correctly.
 */
class PolicyBuilderTest {

    private static final String USER_ID    = "auth0|user-abc-123";
    private static final String METHOD_ARN = "arn:aws:execute-api:us-east-1:123456789:abc123/prod/GET/items";

    // ─────────────────────────────────────────────────────────────────────────
    // Allow policy
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("Allow — principalId is set to the userId")
    void allow_principalIdIsUserId() {
        IamPolicyResponse response = PolicyBuilder.allow(USER_ID, METHOD_ARN);
        assertEquals(USER_ID, response.getPrincipalId());
    }

    @Test
    @DisplayName("Allow — context map contains userId")
    void allow_contextContainsUserId() {
        IamPolicyResponse response = PolicyBuilder.allow(USER_ID, METHOD_ARN);
        assertNotNull(response.getContext());
        assertEquals(USER_ID, response.getContext().get("userId"));
    }

    @Test
    @DisplayName("Allow — context map contains exactly one entry")
    void allow_contextHasExactlyOneEntry() {
        IamPolicyResponse response = PolicyBuilder.allow(USER_ID, METHOD_ARN);
        assertEquals(1, response.getContext().size());
    }

    @Test
    @DisplayName("Allow — policy document is present")
    void allow_policyDocumentIsPresent() {
        IamPolicyResponse response = PolicyBuilder.allow(USER_ID, METHOD_ARN);
        assertNotNull(response.getPolicyDocument());
    }

    @Test
    @DisplayName("Allow — policy version is 2012-10-17")
    void allow_policyVersionIsCorrect() {
        IamPolicyResponse response = PolicyBuilder.allow(USER_ID, METHOD_ARN);
        assertEquals("2012-10-17", response.getPolicyDocument().getVersion());
    }

    @Test
    @DisplayName("Allow — exactly one statement is present")
    void allow_exactlyOneStatement() {
        IamPolicyResponse response = PolicyBuilder.allow(USER_ID, METHOD_ARN);
        List<?> statements = response.getPolicyDocument().getStatement();
        assertNotNull(statements);
        assertEquals(1, statements.size());
    }

    @Test
    @DisplayName("Allow — effect is Allow")
    void allow_effectIsAllow() {
        IamPolicyResponse response = PolicyBuilder.allow(USER_ID, METHOD_ARN);
        IamPolicyResponse.Statement stmt = firstStatement(response);
        assertEquals(IamPolicyResponse.ALLOW, stmt.getEffect());
    }

    @Test
    @DisplayName("Allow — action is execute-api:Invoke")
    void allow_actionIsInvoke() {
        IamPolicyResponse response = PolicyBuilder.allow(USER_ID, METHOD_ARN);
        IamPolicyResponse.Statement stmt = firstStatement(response);
        assertTrue(stmt.getAction().contains("execute-api:Invoke"));
    }

    @Test
    @DisplayName("Allow — resource is wildcard ARN (covers full API surface for cached response)")
    void allow_resourceIsWildcard() {
        IamPolicyResponse response = PolicyBuilder.allow(USER_ID, METHOD_ARN);
        IamPolicyResponse.Statement stmt = firstStatement(response);
        assertTrue(
            stmt.getResource().contains("arn:aws:execute-api:*:*:*"),
            "Allow policy should use wildcard resource so cached Authorizer response covers all methods"
        );
    }

    @Test
    @DisplayName("Allow — different userIds produce independent principalIds")
    void allow_differentUsersProduceIndependentPolicies() {
        IamPolicyResponse resp1 = PolicyBuilder.allow("auth0|user-111", METHOD_ARN);
        IamPolicyResponse resp2 = PolicyBuilder.allow("auth0|user-222", METHOD_ARN);

        assertNotEquals(resp1.getPrincipalId(), resp2.getPrincipalId());
        assertNotEquals(resp1.getContext().get("userId"), resp2.getContext().get("userId"));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Deny policy
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("Deny — principalId is 'anonymous'")
    void deny_principalIdIsAnonymous() {
        IamPolicyResponse response = PolicyBuilder.deny(METHOD_ARN);
        assertEquals("anonymous", response.getPrincipalId());
    }

    @Test
    @DisplayName("Deny — effect is Deny")
    void deny_effectIsDeny() {
        IamPolicyResponse response = PolicyBuilder.deny(METHOD_ARN);
        IamPolicyResponse.Statement stmt = firstStatement(response);
        assertEquals(IamPolicyResponse.DENY, stmt.getEffect());
    }

    @Test
    @DisplayName("Deny — policy document is present")
    void deny_policyDocumentIsPresent() {
        IamPolicyResponse response = PolicyBuilder.deny(METHOD_ARN);
        assertNotNull(response.getPolicyDocument());
    }

    @Test
    @DisplayName("Deny — policy version is 2012-10-17")
    void deny_policyVersionIsCorrect() {
        IamPolicyResponse response = PolicyBuilder.deny(METHOD_ARN);
        assertEquals("2012-10-17", response.getPolicyDocument().getVersion());
    }

    @Test
    @DisplayName("Deny — exactly one statement is present")
    void deny_exactlyOneStatement() {
        IamPolicyResponse response = PolicyBuilder.deny(METHOD_ARN);
        List<?> statements = response.getPolicyDocument().getStatement();
        assertNotNull(statements);
        assertEquals(1, statements.size());
    }

    @Test
    @DisplayName("Deny — action is execute-api:Invoke")
    void deny_actionIsInvoke() {
        IamPolicyResponse response = PolicyBuilder.deny(METHOD_ARN);
        IamPolicyResponse.Statement stmt = firstStatement(response);
        assertTrue(stmt.getAction().contains("execute-api:Invoke"));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Allow vs Deny contrast
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("Allow and Deny produce different effects for the same ARN")
    void allowAndDeny_produceDifferentEffects() {
        IamPolicyResponse allow = PolicyBuilder.allow(USER_ID, METHOD_ARN);
        IamPolicyResponse deny  = PolicyBuilder.deny(METHOD_ARN);

        assertNotEquals(
            firstStatement(allow).getEffect(),
            firstStatement(deny).getEffect()
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper
    // ─────────────────────────────────────────────────────────────────────────

    private IamPolicyResponse.Statement firstStatement(IamPolicyResponse response) {
        return response.getPolicyDocument().getStatement().get(0);
    }
}
