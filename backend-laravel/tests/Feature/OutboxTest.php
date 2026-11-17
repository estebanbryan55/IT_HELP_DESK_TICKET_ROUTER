<?php

namespace Tests\Feature;

use App\Exceptions\ApiException;
use App\Models\OutboxMessage;
use App\Models\Ticket;
use App\Services\Store;
use Tests\TestCase;

class OutboxTest extends TestCase
{
    /** Runs the dispatcher repeatedly, moving the clock past each retry delay. */
    private function drain(int $rounds = 10): void
    {
        for ($i = 0; $i < $rounds; $i++) {
            $this->outbox()->dispatchDue();
            $this->advance(31);
        }
    }

    private function messageFor(string $event, string $recipient): OutboxMessage
    {
        return OutboxMessage::where('event', $event)->where('recipient_id', $recipient)->sole();
    }

    public function test_transient_failure_is_recovered_by_retry(): void
    {
        $this->tickets()->create($this->user('req-ana'), $this->ticketBody(), null, 'test-transient');
        $this->gateway->failTransient(4); // two messages queued (received + assigned): each fails twice

        $this->drain();

        $m = $this->messageFor('ticket.received', 'req-ana');
        $this->assertSame(OutboxMessage::SENT, $m->status);
        $this->assertSame(3, $m->attempts);
        $this->assertSame(['transient_failure', 'transient_failure', 'sent'], array_column($m->attempt_log, 'outcome'));
        $this->assertContains('notification.sent_after_retry', $this->logEvents());
    }

    public function test_retries_stop_at_the_attempt_limit_and_the_message_is_dead_lettered(): void
    {
        $this->tickets()->create($this->user('req-ana'), $this->ticketBody(), null, 'test-exhaust');
        $this->gateway->failTransient(50);

        $this->drain(12);

        $m = $this->messageFor('ticket.received', 'req-ana');
        $this->assertSame(OutboxMessage::DEAD_LETTER, $m->status);
        $this->assertSame('retries_exhausted', $m->dead_letter_reason);
        $this->assertSame(4, $m->attempts, 'never more than maxAttempts');
    }

    public function test_permanent_failure_goes_straight_to_manual_review_without_retrying(): void
    {
        $this->tickets()->create($this->user('req-gio'), $this->ticketBody(), null, 'test-permanent');

        $this->drain();

        $m = $this->messageFor('ticket.received', 'req-gio');
        $this->assertSame(OutboxMessage::DEAD_LETTER, $m->status);
        $this->assertSame('permanent_rejection', $m->dead_letter_reason);
        $this->assertSame(1, $m->attempts);
        // The workflow itself was not blocked by the failed notification.
        $this->assertSame(Ticket::ASSIGNED, Ticket::sole()->status);
    }

    public function test_enqueue_is_idempotent_for_the_same_key(): void
    {
        $this->app->make(Store::class)->transaction(function () {
            $u = $this->user('sup-mara');
            $this->outbox()->enqueue('summary.daily', $u, 'x', occurrence: 'SUM-1');
            $this->outbox()->enqueue('summary.daily', $u, 'x', occurrence: 'SUM-1');
        });
        $this->assertSame(1, OutboxMessage::count());
    }

    public function test_messages_left_in_sending_after_a_crash_are_recovered(): void
    {
        $this->tickets()->create($this->user('req-ana'), $this->ticketBody(), null, 'test-crash');
        // A dispatcher claimed the messages, then the process stopped before recording the outcome.
        OutboxMessage::query()->update(['status' => OutboxMessage::SENDING]);
        $this->advance(120); // past the lease

        $this->drain(1);

        $this->assertContains('outbox.recovered_in_flight', $this->logEvents());
        $this->assertSame(0, OutboxMessage::where('status', '!=', OutboxMessage::SENT)->count());
    }

    public function test_supervisor_can_retry_or_dismiss_a_dead_lettered_message(): void
    {
        $this->tickets()->create($this->user('req-gio'), $this->ticketBody(), null, 'test-manual');
        $this->drain(1);
        $m = $this->messageFor('ticket.received', 'req-gio');
        $sup = $this->user('sup-mara');

        try {
            $this->outbox()->dismiss($sup, $m->id, 'no', 'c');
            $this->fail('short note must be refused');
        } catch (ApiException $e) {
            $this->assertSame(422, $e->status);
        }
        $this->assertSame(OutboxMessage::DISMISSED, $this->outbox()->dismiss($sup, $m->id, 'Requester contacted by phone instead.', 'c')->status);
        $this->expectException(ApiException::class);
        $this->outbox()->manualRetry($sup, $m->id, 'c');
    }

    public function test_manual_retry_gives_a_fresh_budget_and_keeps_the_attempt_log(): void
    {
        $this->tickets()->create($this->user('req-gio'), $this->ticketBody(), null, 'c');
        $this->drain(1);
        $m = $this->messageFor('ticket.received', 'req-gio');

        $retried = $this->outbox()->manualRetry($this->user('sup-mara'), $m->id, 'c');
        $this->assertSame(OutboxMessage::PENDING, $retried->status);
        $this->assertSame(0, $retried->attempts);
        $this->assertCount(1, $retried->attempt_log);
    }
}
