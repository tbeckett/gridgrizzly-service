package com.example.authorizer;

import com.amazonaws.services.lambda.runtime.events.IamPolicyResponse;

import java.util.List;
import java.util.Map;

/**
 * Builds IAM policy documents that API Gateway evaluates to allow or deny access.
 *
 * Policy design
 * ─────────────
 * API Gateway requires the Authorizer to return a policy in the following form:
 *
 *   {
 *     "principalId": "<userId>",
 *     "policyDocument": {
 *       "Version": "2012-10-17",
 *       "Statement": [ { "Effect": "Allow|Deny", "Action": "execute-api:Invoke",
 *                        "Resource": "<methodArn>" } ]
 *     },
 *     "context": { "userId": "<userId>" }  // ← injected into downstream Lambda context
 *   }
 *
 * The "context" map is the mechanism by which the verified userId is passed to
 * business logic Lambda functions. Downstream code reads:
 *
 *   event.getRequestContext().getAuthorizer().get("userId")
 *
 * The resource ARN is set to a wildcard ("arn:aws:execute-api:*:*:*") so that
 * a single cached Authorizer response covers all methods and stages for a given token.
 * If finer-grained method-level control is needed, pass the specific methodArn instead.
 */
public final class PolicyBuilder {

    /**
     * Wildcard resource — the Allow policy grants access to all API Gateway methods.
     * A cached Authorizer response therefore covers the full API surface for a valid token.
     */
    private static final String WILDCARD_RESOURCE = "arn:aws:execute-api:*:*:*";

    private PolicyBuilder() { }

    /**
     * Builds an Allow policy. Called on successful JWT validation.
     *
     * @param userId    the verified user identifier from the JWT "sub" claim
     * @param methodArn the invoked API Gateway method ARN (used as principalId context)
     * @return a fully constructed {@link IamPolicyResponse}
     */
    public static IamPolicyResponse allow(String userId, String methodArn) {
        return buildPolicy(userId, IamPolicyResponse.ALLOW, WILDCARD_RESOURCE);
    }

    /**
     * Builds a Deny policy. Called when JWT validation fails for any reason
     * other than a missing/malformed token (which should return a 401 via an exception).
     *
     * @param methodArn the invoked API Gateway method ARN
     * @return a fully constructed deny {@link IamPolicyResponse}
     */
    public static IamPolicyResponse deny(String methodArn) {
        return buildPolicy("anonymous", IamPolicyResponse.DENY, methodArn);
    }

    // ─────────────────────────────────────────────────────────────────────────

    private static IamPolicyResponse buildPolicy(
            String principalId,
            String effect,
            String resource
    ) {
        var statement = IamPolicyResponse.Statement.builder()
                .withEffect(effect)
                .withAction("execute-api:Invoke")
                .withResource(List.of(resource))
                .build();

        var policyDocument = IamPolicyResponse.PolicyDocument.builder()
                .withVersion("2012-10-17")
                .withStatement(List.of(statement))
                .build();

        // The context map is forwarded verbatim to every downstream Lambda function.
        // Values must be strings, numbers, or booleans — not nested objects.
        Map<String, Object> context = Map.of("userId", principalId);

        return IamPolicyResponse.builder()
                .withPrincipalId(principalId)
                .withPolicyDocument(policyDocument)
                .withContext(context)
                .build();
    }
}
