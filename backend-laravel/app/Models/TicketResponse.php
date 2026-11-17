<?php

namespace App\Models;

use App\Services\Clock;
use Illuminate\Database\Eloquent\Model;

class TicketResponse extends Model
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
        return ['at' => Clock::iso($this->at), 'authorId' => $this->author_id, 'message' => $this->message];
    }
}
