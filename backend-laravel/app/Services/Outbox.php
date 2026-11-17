<?php

namespace App\Services;

use App\Exceptions\ApiException;
use App\Models\OutboxMessage;
use App\Models\User;
use Closure;

class Outbox
{
    /**
     * Message text carries only the ticket number and status (data minimisation):
     * no ticket description or requester details leave the system.
     */
    private const TEMPLATES = [
        'ticket.received' => 'We received your ticket {ticket}. You will be told when an agent is assigned.',
        'ticket.assigned' => 'Ticket {ticket} ({priority}) has been assigned to you.',
        'ticket.needs_triage' => 'Ticket {ticket} could not be routed automatically and needs triage.',
        'ticket.response' => 'Support replied on ticket {ticket}.',
        'ticket.resolved' => 'Ticket {ticket} was marked resolved. Please confirm or reopen it.',
        'ticket.reopened' => 'Ticket {ticket} was reopened by the requester.',
        'ticket.closed' => 'Ticket {ticket} was confirmed and closed.',
        'ticket.reassigned' => 'Ticket {ticket} was reassigned to you.',
        'sla.warning' => 'Ticket {ticket} has used {ratio} of its SLA time.',
        'sla.breach' => 'Ticket {ticket} has breached its SLA and was escalated.',
        'summary.daily' => 'The support summary for {date} is ready.',
    ];

    /** Called after something is enqueued so delivery starts without waiting for the next poll. */
    public ?Closure $onEnqueued = null;

    public function __construct(
        private readonly Store $store,
        private readonly NotificationGateway $gateway,
        private readonly RetryPolicy $policy,
        private readonly Clock $clock,
        private readonly StructuredLog $log,
        private readonly int $batchSize = 20,
        private readonly int $leaseSeconds = 60,
    ) {}

    /**
     * Adds a message inside the caller's transaction (transactional outbox):
     * the state change and its notification are saved together or not at all.
     * The idempotency key makes a repeated enqueue a no-op.
     *
     * @param array<string, string> $vars
     */
    public function enqueue(string $event, User $recipient, string $correlationId, ?string $ticketId = null,
        string $occurrence = '0', array $vars = []): ?OutboxMessage
    {
        $key = ($ticketId ?? 'system').":$event:$recipient->id:$occurrence";
        if (OutboxMessage::where('idempotency_key', $key)->exists()) {
            $this->log->info('outbox.duplicate_skipped', ['idempotencyKey' => $key, 'correlationId' => $correlationId]);

            return null;
        }
        $text = self::TEMPLATES[$event] ?? $event;
        foreach (['ticket' => $ticketId ?? '', ...$vars] as $k => $v) {
            $text = str_replace('{'.$k.'}', $v, $text);
        }
        $now = $this->clock->now();
        $m = OutboxMessage::create([
            'id' => 'MSG-'.str_pad((string) $this->store->nextSeq('message'), 5, '0', STR_PAD_LEFT),
            'idempotency_key' => $key,
            'ticket_id' => $ticketId,
            'event' => $event,
            'recipient_id' => $recipient->id,
            'recipient_address' => $recipient->email,
            'subject' => '[Help Desk] '.($ticketId ?? 'Summary').": $event",
            'body' => $text,
            'correlation_id' => $correlationId,
            'created_at' => $now,
            'status' => OutboxMessage::PENDING,
            'attempts' => 0,
            'next_attempt_at' => $now,
            'attempt_log' => [],
        ]);
        $this->log->info('outbox.enqueued', [
            'messageId' => $m->id,
            'notificationEvent' => $event,
            'ticketId' => $ticketId,
            'recipientId' => $recipient->id,
            'correlationId' => $correlationId,
        ]);
        $this->nudge();

        return $m;
    }

    /** @return array{processed: int, sent: int, retried: int, deadLettered: int} */
    public function dispatchDue(): array
    {
        $stats = ['sent' => 0, 'retried' => 0, 'deadLettered' => 0];

        $ids = $this->store->transaction(function () {
            $now = $this->clock->now();
            $nowDb = $now->format('Y-m-d H:i:s.v'); // keep milliseconds in the comparison

            // Recovery: "sending" past its lease means a process stopped mid-call.
            // It is safe to resend because the gateway de-duplicates by idempotency key.
            $stale = OutboxMessage::where('status', OutboxMessage::SENDING)->where('next_attempt_at', '<=', $nowDb)->get();
            foreach ($stale as $m) {
                $m->update(['status' => OutboxMessage::RETRYING, 'next_attempt_at' => $now]);
                $this->log->warn('outbox.recovered_in_flight', ['messageId' => $m->id, 'correlationId' => $m->correlation_id]);
            }

            $batch = OutboxMessage::whereIn('status', OutboxMessage::DUE)->where('next_attempt_at', '<=', $nowDb)
                ->orderBy('next_attempt_at')->orderBy('id')->limit($this->batchSize)->get();
            foreach ($batch as $m) {
                // Checkpoint before the external call; next_attempt_at doubles as the lease expiry.
                $m->update(['status' => OutboxMessage::SENDING, 'next_attempt_at' => $now->addSeconds($this->leaseSeconds)]);
            }

            return $batch->pluck('id')->all();
        });

        // Gateway calls happen outside the store lock.
        foreach ($ids as $id) {
            $result = $this->gateway->send(OutboxMessage::findOrFail($id));
            $this->store->transaction(function () use ($id, $result, &$stats) {
                $this->recordOutcome(OutboxMessage::findOrFail($id), $result, $stats);
            });
        }

        return ['processed' => $stats['sent'] + $stats['retried'] + $stats['deadLettered'], ...$stats];
    }

    private function recordOutcome(OutboxMessage $m, SendResult $r, array &$stats): void
    {
        $now = $this->clock->now();
        $m->attempts++;
        $fields = [
            'messageId' => $m->id,
            'ticketId' => $m->ticket_id,
            'notificationEvent' => $m->event,
            'attempt' => $m->attempts,
            'maxAttempts' => $this->policy->maxAttempts,
            'httpStatus' => $r->httpStatus,
            'errorCode' => $r->errorCode,
            'durationMs' => $r->durationMs,
            'correlationId' => $m->correlation_id,
        ];
        $attemptLog = $m->attempt_log ?? [];

        if ($r->ok()) {
            $attemptLog[] = ['at' => Clock::iso($now), 'outcome' => 'sent', 'httpStatus' => $r->httpStatus, 'errorCode' => null, 'durationMs' => $r->durationMs];
            $m->fill(['attempt_log' => $attemptLog, 'status' => OutboxMessage::SENT, 'sent_at' => $now, 'last_error_code' => null,
                'next_attempt_at' => $now])->save();
            $stats['sent']++;
            $this->log->info($m->attempts > 1 ? 'notification.sent_after_retry' : 'notification.sent', $fields);

            return;
        }

        $transient = $r->failure === 'transient';
        $attemptLog[] = [
            'at' => Clock::iso($now),
            'outcome' => $transient ? 'transient_failure' : 'permanent_failure',
            'httpStatus' => $r->httpStatus,
            'errorCode' => $r->errorCode,
            'durationMs' => $r->durationMs,
        ];
        $m->attempt_log = $attemptLog;
        $m->last_error_code = $r->errorCode;

        if ($transient && $this->policy->canRetry($m->attempts)) {
            $delay = $this->policy->delayAfter($m->attempts);
            $m->fill(['status' => OutboxMessage::RETRYING, 'next_attempt_at' => $now->addMilliseconds($delay)])->save();
            $stats['retried']++;
            $this->log->warn('notification.retry_scheduled', [...$fields, 'retryInMs' => $delay]);

            return;
        }

        $m->fill(['status' => OutboxMessage::DEAD_LETTER, 'dead_letter_reason' => $transient ? 'retries_exhausted' : 'permanent_rejection',
            'next_attempt_at' => $now])->save();
        $stats['deadLettered']++;
        $this->log->error('notification.dead_lettered', [...$fields, 'reason' => $m->dead_letter_reason, 'action' => 'manual_review_required']);
    }

    /** Supervisor action after fixing the cause (e.g. correcting a mailbox). */
    public function manualRetry(User $actor, string $id, string $correlationId): OutboxMessage
    {
        return $this->store->transaction(function () use ($actor, $id, $correlationId) {
            $m = OutboxMessage::find($id) ?? throw ApiException::notFound('Notification');
            if ($m->status !== OutboxMessage::DEAD_LETTER) {
                throw ApiException::conflict('Only dead-lettered notifications can be retried.');
            }
            // A fresh retry budget; earlier attempts stay in attempt_log.
            $m->update(['status' => OutboxMessage::PENDING, 'attempts' => 0, 'next_attempt_at' => $this->clock->now(),
                'resolution_note' => "manual retry by $actor->id"]);
            $this->log->info('notification.manual_retry', ['messageId' => $id, 'actorId' => $actor->id, 'correlationId' => $correlationId]);
            $this->nudge();

            return $m;
        });
    }

    public function dismiss(User $actor, string $id, string $note, string $correlationId): OutboxMessage
    {
        return $this->store->transaction(function () use ($actor, $id, $note, $correlationId) {
            $m = OutboxMessage::find($id) ?? throw ApiException::notFound('Notification');
            if ($m->status !== OutboxMessage::DEAD_LETTER) {
                throw ApiException::conflict('Only dead-lettered notifications can be dismissed.');
            }
            if (mb_strlen(trim($note)) < 5) {
                throw ApiException::validation(['note' => 'Explain the resolution (at least 5 characters).']);
            }
            $m->update(['status' => OutboxMessage::DISMISSED, 'resolution_note' => "$actor->id: ".trim($note)]);
            $this->log->info('notification.dismissed', ['messageId' => $id, 'actorId' => $actor->id, 'correlationId' => $correlationId]);

            return $m;
        });
    }

    private function nudge(): void
    {
        if ($this->onEnqueued !== null) {
            ($this->onEnqueued)();
        }
    }
}
