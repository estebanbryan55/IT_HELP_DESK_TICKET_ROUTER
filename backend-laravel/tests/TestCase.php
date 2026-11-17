<?php

namespace Tests;

use App\Models\OutboxMessage;
use App\Models\User;
use App\Services\Clock;
use App\Services\NotificationGateway;
use App\Services\Outbox;
use App\Services\RetryPolicy;
use App\Services\StructuredLog;
use App\Services\TicketService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;

/** Runs against the helpdesk_test MySQL database with a scripted gateway and a fixed-seed retry policy. */
abstract class TestCase extends BaseTestCase
{
    use RefreshDatabase;

    protected bool $seed = true;

    protected FakeGateway $gateway;

    protected function setUp(): void
    {
        parent::setUp();
        $this->gateway = new FakeGateway;
        $this->app->instance(NotificationGateway::class, $this->gateway);
        mt_srand(42);
        $this->app->instance(RetryPolicy::class, new RetryPolicy(4, 2000, 30000, mt_rand(...)));
    }

    protected function tickets(): TicketService
    {
        return $this->app->make(TicketService::class);
    }

    protected function outbox(): Outbox
    {
        return $this->app->make(Outbox::class);
    }

    protected function user(string $id): User
    {
        return User::findOrFail($id);
    }

    protected function advance(int $seconds): void
    {
        $this->app->make(Clock::class)->advance($seconds);
    }

    protected function logEvents(): array
    {
        return array_column($this->app->make(StructuredLog::class)->recent, 'event');
    }

    protected function countEvent(string $event): int
    {
        return OutboxMessage::where('event', $event)->count();
    }

    protected function ticketBody(array $overrides = []): array
    {
        return [
            'title' => 'Wifi keeps dropping in room 204',
            'description' => 'The wifi connection drops every few minutes during class.',
            'category' => 'auto',
            'priority' => 'medium',
            ...$overrides,
        ];
    }
}
