<?php

namespace App\Enums;

enum Role: string
{
    case Requester = 'requester';
    case Agent = 'agent';
    case Supervisor = 'supervisor';

    /** Sanctum token abilities granted to each role (least privilege). */
    public function abilities(): array
    {
        return match ($this) {
            self::Requester => ['tickets:create', 'tickets:read-own', 'tickets:confirm'],
            self::Agent => ['tickets:read-assigned', 'tickets:work'],
            self::Supervisor => ['tickets:read-all', 'tickets:work', 'tickets:assign'],
        };
    }
}
