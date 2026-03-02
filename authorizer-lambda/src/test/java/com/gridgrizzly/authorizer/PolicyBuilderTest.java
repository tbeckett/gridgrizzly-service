package com.gridgrizzly.authorizer;

import com.amazonaws.services.lambda.runtime.events.IamPolicyResponse;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for {@link PolicyBuilder}.
 * <p/>
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
        assertEquals("2012-10-17", response.getPolicyDocument().get("Version"));
    }

    @Test
    @DisplayName("Allow — exactly one statement is present")
    void allow_exactlyOneStatement() {
        IamPolicyResponse response = PolicyBuilder.allow(USER_ID, METHOD_ARN);
        Map<?, ?>[] statements = (Map<?, ?>[]) response.getPolicyDocument().get("Statement");
        assertNotNull(statements);
        assertEquals(1, statements.length);
    }

    @Test
    @DisplayName("Allow — effect is Allow")
    void allow_effectIsAllow() {
        Map<String, Object> stmt = firstStatement(PolicyBuilder.allow(USER_ID, METHOD_ARN));
        assertEquals(IamPolicyResponse.ALLOW, stmt.get("Effect"));
    }

    @Test
    @DisplayName("Allow — action is execute-api:Invoke")
    void allow_actionIsInvoke() {
        Map<String, Object> stmt = firstStatement(PolicyBuilder.allow(USER_ID, METHOD_ARN));
        assertEquals("execute-api:Invoke", stmt.get("Action"));
    }

    @Test
    @DisplayName("Allow — resource is wildcard ARN (covers full API surface for cached response)")
    void allow_resourceIsWildcard() {
        Map<String, Object> stmt = firstStatement(PolicyBuilder.allow(USER_ID, METHOD_ARN));
        String[] resources = (String[]) stmt.get("Resource");
        assertTrue(
            Arrays.asList(resources).contains("arn:aws:execute-api:*:*:*"),
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
        Map<String, Object> stmt = firstStatement(PolicyBuilder.deny(METHOD_ARN));
        assertEquals(IamPolicyResponse.DENY, stmt.get("Effect"));
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
        assertEquals("2012-10-17", response.getPolicyDocument().get("Version"));
    }

    @Test
    @DisplayName("Deny — exactly one statement is present")
    void deny_exactlyOneStatement() {
        IamPolicyResponse response = PolicyBuilder.deny(METHOD_ARN);
        Map<?, ?>[] statements = (Map<?, ?>[]) response.getPolicyDocument().get("Statement");
        assertNotNull(statements);
        assertEquals(1, statements.length);
    }

    @Test
    @DisplayName("Deny — action is execute-api:Invoke")
    void deny_actionIsInvoke() {
        Map<String, Object> stmt = firstStatement(PolicyBuilder.deny(METHOD_ARN));
        assertEquals("execute-api:Invoke", stmt.get("Action"));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Allow vs Deny contrast
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("Allow and Deny produce different effects for the same ARN")
    void allowAndDeny_produceDifferentEffects() {
        assertNotEquals(
            firstStatement(PolicyBuilder.allow(USER_ID, METHOD_ARN)).get("Effect"),
            firstStatement(PolicyBuilder.deny(METHOD_ARN)).get("Effect")
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private Map<String, Object> firstStatement(IamPolicyResponse response) {
        Map<String, Object>[] statements = (Map<String, Object>[]) response.getPolicyDocument().get("Statement");
        return statements[0];
    }
}
