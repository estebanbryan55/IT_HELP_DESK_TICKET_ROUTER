<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;

/**
 * Every state change runs in a database transaction that first takes one row lock,
 * so only one transaction mutates help desk state at a time (API and scheduler alike).
 * A failed transaction is rolled back completely.
 */
class Store
{
    /**
     * @template T
     * @param callable(): T $fn
     * @return T
     */
    public function transaction(callable $fn): mixed
    {
        return DB::transaction(function () use ($fn) {
            DB::table('app_state')->where('key', 'lock')->lockForUpdate()->first();

            return $fn();
        });
    }

    /** Next value of a named sequence. Call inside transaction(). */
    public function nextSeq(string $name): int
    {
        $key = "seq:$name";
        DB::table('app_state')->insertOrIgnore(['key' => $key, 'value' => 0]);
        DB::table('app_state')->where('key', $key)->increment('value');

        return (int) DB::table('app_state')->where('key', $key)->value('value');
    }
}
