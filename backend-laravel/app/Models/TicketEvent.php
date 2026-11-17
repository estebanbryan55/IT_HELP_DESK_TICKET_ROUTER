<?php

namespace App\Models;

use App\Services\Clock;
use Illuminate\Database\Eloquent\Model;

/** One audit-trail entry on a ticket. */
class TicketEvent extends Model
{
    public $timestamps = false;
    protected $dateFormat = 'Y-m-d H:i:s.v';
    protected $guarded = [];

    protected function casts(): array
    {
        return ['at' => 'immutable_datetime'];
    }

    public function toApi(): array
    {
        return [
            'at' => Clock::iso($this->at),
            'actor' => $this->actor,
            'action' => $this->action,
            'from' => $this->from,
            'to' => $this->to,
            'note' => $this->note,
            'correlationId' => $this->correlation_id,
        ];
    }
}
