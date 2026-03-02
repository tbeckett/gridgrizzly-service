package com.gridgrizzly.authorizer;

import com.auth0.jwk.JwkException;

import java.security.PublicKey;

/**
 * Provides RSA public keys by key ID, used to verify JWT signatures.
 */
public interface JwksKeyProvider {

    PublicKey getPublicKey(String keyId) throws JwkException;
}
