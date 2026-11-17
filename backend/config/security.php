<?php

return [

    // Reject plain-HTTP API requests. Disabled only for local development and automated tests.
    'require_https' => (bool) env('REQUIRE_HTTPS', true),

    // HSTS max-age sent on HTTPS responses (seconds).
    'hsts_max_age' => (int) env('HSTS_MAX_AGE', 31536000),

    // Bearer token lifetime for the Flutter Web client (minutes).
    'token_ttl_minutes' => (int) env('API_TOKEN_TTL_MINUTES', 60),

    'integration' => [
        // Shared HMAC keys for the email-gateway integration, as "keyId:secret,keyId2:secret2".
        // Two entries allow rotation: the partner switches key id, then the old one is removed.
        'keys' => collect(explode(',', (string) env('INTEGRATION_HMAC_KEYS', '')))
            ->filter(fn ($pair) => str_contains($pair, ':'))
            ->mapWithKeys(function ($pair) {
                [$id, $secret] = explode(':', trim($pair), 2);

                return [$id => $secret];
            })
            ->all(),

        // Maximum age / clock skew accepted for a signed message (seconds).
        'tolerance_seconds' => (int) env('INTEGRATION_SIGNATURE_TOLERANCE', 300),

        // Used only by the gateway:send simulator command.
        'simulator' => [
            'key_id' => env('GATEWAY_KEY_ID'),
            'url' => env('GATEWAY_URL'),
        ],
    ],

];
