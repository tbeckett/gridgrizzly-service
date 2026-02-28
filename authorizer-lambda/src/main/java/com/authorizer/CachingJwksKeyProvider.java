package com.example.authorizer;

import com.auth0.jwk.Jwk;
import com.auth0.jwk.JwkException;
import com.auth0.jwk.JwkProvider;
import com.auth0.jwk.JwkProviderBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.URI;
import java.security.PublicKey;
import java.util.concurrent.TimeUnit;

/**
 * Provides RSA public keys fetched from Auth0's JWKS endpoint.
 *
 * Key caching strategy
 * ────────────────────
 * The Auth0 JWKS provider is built with a two-level cache:
 *
 *   1. In-process LRU cache (up to 5 keys, valid for 10 minutes).
 *      Warm Lambda invocations reuse this cache across requests —
 *      no network call is made until the TTL expires.
 *
 *   2. Rate-limit guard: at most 10 JWKS fetches per minute.
 *      This prevents thundering-herd behaviour on cold-start bursts
 *      and protects against malicious key-ID rotation attacks that
 *      would otherwise cause repeated outbound calls.
 *
 * The JwkProvider instance is stored in a static field so it survives
 * across warm Lambda invocations. Because Lambda single-threads each
 * execution environment, no additional synchronisation is required.
 */
public final class CachingJwksKeyProvider {

    private static final Logger log = LoggerFactory.getLogger(CachingJwksKeyProvider.class);

    private static final int    CACHE_SIZE      = 5;
    private static final long   CACHE_TTL_MINS  = 10;
    private static final long   RATE_LIMIT      = 10;
    private static final long   RATE_PERIOD_MIN = 1;

    private final JwkProvider provider;

    public CachingJwksKeyProvider(AuthorizerConfig config) {
        log.info("Initialising JWKS provider for: {}", config.jwksUri());
        this.provider = new JwkProviderBuilder(URI.create(config.jwksUri()).toURL())
                .cached(CACHE_SIZE, CACHE_TTL_MINS, TimeUnit.MINUTES)
                .rateLimited(RATE_LIMIT, RATE_PERIOD_MIN, TimeUnit.MINUTES)
                .build();
    }

    /**
     * Returns the RSA public key for the given key ID (kid).
     *
     * @param keyId the "kid" claim from the JWT header
     * @return the corresponding RSA {@link PublicKey}
     * @throws JwkException if the key cannot be fetched or found
     */
    public PublicKey getPublicKey(String keyId) throws JwkException {
        log.debug("Fetching public key for kid: {}", keyId);
        Jwk jwk = provider.get(keyId);
        return jwk.getPublicKey();
    }
}
