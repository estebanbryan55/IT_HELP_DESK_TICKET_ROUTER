<?php

namespace App\Services;

use App\Models\OutboxMessage;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;

/** Calls the external notification service over HTTP with a hard timeout. */
class HttpNotificationGateway implements NotificationGateway
{
    public function __construct(
        private readonly string $baseUrl,
        private readonly string $apiKey,
        private readonly int $timeoutMs,
    ) {}

    public function send(OutboxMessage $m): SendResult
    {
        $start = hrtime(true);
        $elapsed = fn () => intdiv(hrtime(true) - $start, 1_000_000);
        try {
            $res = Http::withOptions(['timeout' => $this->timeoutMs / 1000, 'connect_timeout' => $this->timeoutMs / 1000])
                ->withToken($this->apiKey)
                ->withHeaders(['Idempotency-Key' => $m->idempotency_key, 'X-Correlation-Id' => $m->correlation_id])
                ->asJson()
                ->post("$this->baseUrl/send", ['to' => $m->recipient_address, 'subject' => $m->subject, 'body' => $m->body]);
        } catch (ConnectionException $e) {
            $code = str_contains(strtolower($e->getMessage()), 'timed out') ? 'timeout' : 'connection_refused';

            return new SendResult('transient', $elapsed(), errorCode: $code);
        }

        $kind = RetryPolicy::classifyHttpStatus($res->status());
        $code = null;
        if ($kind !== 'none') {
            $error = $res->json('error');
            $code = is_scalar($error) ? (string) $error : 'http_'.$res->status();
        }

        return new SendResult($kind, $elapsed(), $res->status(), $code);
    }

    public function ping(): bool
    {
        try {
            return Http::timeout(1)->get("$this->baseUrl/health")->status() === 200;
        } catch (\Throwable) {
            return false;
        }
    }
}
