<?php

namespace App\Services;

/**
 * HMAC-SHA256 message authentication for the email-gateway integration.
 *
 * Signed string: "{timestamp}.{nonce}.{raw body}". Binding the timestamp and
 * nonce into the MAC means neither can be changed to make an old message look
 * fresh. The same class is used by the gateway simulator script and tests.
 */
class MessageSigner
{
    public static function sign(string $secret, int $timestamp, string $nonce, string $body): string
    {
        return hash_hmac('sha256', "{$timestamp}.{$nonce}.{$body}", $secret);
    }

    public static function verify(string $secret, int $timestamp, string $nonce, string $body, string $signature): bool
    {
        return hash_equals(self::sign($secret, $timestamp, $nonce, $body), strtolower($signature));
    }
}
