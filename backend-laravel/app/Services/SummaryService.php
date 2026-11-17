<?php

namespace App\Services;

use App\Models\OutboxMessage;
use App\Models\SupportSummary;
use App\Models\Ticket;
use App\Models\User;
use DateTimeInterface;

/** Builds the daily support summary for supervisors. */
class SummaryService
{
    public function __construct(
        private readonly Store $store,
        private readonly Outbox $outbox,
        private readonly Clock $clock,
        private readonly StructuredLog $log,
    ) {}

    public function localDate(DateTimeInterface $utc): string
    {
        return \Carbon\CarbonImmutable::instance($utc)->utc()->addHours((int) config('helpdesk.timezone_offset_hours'))->format('Y-m-d');
    }

    public function hasSummaryFor(string $date): bool
    {
        return SupportSummary::where('date', $date)->where('trigger', 'scheduled')->exists();
    }

    public function generate(string $trigger, string $cid): SupportSummary
    {
        return $this->store->transaction(function () use ($trigger, $cid) {
            $now = $this->clock->now();
            $today = $this->localDate($now);
            $isToday = fn (?DateTimeInterface $d) => $d !== null && $this->localDate($d) === $today;
            $tickets = Ticket::all();
            $open = $tickets->filter->isOpen();
            $resolvedMinutes = $tickets->whereNotNull('resolved_at')
                ->map(fn (Ticket $t) => intdiv($t->resolved_at->getTimestamp() - $t->created_at->getTimestamp(), 60))->values();
            $countBy = fn ($list, callable $key) => (object) $list->countBy($key)->all();
            $msgs = OutboxMessage::all();

            $data = [
                'totals' => [
                    'all' => $tickets->count(),
                    'open' => $open->count(),
                    'submittedToday' => $tickets->filter(fn ($t) => $isToday($t->created_at))->count(),
                    'closedToday' => $tickets->filter(fn ($t) => $isToday($t->closed_at))->count(),
                    'breachedOpen' => $open->filter(fn ($t) => $t->hasAlert('breach'))->count(),
                    'awaitingTriage' => $open->where('status', Ticket::NEEDS_TRIAGE)->count(),
                ],
                'byStatus' => $countBy($tickets, fn ($t) => $t->status),
                'openByCategory' => $countBy($open, fn ($t) => $t->category),
                'openByAgent' => $countBy($open->whereNotNull('assignee_id'), fn ($t) => $t->assignee_id),
                'avgResolutionMinutes' => $resolvedMinutes->isEmpty() ? null : (int) round($resolvedMinutes->avg()),
                'notifications' => [
                    'sent' => $msgs->where('status', OutboxMessage::SENT)->count(),
                    'sentAfterRetry' => $msgs->filter(fn ($m) => $m->status === OutboxMessage::SENT && count($m->attempt_log ?? []) > 1)->count(),
                    'pendingOrRetrying' => $msgs->whereIn('status', OutboxMessage::DUE)->count(),
                    'deadLetter' => $msgs->where('status', OutboxMessage::DEAD_LETTER)->count(),
                ],
            ];
            $seq = $this->store->nextSeq('summary');
            $summary = SupportSummary::create(['id' => "SUM-$seq", 'seq' => $seq, 'date' => $today, 'generated_at' => $now, 'trigger' => $trigger, 'data' => $data]);
            SupportSummary::where('seq', '<=', $seq - 60)->delete(); // keep the latest 60
            foreach (User::where('role', User::SUPERVISOR)->orderBy('id')->get() as $sup) {
                $this->outbox->enqueue('summary.daily', $sup, $cid, occurrence: $summary->id, vars: ['date' => $today]);
            }
            $this->log->info('summary.generated', ['summaryId' => $summary->id, 'date' => $today, 'trigger' => $trigger, 'open' => $open->count(), 'correlationId' => $cid]);

            return $summary->refresh();
        });
    }
}
