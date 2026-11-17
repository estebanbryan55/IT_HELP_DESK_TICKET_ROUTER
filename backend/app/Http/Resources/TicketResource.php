<?php

namespace App\Http\Resources;

use App\Enums\Role;
use App\Enums\TicketStatus;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** Exposes only the fields each role needs; protected fields are masked or omitted. */
class TicketResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $user = $request->user();
        $canSeeProtected = $user?->can('viewProtected', $this->resource) ?? false;
        $detailed = $this->relationLoaded('events');
        $open = ! in_array($this->status, [TicketStatus::Resolved, TicketStatus::Closed], true);

        return [
            'id' => $this->id,
            'reference' => $this->reference,
            'category' => $this->category->value,
            'priority' => $this->priority->value,
            'status' => $this->status->value,
            'source' => $this->source,
            'subject' => $this->subject,
            'description' => $this->when($detailed, fn () => $this->description),
            'asset_tag' => $this->asset_tag,
            'contact_number' => $this->when($detailed, fn () => $canSeeProtected
                ? $this->contact_number
                : self::mask($this->contact_number)),
            'access_note' => $this->when($detailed && $canSeeProtected, fn () => $this->access_note),
            'resolution_note' => $this->resolution_note,
            'requester' => $this->whenLoaded('requester', fn () => ['id' => $this->requester->id, 'name' => $this->requester->name]),
            'agent' => $this->whenLoaded('agent', fn () => $this->agent ? ['id' => $this->agent->id, 'name' => $this->agent->name] : null),
            'sla_due_at' => $this->sla_due_at?->toIso8601String(),
            'is_overdue' => $open && (bool) $this->sla_due_at?->isPast(),
            'resolved_at' => $this->resolved_at?->toIso8601String(),
            'closed_at' => $this->closed_at?->toIso8601String(),
            'created_at' => $this->created_at->toIso8601String(),
            'events' => $this->whenLoaded('events', fn () => $this->events->map(fn ($e) => [
                'action' => $e->action,
                'from_status' => $e->from_status,
                'to_status' => $e->to_status,
                // Internal routing notes are hidden from requesters.
                'note' => $user?->isRole(Role::Requester) && $e->action === 'assigned' ? null : $e->note,
                'created_at' => $e->created_at?->toIso8601String(),
            ])),
        ];
    }

    private static function mask(?string $value): ?string
    {
        return $value === null ? null : str_repeat('*', max(0, mb_strlen($value) - 3)).mb_substr($value, -3);
    }
}
