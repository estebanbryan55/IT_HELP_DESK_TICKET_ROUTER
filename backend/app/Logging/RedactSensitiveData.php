<?php

namespace App\Logging;

use Illuminate\Log\Logger;
use Monolog\LogRecord;

/**
 * Monolog tap that masks secrets and confidential ticket fields in log
 * context, as a safety net in case a developer logs a whole payload.
 */
class RedactSensitiveData
{
    public const KEYS = [
        'password', 'password_confirmation', 'token', 'access_token', 'authorization',
        'secret', 'signature', 'x-signature', 'contact_number', 'access_note', 'app_key',
    ];

    public function __invoke(Logger $logger): void
    {
        foreach ($logger->getHandlers() as $handler) {
            $handler->pushProcessor(fn (LogRecord $record) => $record->with(
                context: self::redact($record->context),
                extra: self::redact($record->extra),
            ));
        }
    }

    public static function redact(array $data): array
    {
        foreach ($data as $key => $value) {
            if (is_string($key) && in_array(strtolower($key), self::KEYS, true)) {
                $data[$key] = '[REDACTED]';
            } elseif (is_array($value)) {
                $data[$key] = self::redact($value);
            } elseif (is_string($value)) {
                $data[$key] = preg_replace('/Bearer\s+[A-Za-z0-9|\-_.]+/i', 'Bearer [REDACTED]', $value);
            }
        }

        return $data;
    }
}
