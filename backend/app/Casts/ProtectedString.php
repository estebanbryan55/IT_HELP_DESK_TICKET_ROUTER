<?php

namespace App\Casts;

use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Contracts\Encryption\DecryptException;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Log;

/**
 * Stores a confidential string using Laravel's authenticated encryption
 * (AES-256 with a MAC over IV and ciphertext). If the stored value was
 * altered or encrypted with an unknown key, the MAC check fails; instead of
 * crashing the request we log an integrity alert and return null so the
 * field is shown as unavailable.
 */
class ProtectedString implements CastsAttributes
{
    public function get(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        if ($value === null) {
            return null;
        }

        try {
            return Crypt::decryptString($value);
        } catch (DecryptException) {
            Log::warning('integrity.decrypt_failed', [
                'model' => $model::class,
                'id' => $model->getKey(),
                'field' => $key,
            ]);

            return null;
        }
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        return $value === null || $value === '' ? null : Crypt::encryptString((string) $value);
    }
}
