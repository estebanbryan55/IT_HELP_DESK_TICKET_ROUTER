<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Cross-Origin Resource Sharing (CORS) Configuration
    |--------------------------------------------------------------------------
    |
    | Here you may configure your settings for cross-origin resource sharing
    | or "CORS". This determines what cross-origin operations may execute
    | in web browsers. You are free to adjust these settings as needed.
    |
    | To learn more: https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS
    |
    */

    'paths' => ['api/*'],

    'allowed_methods' => ['GET', 'POST'],

    // Only the Flutter Web origin(s); never '*' for an authenticated API.
    'allowed_origins' => explode(',', env('FRONTEND_ORIGINS', 'http://localhost:5000')),

    'allowed_origins_patterns' => [],

    // Week 15 DEF-07: Idempotency-Key must pass the browser preflight.
    'allowed_headers' => ['Authorization', 'Content-Type', 'Accept', 'X-Correlation-Id', 'Idempotency-Key'],

    'exposed_headers' => ['X-Correlation-Id', 'Idempotent-Replayed', 'Retry-After'],

    'max_age' => 0,

    'supports_credentials' => false,

];
