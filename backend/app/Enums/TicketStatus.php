<?php

namespace App\Enums;

enum TicketStatus: string
{
    case Open = 'open';
    case Assigned = 'assigned';
    case InProgress = 'in_progress';
    case Resolved = 'resolved';
    case Closed = 'closed';

    /** Allowed transitions for agents/supervisors working a ticket. */
    public function canMoveTo(self $next): bool
    {
        return in_array($next, match ($this) {
            self::Open => [self::Assigned],
            self::Assigned => [self::InProgress, self::Resolved],
            self::InProgress => [self::Resolved],
            self::Resolved => [self::InProgress, self::Closed],
            self::Closed => [],
        }, true);
    }
}
