<?php

namespace App\Console\Commands;

use App\Services\MessageSigner;
use Illuminate\Console\Command;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\RequestException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Throwable;

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

    private const ATTEMPTS = 3;

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

        // Week 15 DEF-08: bounded waiting. Each attempt times out after 3 s and only
        // network failures or 5xx answers are retried (3 attempts, 500 ms apart).
        // Retrying is safe: the nonce makes a repeated delivery a 409 replay, not a new ticket.
        $send = fn () => Http::withHeaders([
            'X-Key-Id' => $keyId,
            'X-Timestamp' => (string) $timestamp,
            'X-Nonce' => $nonce,
            'X-Signature' => $signature,
            'Accept' => 'application/json',
        ])->connectTimeout(2)->timeout(3)
            ->retry(self::ATTEMPTS, 500, fn (Throwable $e) => $e instanceof ConnectionException
                || ($e instanceof RequestException && $e->response->serverError()), throw: false)
            ->withBody($body, 'application/json')->post($url);

        try {
            $this->report('Attempt 1', $send());
            if ($this->option('replay')) {
                $this->report('Attempt 2 (replay)', $send());
            }
        } catch (ConnectionException $e) {
            // Permanent failure for this run: report once, no stack trace, non-zero exit
            // so a scheduler or operator can route the message to manual handling.
            $this->error(sprintf('Help desk API unreachable after %d attempts (%s). Message kept for manual retry.',
                self::ATTEMPTS, str_contains($e->getMessage(), 'timed out') ? 'timeout' : 'connection failed'));

            return self::FAILURE;
        }

        return self::SUCCESS;
    }

    private function report(string $label, $response): void
    {
        $this->line(sprintf('%s: HTTP %d  correlation=%s  body=%s',
            $label, $response->status(), $response->header('X-Correlation-Id'), $response->body()));
    }
}
