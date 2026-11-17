<?php

namespace App\Enums;

enum TicketPriority: string
{
    case Low = 'low';
    case Normal = 'normal';
    case High = 'high';
    case Urgent = 'urgent';

    public function slaMultiplier(): float
    {
        return match ($this) {
            self::Low => 2.0,
            self::Normal => 1.0,
            self::High => 0.5,
            self::Urgent => 0.25,
        };
    }
}
