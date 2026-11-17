<?php

namespace App\Services;

use App\Models\Ticket;
use App\Models\User;

/** Scheduled job: SLA-style aging alerts, escalation, and reassignment away from unavailable agents. */
class AgingScanner
{
    public function __construct(
        private readonly Store $store,
        private readonly TicketService $tickets,
        private readonly Outbox $outbox,
        private readonly Clock $clock,
        private readonly StructuredLog $log,
    ) {}

    public function run(string $cid): array
    {
        return $this->store->transaction(function () use ($cid) {
            $now = $this->clock->now();
            $scanned = $warnings = $breaches = $reassigned = $toTriage = 0;
            $supervisors = User::where('role', User::SUPERVISOR)->orderBy('id')->get();
            $warningRatio = (float) config('helpdesk.sla_warning_ratio');

            $open = Ticket::with('history')->whereIn('status', Ticket::OPEN_STATUSES)->orderBy('created_at')->orderBy('id')->get();
            foreach ($open as $t) {
                $scanned++;

                // 1. Reassignment: the current agent was marked unavailable.
                $assignee = $t->assignee_id === null ? null : User::find($t->assignee_id);
                if ($assignee !== null && ! $assignee->available) {
                    $next = $this->tickets->pickAgent($t->team, $assignee->id);
                    if ($next !== null) {
                        $this->tickets->assignTo($t, $next, 'system:aging', $cid, "auto-reassigned: $assignee->id unavailable");
                        $reassigned++;
                    } else {
                        $this->tickets->sendToTriage($t, 'system:aging', $cid, "assignee $assignee->id unavailable and no backup in $t->team");
                        $toTriage++;
                    }
                    $t->updated_at = $now;
                }

                // 2. Aging: compare elapsed time with the SLA window.
                $window = $t->sla_due_at->getTimestamp() - $t->created_at->getTimestamp();
                $ratio = $window <= 0 ? 1.0 : ($now->getTimestamp() - $t->created_at->getTimestamp()) / $window;
                $owner = $t->assignee_id === null ? null : User::find($t->assignee_id);
                $percent = round($ratio * 100).'%';

                if ($ratio >= 1.0 && ! $t->hasAlert('breach')) {
                    $alerts = $t->alerts ?? [];
                    $alerts[] = 'breach';
                    if (! in_array('warning', $alerts, true)) {
                        $alerts[] = 'warning'; // a skipped warning is implied
                    }
                    $t->alerts = $alerts;
                    $t->escalated = true;
                    $this->tickets->audit($t, 'system:aging', 'sla_breached', note: 'escalated to supervisor', cid: $cid);
                    $recipients = collect([$owner, ...$supervisors])->filter()->unique('id');
                    foreach ($recipients as $r) {
                        $this->outbox->enqueue('sla.breach', $r, $cid, $t->id);
                    }
                    $this->log->warn('sla.breached', ['ticketId' => $t->id, 'ratio' => number_format($ratio, 2, '.', ''), 'assigneeId' => $t->assignee_id, 'correlationId' => $cid]);
                    $breaches++;
                } elseif ($ratio >= $warningRatio && $ratio < 1.0 && ! $t->hasAlert('warning')) {
                    $t->alerts = [...($t->alerts ?? []), 'warning'];
                    $this->tickets->audit($t, 'system:aging', 'sla_warning', note: "$percent of SLA used", cid: $cid);
                    foreach ($owner === null ? $supervisors : [$owner] as $r) {
                        $this->outbox->enqueue('sla.warning', $r, $cid, $t->id, vars: ['ratio' => $percent]);
                    }
                    $this->log->info('sla.warning', ['ticketId' => $t->id, 'ratio' => number_format($ratio, 2, '.', ''), 'assigneeId' => $t->assignee_id, 'correlationId' => $cid]);
                    $warnings++;
                }
                $t->save();
            }

            return ['scanned' => $scanned, 'warnings' => $warnings, 'breaches' => $breaches, 'reassigned' => $reassigned, 'sentToTriage' => $toTriage];
        });
    }
}
