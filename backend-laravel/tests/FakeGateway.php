<?php

namespace Tests;

use App\Models\OutboxMessage;
use App\Services\NotificationGateway;
use App\Services\SendResult;

/** Gateway whose responses are scripted per call. Default outcome is success. */
class FakeGateway implements NotificationGateway
{
    /** @var list<SendResult> */
    public array $script = [];

    /** @var list<string> message ids */
    public array $calls = [];

    public function failTransient(int $times, int $status = 503): void
    {
        for ($i = 0; $i < $times; $i++) {
            $this->script[] = new SendResult('transient', 5, $status, 'service_unavailable');
        }
    }

    public function send(OutboxMessage $m): SendResult
    {
        $this->calls[] = $m->id;
        if (str_ends_with($m->recipient_address, '@invalid.test')) {
            return new SendResult('permanent', 3, 422, 'recipient_rejected');
        }

        return array_shift($this->script) ?? new SendResult('none', 4, 202);
    }

    public function ping(): bool
    {
        return true;
    }
}
