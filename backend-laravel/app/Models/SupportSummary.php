<?php

namespace App\Models;

use App\Services\Clock;
use Illuminate\Database\Eloquent\Model;

class SupportSummary extends Model
{
    public $incrementing = false;
    public $timestamps = false;
    protected $keyType = 'string';
    protected $dateFormat = 'Y-m-d H:i:s.v';
    protected $guarded = [];

    protected function casts(): array
    {
        return ['generated_at' => 'immutable_datetime', 'data' => 'object'];
    }

    public function toApi(): array
    {
        return [
            'id' => $this->id,
            'date' => $this->date,
            'generatedAt' => Clock::iso($this->generated_at),
            'trigger' => $this->trigger,
            'data' => $this->data,
        ];
    }
}
