<?php

namespace App\Console\Commands;

use App\Services\MessageSigner;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;

/**
 * Email-gateway simulator used to produce Week 14 evidence. Sends one signed
 * message and, optionally, a deliberately bad variant.
 *
 *   php artisan gateway:send                 valid message      -> 201
 *   php artisan gateway:send --tamper        body changed after signing -> 401
 *   php artisan gateway:send --expired       timestamp 10 minutes old   -> 401
 *   php artisan gateway:send --replay        same message sent twice    -> 201 then 409
 *   php artisan gateway:send --wrong-key     signed with a different secret -> 401
 */
class SendGatewayMessage extends Command
{
    protected $signature = 'gateway:send
        {--email=student@example.test : Registered requester email}
        {--tamper} {--expired} {--replay} {--wrong-key}';

    protected $description = 'Send a signed test ticket from the simulated email gateway';

    public function handle(): int
    {
        $keyId = (string) config('security.integration.simulator.key_id');
        $secret = config("security.integration.keys.{$keyId}");
        $url = (string) config('security.integration.simulator.url');

        if (! $secret || ! $url) {
            $this->error('Set GATEWAY_KEY_ID, GATEWAY_URL and INTEGRATION_HMAC_KEYS in .env first.');

            return self::FAILURE;
        }

        $body = json_encode([
            'requester_email' => $this->option('email'),
            'category' => 'software',
            'subject' => 'Email forwarded: cannot open LMS',
            'description' => 'Forwarded by the email gateway: the LMS shows a blank page after login.',
        ]);

        $timestamp = $this->option('expired') ? time() - 600 : time();
        $nonce = (string) Str::uuid();
        $signingSecret = $this->option('wrong-key') ? bin2hex(random_bytes(32)) : $secret;
        $signature = MessageSigner::sign($signingSecret, $timestamp, $nonce, $body);

        if ($this->option('tamper')) {
            $body = str_replace('"software"', '"account"', $body);
        }

        $send = fn () => Http::withHeaders([
            'X-Key-Id' => $keyId,
            'X-Timestamp' => (string) $timestamp,
            'X-Nonce' => $nonce,
            'X-Signature' => $signature,
            'Accept' => 'application/json',
        ])->withBody($body, 'application/json')->post($url);

        $this->report('Attempt 1', $send());
        if ($this->option('replay')) {
            $this->report('Attempt 2 (replay)', $send());
        }

        return self::SUCCESS;
    }

    private function report(string $label, $response): void
    {
        $this->line(sprintf('%s: HTTP %d  correlation=%s  body=%s',
            $label, $response->status(), $response->header('X-Correlation-Id'), $response->body()));
    }
}
