<?php

namespace App\Services;

use Carbon\CarbonImmutable;
use DateTimeInterface;
use Illuminate\Support\Facades\DB;

/**
 * Injectable clock so SLA aging can be tested and demonstrated without waiting hours.
 * The development offset is stored in the database so the API and the scheduler share it.
 */
class Clock
{
    public function now(): CarbonImmutable
    {
        return CarbonImmutable::now('UTC')->addSeconds($this->offsetSeconds());
    }

    public function offsetSeconds(): int
    {
        return (int) (DB::table('app_state')->where('key', 'clock_offset_seconds')->value('value') ?? 0);
    }

    public function advance(int $seconds): void
    {
        DB::table('app_state')->where('key', 'clock_offset_seconds')->increment('value', $seconds);
    }

    /** ISO-8601 UTC with milliseconds, e.g. 2026-11-11T07:00:00.123Z */
    public static function iso(?DateTimeInterface $d): ?string
    {
        return $d === null ? null : CarbonImmutable::instance($d)->utc()->format('Y-m-d\TH:i:s.v\Z');
    }
}
