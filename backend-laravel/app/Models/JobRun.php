<?php

namespace App\Models;

use App\Services\Clock;
use Illuminate\Database\Eloquent\Model;

class JobRun extends Model
{
    protected $primaryKey = 'seq';
    public $timestamps = false;
    protected $dateFormat = 'Y-m-d H:i:s.v';
    protected $guarded = [];

    protected function casts(): array
    {
        return ['started_at' => 'immutable_datetime', 'finished_at' => 'immutable_datetime', 'stats' => 'object'];
    }

    public function durationMs(): ?int
    {
        return $this->finished_at === null ? null
            : (int) round($this->started_at->diffInMilliseconds($this->finished_at));
    }

    public function toApi(): array
    {
        return [
            'id' => $this->id,
            'job' => $this->job,
            'trigger' => $this->trigger,
            'startedAt' => Clock::iso($this->started_at),
            'finishedAt' => Clock::iso($this->finished_at),
            'durationMs' => $this->durationMs(),
            'status' => $this->status,
            'stats' => $this->stats ?? new \stdClass,
            'correlationId' => $this->correlation_id,
        ];
    }
}
