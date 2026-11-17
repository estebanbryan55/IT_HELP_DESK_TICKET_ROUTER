<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** A seeded help desk user (requester, agent or supervisor). */
class User extends Model
{
    public const REQUESTER = 'requester';
    public const AGENT = 'agent';
    public const SUPERVISOR = 'supervisor';

    public $incrementing = false;
    public $timestamps = false;
    protected $keyType = 'string';
    protected $guarded = [];

    protected function casts(): array
    {
        return ['available' => 'boolean'];
    }

    public function openTickets(): HasMany
    {
        return $this->hasMany(Ticket::class, 'assignee_id')->whereIn('status', Ticket::OPEN_STATUSES);
    }

    /** What clients may see: the email address stays on the server. */
    public function toPublic(): array
    {
        return [
            'id' => $this->id,
            'displayName' => $this->display_name,
            'role' => $this->role,
            'team' => $this->team,
            'available' => $this->available,
        ];
    }
}
