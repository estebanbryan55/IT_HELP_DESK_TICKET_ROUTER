<?php

// Help desk settings, all read from .env (see .env.example).

$csv = fn (string $v) => array_values(array_filter(array_map('trim', explode(',', $v))));

return [
    'version' => '0.13.0',
    'log_file' => env('HELPDESK_LOG_FILE', 'storage/logs/app.log'),
    'rules_file' => env('RULES_FILE', 'config/routing_rules.json'),
    'allowed_origins' => $csv(env('ALLOWED_ORIGINS', 'http://localhost:*')),
    'demo_auth_enabled' => filter_var(env('DEMO_AUTH_ENABLED', true), FILTER_VALIDATE_BOOL),

    // Development-only endpoints (POST /api/v1/dev/clock/advance).
    'dev_tools' => filter_var(env('HELPDESK_DEV_TOOLS', env('APP_ENV') === 'development'), FILTER_VALIDATE_BOOL),

    // Start outbox delivery right after a request that enqueued notifications (off in tests).
    'event_dispatch' => filter_var(env('HELPDESK_EVENT_DISPATCH', true), FILTER_VALIDATE_BOOL),

    'gateway' => [
        'url' => rtrim(env('GATEWAY_URL', 'http://127.0.0.1:8091'), '/'),
        'api_key' => env('GATEWAY_API_KEY', ''),
        'timeout_ms' => (int) env('GATEWAY_TIMEOUT_MS', 3000),
    ],

    'retry' => [
        'max_attempts' => (int) env('RETRY_MAX_ATTEMPTS', 4),
        'base_delay_ms' => (int) env('RETRY_BASE_DELAY_MS', 2000),
        'max_delay_ms' => (int) env('RETRY_MAX_DELAY_MS', 30000),
    ],

    'outbox_poll_seconds' => (int) env('OUTBOX_POLL_SECONDS', 5),
    'outbox_batch_size' => 20,
    'summary_hour' => (int) env('SUMMARY_HOUR', 18),
    'timezone_offset_hours' => (int) env('TIMEZONE_OFFSET_HOURS', 8),

    'sla_hours' => [
        'critical' => (int) env('SLA_HOURS_CRITICAL', 4),
        'high' => (int) env('SLA_HOURS_HIGH', 8),
        'medium' => (int) env('SLA_HOURS_MEDIUM', 24),
        'low' => (int) env('SLA_HOURS_LOW', 72),
    ],
    'sla_warning_ratio' => (float) env('SLA_WARNING_RATIO', 0.75),
];
