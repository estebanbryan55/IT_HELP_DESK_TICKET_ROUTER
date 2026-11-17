<?php

namespace App\Models;

use App\Services\Clock;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Ticket extends Model
{
    public const SUBMITTED = 'submitted';
    public const NEEDS_TRIAGE = 'needs_triage';
    public const ASSIGNED = 'assigned';
    public const IN_PROGRESS = 'in_progress';
    public const RESOLVED = 'resolved';
    public const CLOSED = 'closed';

    public const STATUSES = [self::SUBMITTED, self::NEEDS_TRIAGE, self::ASSIGNED, self::IN_PROGRESS, self::RESOLVED, self::CLOSED];

    /** Statuses whose SLA clock is running. */
    public const OPEN_STATUSES = [self::SUBMITTED, self::NEEDS_TRIAGE, self::ASSIGNED, self::IN_PROGRESS];

    public const PRIORITIES = ['low', 'medium', 'high', 'critical'];
    public const CATEGORIES = ['network', 'account', 'hardware', 'software', 'other'];

    public $incrementing = false;
    public $timestamps = false;
    protected $keyType = 'string';
    protected $dateFormat = 'Y-m-d H:i:s.v';
    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'created_at' => 'immutable_datetime',
            'updated_at' => 'immutable_datetime',
            'sla_due_at' => 'immutable_datetime',
            'resolved_at' => 'immutable_datetime',
            'closed_at' => 'immutable_datetime',
            'escalated' => 'boolean',
            'alerts' => 'array',
        ];
    }

    public static function priorityRank(string $p): int
    {
        $i = array_search($p, self::PRIORITIES, true);

        return $i === false ? -1 : $i;
    }

    public function history(): HasMany
    {
        return $this->hasMany(TicketEvent::class)->orderBy('id');
    }

    public function responses(): HasMany
    {
        return $this->hasMany(TicketResponse::class)->orderBy('id');
    }

    public function isOpen(): bool
    {
        return in_array($this->status, self::OPEN_STATUSES, true);
    }

    public function hasAlert(string $alert): bool
    {
        return in_array($alert, $this->alerts ?? [], true);
    }

    /** @param array<string, string> $names user id -> display name */
    public function toApi(array $names): array
    {
        return [
            'id' => $this->id,
            'title' => $this->title,
            'description' => $this->description,
            'requestedCategory' => $this->requested_category,
            'requestedPriority' => $this->requested_priority,
            'category' => $this->category,
            'priority' => $this->priority,
            'status' => $this->status,
            'requesterId' => $this->requester_id,
            'assigneeId' => $this->assignee_id,
            'team' => $this->team,
            'createdAt' => Clock::iso($this->created_at),
            'updatedAt' => Clock::iso($this->updated_at),
            'slaDueAt' => Clock::iso($this->sla_due_at),
            'resolvedAt' => Clock::iso($this->resolved_at),
            'closedAt' => Clock::iso($this->closed_at),
            'routingReason' => $this->routing_reason,
            'escalated' => $this->escalated,
            'alerts' => array_values($this->alerts ?? []),
            'history' => $this->history->map(fn (TicketEvent $e) => $e->toApi())->all(),
            'responses' => $this->responses->map(fn (TicketResponse $r) => $r->toApi())->all(),
            'requesterName' => $names[$this->requester_id] ?? null,
            'assigneeName' => $this->assignee_id === null ? null : ($names[$this->assignee_id] ?? null),
        ];
    }
}
