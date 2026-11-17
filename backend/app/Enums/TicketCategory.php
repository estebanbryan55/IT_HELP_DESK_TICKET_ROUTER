<?php

namespace App\Enums;

enum TicketCategory: string
{
    case Hardware = 'hardware';
    case Software = 'software';
    case Network = 'network';
    case Account = 'account';
    case Other = 'other';

    /** SLA target in hours used to compute sla_due_at for normal priority. */
    public function slaHours(): int
    {
        return match ($this) {
            self::Network, self::Account => 8,
            self::Hardware, self::Software => 24,
            self::Other => 48,
        };
    }
}
