<?php

namespace App\Services;

use App\Exceptions\ApiException;
use App\Models\Ticket;
use App\Models\TicketEvent;
use App\Models\TicketResponse;
use App\Models\User;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

class TicketService
{
    public function __construct(
        private readonly Store $store,
        public readonly RoutingRules $rules,
        private readonly Outbox $outbox,
        private readonly Clock $clock,
        private readonly StructuredLog $log,
    ) {}

    // ---------------------------------------------------------------- queries

    /** @return Collection<int, Ticket> */
    public function listFor(User $user, ?string $status = null): Collection
    {
        $q = Ticket::with(['history', 'responses'])->orderByDesc('created_at')->orderByDesc('id');
        if ($status !== null) {
            $q->where('status', $status);
        }
        match ($user->role) {
            User::SUPERVISOR => null,
            User::AGENT => $q->where(fn ($w) => $w->where('assignee_id', $user->id)
                ->when($user->team !== null, fn ($w2) => $w2->orWhere('team', $user->team))),
            default => $q->where('requester_id', $user->id),
        };

        return $q->get();
    }

    public function getFor(User $user, string $id): Ticket
    {
        $t = Ticket::with(['history', 'responses'])->find($id);
        // Same 404 for "missing" and "not yours" so ticket numbers cannot be probed.
        if ($t === null || ! $this->canView($user, $t)) {
            throw ApiException::notFound('Ticket');
        }

        return $t;
    }

    public function canView(User $u, Ticket $t): bool
    {
        return match ($u->role) {
            User::SUPERVISOR => true,
            User::AGENT => $t->assignee_id === $u->id || ($t->team !== null && $t->team === $u->team),
            default => $t->requester_id === $u->id,
        };
    }

    // ---------------------------------------------------------------- commands

    public function create(User $actor, array $body, ?string $idempotencyKey, string $cid): Ticket
    {
        $this->requireRole($actor, [User::REQUESTER]);
        $input = self::validateCreate($body);

        return $this->store->transaction(function () use ($actor, $input, $idempotencyKey, $cid) {
            $idemKey = $idempotencyKey === null ? null : "$actor->id:$idempotencyKey";
            if ($idemKey !== null) {
                $existing = DB::table('ticket_idempotency_keys')->where('key', $idemKey)->value('ticket_id');
                if ($existing !== null) {
                    $this->log->info('ticket.create_replayed', ['ticketId' => $existing, 'correlationId' => $cid]);

                    return Ticket::with(['history', 'responses'])->findOrFail($existing);
                }
            }

            $now = $this->clock->now();
            $t = Ticket::create([
                'id' => 'TKT-'.str_pad((string) $this->store->nextSeq('ticket'), 4, '0', STR_PAD_LEFT),
                'title' => $input['title'],
                'description' => $input['description'],
                'requested_category' => $input['category'],
                'requested_priority' => $input['priority'],
                'category' => $input['category'],
                'priority' => $input['priority'],
                'status' => Ticket::SUBMITTED,
                'requester_id' => $actor->id,
                'created_at' => $now,
                'updated_at' => $now,
                'sla_due_at' => $now,
                'routing_reason' => '',
                'escalated' => false,
                'alerts' => [],
            ]);
            $t->setRelation('history', new \Illuminate\Database\Eloquent\Collection);
            $t->setRelation('responses', new \Illuminate\Database\Eloquent\Collection);
            if ($idemKey !== null) {
                DB::table('ticket_idempotency_keys')->insert(['key' => $idemKey, 'ticket_id' => $t->id]);
            }
            $this->audit($t, $actor->id, 'submitted', to: Ticket::SUBMITTED, cid: $cid);
            $this->log->info('ticket.submitted', ['ticketId' => $t->id, 'requesterId' => $actor->id, 'correlationId' => $cid]);

            $this->outbox->enqueue('ticket.received', $actor, $cid, $t->id);

            // Event-driven trigger: "ticket.created" is handled immediately, inside the same
            // transaction, so a ticket can never be saved without a routing decision.
            $this->onTicketCreated($t, $cid);
            $t->save();

            return $t;
        });
    }

    public function respond(User $actor, string $id, array $body, string $cid): Ticket
    {
        $message = self::text($body, 'message', 2, 2000);

        return $this->mutate($actor, $id, function (Ticket $t) use ($actor, $message, $cid) {
            if (! $t->isOpen() && $t->status !== Ticket::RESOLVED) {
                throw ApiException::conflict('Ticket is closed.');
            }
            $isStaff = $actor->role !== User::REQUESTER;
            if ($isStaff && ! $this->isAssigneeOrSupervisor($actor, $t)) {
                throw ApiException::forbidden('Only the assigned agent can respond.');
            }
            $t->responses->push(TicketResponse::create(['ticket_id' => $t->id, 'at' => $this->clock->now(), 'author_id' => $actor->id, 'message' => $message]));
            if ($isStaff) {
                if ($t->status === Ticket::ASSIGNED) {
                    $this->transition($t, $actor->id, Ticket::IN_PROGRESS, $cid, note: 'first response');
                }
                $this->outbox->enqueue('ticket.response', User::findOrFail($t->requester_id), $cid, $t->id, (string) $t->responses->count());
            } else {
                $this->audit($t, $actor->id, 'requester_comment', cid: $cid);
            }
        }, $cid);
    }

    public function resolve(User $actor, string $id, array $body, string $cid): Ticket
    {
        $note = self::text($body, 'resolution', 5, 1000);

        return $this->mutate($actor, $id, function (Ticket $t) use ($actor, $note, $cid) {
            if (! $this->isAssigneeOrSupervisor($actor, $t)) {
                throw ApiException::forbidden('Only the assigned agent can resolve.');
            }
            $this->requireStatus($t, [Ticket::ASSIGNED, Ticket::IN_PROGRESS]);
            $t->resolved_at = $this->clock->now();
            $this->transition($t, $actor->id, Ticket::RESOLVED, $cid, note: $note);
            $this->outbox->enqueue('ticket.resolved', User::findOrFail($t->requester_id), $cid, $t->id, (string) $t->history->count());
        }, $cid);
    }

    public function confirm(User $actor, string $id, string $cid): Ticket
    {
        return $this->mutate($actor, $id, function (Ticket $t) use ($actor, $cid) {
            if ($actor->id !== $t->requester_id) {
                throw ApiException::forbidden('Only the requester can confirm the resolution.');
            }
            $this->requireStatus($t, [Ticket::RESOLVED]);
            $t->closed_at = $this->clock->now();
            $this->transition($t, $actor->id, Ticket::CLOSED, $cid, note: 'requester confirmed resolution');
            if ($t->assignee_id !== null) {
                $this->outbox->enqueue('ticket.closed', User::findOrFail($t->assignee_id), $cid, $t->id);
            }
        }, $cid);
    }

    public function reopen(User $actor, string $id, array $body, string $cid): Ticket
    {
        $reason = self::text($body, 'reason', 5, 500);

        return $this->mutate($actor, $id, function (Ticket $t) use ($actor, $reason, $cid) {
            if ($actor->id !== $t->requester_id) {
                throw ApiException::forbidden('Only the requester can reopen.');
            }
            $this->requireStatus($t, [Ticket::RESOLVED]);
            $t->resolved_at = null;
            $this->transition($t, $actor->id, Ticket::IN_PROGRESS, $cid, note: "reopened: $reason");
            if ($t->assignee_id !== null) {
                $this->outbox->enqueue('ticket.reopened', User::findOrFail($t->assignee_id), $cid, $t->id, (string) $t->history->count());
            }
        }, $cid);
    }

    public function reassign(User $actor, string $id, array $body, string $cid): Ticket
    {
        $this->requireRole($actor, [User::SUPERVISOR]);
        $agentId = self::text($body, 'agentId', 1, 64);
        $reason = self::text($body, 'reason', 5, 500);

        return $this->mutate($actor, $id, function (Ticket $t) use ($actor, $agentId, $reason, $cid) {
            $this->requireStatus($t, [Ticket::ASSIGNED, Ticket::IN_PROGRESS, Ticket::NEEDS_TRIAGE]);
            $agent = User::find($agentId);
            if ($agent === null || $agent->role !== User::AGENT) {
                throw ApiException::validation(['agentId' => 'Unknown agent.']);
            }
            if (! $agent->available) {
                throw ApiException::validation(['agentId' => 'Agent is marked unavailable.']);
            }
            if ($agent->id === $t->assignee_id) {
                throw ApiException::validation(['agentId' => 'Ticket is already assigned to this agent.']);
            }
            $this->assignTo($t, $agent, $actor->id, $cid, "manual reassignment: $reason");
        }, $cid);
    }

    /** Supervisor completes a ticket the rules could not route. */
    public function triage(User $actor, string $id, array $body, string $cid): Ticket
    {
        $this->requireRole($actor, [User::SUPERVISOR]);
        $category = $body['category'] ?? null;
        $priority = $body['priority'] ?? null;
        $errors = [];
        if (! is_string($category) || $this->rules->teamFor($category) === null) {
            $errors['category'] = 'Choose a routable category.';
        }
        if (! is_string($priority) || ! in_array($priority, Ticket::PRIORITIES, true)) {
            $errors['priority'] = 'Choose a valid priority.';
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }

        return $this->mutate($actor, $id, function (Ticket $t) use ($actor, $category, $priority, $cid) {
            $this->requireStatus($t, [Ticket::NEEDS_TRIAGE]);
            $t->category = $category;
            $t->priority = $priority;
            $t->team = $this->rules->teamFor($category);
            $t->routing_reason = "triaged by $actor->id";
            $t->sla_due_at = $t->created_at->addHours($this->slaHours($t->priority));
            $agent = $this->pickAgent($t->team);
            if ($agent === null) {
                throw ApiException::conflict("No available agent in team $t->team.");
            }
            $this->assignTo($t, $agent, $actor->id, $cid, 'triaged');
        }, $cid);
    }

    public function setAvailability(User $actor, string $agentId, array $body, string $cid): User
    {
        $this->requireRole($actor, [User::SUPERVISOR]);
        $available = $body['available'] ?? null;
        if (! is_bool($available)) {
            throw ApiException::validation(['available' => 'Must be true or false.']);
        }

        return $this->store->transaction(function () use ($actor, $agentId, $available, $cid) {
            $agent = User::find($agentId);
            if ($agent === null || $agent->role !== User::AGENT) {
                throw ApiException::notFound('Agent');
            }
            $agent->update(['available' => $available]);
            $this->log->info('agent.availability_changed', ['agentId' => $agentId, 'available' => $available, 'actorId' => $actor->id, 'correlationId' => $cid]);

            return $agent;
        });
    }

    // ---------------------------------------------------------------- routing (shared with automation)

    private function onTicketCreated(Ticket $t, string $cid): void
    {
        $d = $this->rules->decide($t->title, $t->description, $t->requested_category, $t->requested_priority);
        $t->category = $d['category'];
        $t->priority = $d['priority'];
        $t->team = $d['team'];
        $t->routing_reason = $d['reason'];
        $t->sla_due_at = $t->created_at->addHours($this->slaHours($t->priority));
        $this->log->info('routing.decided', ['ticketId' => $t->id, ...$d, 'correlationId' => $cid]);

        $agent = $d['team'] === null ? null : $this->pickAgent($d['team']);
        if ($agent === null) {
            $this->sendToTriage($t, 'system:router', $cid, $d['team'] === null ? 'no routing rule matched' : "no available agent in {$d['team']}");

            return;
        }
        $this->assignTo($t, $agent, 'system:router', $cid, $d['reason']);
    }

    /** Least-loaded available agent in the team; ties broken by id for repeatable results. */
    public function pickAgent(string $team, ?string $excludeId = null): ?User
    {
        return User::where('role', User::AGENT)->where('team', $team)->where('available', true)
            ->when($excludeId !== null, fn ($q) => $q->where('id', '!=', $excludeId))
            ->withCount(['openTickets as load'])
            ->get()
            ->sortBy([['load', 'asc'], ['id', 'asc']])
            ->first();
    }

    public function assignTo(Ticket $t, User $agent, string $actorId, string $cid, ?string $note = null): void
    {
        $previous = $t->assignee_id;
        $t->assignee_id = $agent->id;
        $t->team = $agent->team;
        $event = $previous === null ? 'ticket.assigned' : 'ticket.reassigned';
        if ($t->status === Ticket::IN_PROGRESS) {
            $this->audit($t, $actorId, $previous === null ? 'assigned' : 'reassigned', from: $previous, to: $agent->id, note: $note, cid: $cid);
        } else {
            $this->transition($t, $actorId, Ticket::ASSIGNED, $cid, note: $note, assignee: $agent->id);
        }
        $t->save(); // so the next pickAgent sees the new load
        $this->log->info($event, ['ticketId' => $t->id, 'from' => $previous, 'to' => $agent->id, 'actorId' => $actorId, 'correlationId' => $cid]);
        $this->outbox->enqueue($event, $agent, $cid, $t->id, (string) $t->history->count(), ['priority' => $t->priority]);
    }

    public function sendToTriage(Ticket $t, string $actorId, string $cid, string $reason): void
    {
        $t->assignee_id = null;
        $this->transition($t, $actorId, Ticket::NEEDS_TRIAGE, $cid, note: $reason);
        $t->save();
        $this->log->warn('ticket.needs_triage', ['ticketId' => $t->id, 'reason' => $reason, 'correlationId' => $cid]);
        foreach (User::where('role', User::SUPERVISOR)->orderBy('id')->get() as $sup) {
            $this->outbox->enqueue('ticket.needs_triage', $sup, $cid, $t->id, (string) $t->history->count());
        }
    }

    public function audit(Ticket $t, string $actor, string $action, ?string $from = null, ?string $to = null, ?string $note = null, ?string $cid = null): void
    {
        $t->history->push(TicketEvent::create([
            'ticket_id' => $t->id, 'at' => $this->clock->now(), 'actor' => $actor, 'action' => $action,
            'from' => $from, 'to' => $to, 'note' => $note, 'correlation_id' => $cid,
        ]));
    }

    // ---------------------------------------------------------------- helpers

    private function mutate(User $actor, string $id, callable $fn, string $cid): Ticket
    {
        return $this->store->transaction(function () use ($actor, $id, $fn) {
            $t = Ticket::with(['history', 'responses'])->find($id);
            if ($t === null || ! $this->canView($actor, $t)) {
                throw ApiException::notFound('Ticket');
            }
            $fn($t);
            $t->updated_at = $this->clock->now();
            $t->save();

            return $t;
        });
    }

    private function transition(Ticket $t, string $actorId, string $to, string $cid, ?string $note = null, ?string $assignee = null): void
    {
        $from = $t->status;
        $t->status = $to;
        $this->audit($t, $actorId, 'status_changed', from: $from, to: $to,
            note: $assignee === null ? $note : trim(($note ?? '')." -> $assignee"), cid: $cid);
        $this->log->info('ticket.status_changed', ['ticketId' => $t->id, 'from' => $from, 'to' => $to, 'actorId' => $actorId, 'correlationId' => $cid]);
    }

    private function slaHours(string $priority): int
    {
        return config("helpdesk.sla_hours.$priority");
    }

    private function isAssigneeOrSupervisor(User $u, Ticket $t): bool
    {
        return $u->role === User::SUPERVISOR || $t->assignee_id === $u->id;
    }

    private function requireRole(User $u, array $roles): void
    {
        if (! in_array($u->role, $roles, true)) {
            throw ApiException::forbidden();
        }
    }

    private function requireStatus(Ticket $t, array $allowed): void
    {
        if (! in_array($t->status, $allowed, true)) {
            throw ApiException::conflict("Action not allowed while ticket is $t->status.");
        }
    }

    private static function text(array $body, string $field, int $min, int $max): string
    {
        $v = $body[$field] ?? null;
        if (! is_string($v) || mb_strlen(trim($v)) < $min || mb_strlen(trim($v)) > $max) {
            throw ApiException::validation([$field => "Must be $min-$max characters."]);
        }

        return trim($v);
    }

    /**
     * Server-side validation is authoritative; the Flutter form mirrors these rules.
     *
     * @return array{title: string, description: string, category: string, priority: string}
     */
    public static function validateCreate(array $b): array
    {
        $errors = [];
        $title = $b['title'] ?? null;
        $description = $b['description'] ?? null;
        $category = array_key_exists('category', $b) && $b['category'] !== null ? $b['category'] : 'auto';
        $priority = $b['priority'] ?? null;

        if (! is_string($title) || mb_strlen(trim($title)) < 5 || mb_strlen(trim($title)) > 120) {
            $errors['title'] = 'Title must be 5-120 characters.';
        }
        if (! is_string($description) || mb_strlen(trim($description)) < 10 || mb_strlen(trim($description)) > 2000) {
            $errors['description'] = 'Description must be 10-2000 characters.';
        }
        if (! is_string($category) || ! ($category === 'auto' || in_array($category, Ticket::CATEGORIES, true))) {
            $errors['category'] = 'Unknown category.';
        }
        if (! is_string($priority) || ! in_array($priority, Ticket::PRIORITIES, true)) {
            $errors['priority'] = 'Priority must be low, medium, high or critical.';
        }
        $unknown = array_diff(array_keys($b), ['title', 'description', 'category', 'priority']);
        if ($unknown !== []) {
            $errors['_'] = 'Unexpected fields: '.implode(', ', $unknown);
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }

        return ['title' => trim($title), 'description' => trim($description), 'category' => $category, 'priority' => $priority];
    }
}
