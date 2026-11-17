<?php

namespace App\Services;

use App\Enums\Role;
use App\Enums\TicketCategory;
use App\Enums\TicketPriority;
use App\Enums\TicketStatus;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\Context;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Creates tickets, applies rule-based assignment, and records every state
 * change in the append-only ticket_events table.
 */
class TicketRouter
{
    public function open(User $requester, array $data, string $source = 'web'): Ticket
    {
        return DB::transaction(function () use ($requester, $data, $source) {
            $category = TicketCategory::from($data['category']);
            $priority = TicketPriority::from($data['priority'] ?? 'normal');

            $ticket = Ticket::create([
                'reference' => $this->nextReference(),
                'requester_id' => $requester->id,
                'category' => $category,
                'priority' => $priority,
                'status' => TicketStatus::Open,
                'source' => $source,
                'subject' => $data['subject'],
                'description' => $data['description'],
                'asset_tag' => $data['asset_tag'] ?? null,
                'contact_number' => $data['contact_number'] ?? null,
                'access_note' => $data['access_note'] ?? null,
                'sla_due_at' => now()->addMinutes((int) round($category->slaHours() * 60 * $priority->slaMultiplier())),
            ]);

            $this->record($ticket, $requester, 'created', null, TicketStatus::Open);

            if ($agent = $this->pickAgent($category)) {
                $this->assign($ticket, $agent, null, 'rule-based assignment');
            }

            Log::info('ticket.created', ['ticket' => $ticket->reference, 'source' => $source]);

            return $ticket->refresh();
        });
    }

    public function assign(Ticket $ticket, User $agent, ?User $actor, ?string $note = null): Ticket
    {
        $from = $ticket->status;
        $ticket->assigned_agent_id = $agent->id;
        if ($ticket->status === TicketStatus::Open) {
            $ticket->status = TicketStatus::Assigned;
        }
        $ticket->save();

        $this->record($ticket, $actor, 'assigned', $from, $ticket->status, $note ?? "assigned to agent #{$agent->id}");

        return $ticket;
    }

    public function transition(Ticket $ticket, TicketStatus $to, User $actor, ?string $note = null): Ticket
    {
        $from = $ticket->status;
        $ticket->status = $to;

        if ($to === TicketStatus::Resolved) {
            $ticket->resolved_at = now();
            $ticket->resolution_note = $note;
        } elseif ($to === TicketStatus::Closed) {
            $ticket->closed_at = now();
        } elseif ($to === TicketStatus::InProgress) {
            $ticket->resolved_at = null;
        }
        $ticket->save();

        $this->record($ticket, $actor, 'status_changed', $from, $to, $note);

        return $ticket;
    }

    /** Least-loaded active agent specialised in the category; falls back to any active agent. */
    private function pickAgent(TicketCategory $category): ?User
    {
        $base = User::query()
            ->where('role', Role::Agent)
            ->where('is_active', true)
            ->withCount(['assignedTickets as open_load' => fn ($q) => $q->whereNotIn('status', [
                TicketStatus::Resolved, TicketStatus::Closed,
            ])])
            ->orderBy('open_load')
            ->orderBy('id');

        return (clone $base)->where('specialization', $category)->first() ?? $base->first();
    }

    private function nextReference(): string
    {
        $next = (Ticket::max('id') ?? 0) + 1;

        return sprintf('HD-%s-%06d', now()->format('Y'), $next);
    }

    private function record(Ticket $ticket, ?User $actor, string $action, ?TicketStatus $from, ?TicketStatus $to, ?string $note = null): void
    {
        $ticket->events()->create([
            'actor_id' => $actor?->id,
            'action' => $action,
            'from_status' => $from?->value,
            'to_status' => $to?->value,
            'note' => $note ? mb_substr($note, 0, 500) : null,
            'correlation_id' => Context::get('correlation_id'),
        ]);
    }
}
