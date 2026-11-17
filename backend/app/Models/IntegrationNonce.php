<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;

#[Fillable(['key_id', 'nonce', 'received_at'])]
class IntegrationNonce extends Model
{
    public $timestamps = false;

    protected function casts(): array
    {
        return ['received_at' => 'datetime'];
    }
}
