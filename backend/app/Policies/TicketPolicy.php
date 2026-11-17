<?php

namespace App\Policies;

use App\Enums\Role;
use App\Models\Ticket;
use App\Models\User;

/**
 * Authorisation is decided from server-side data (role, ownership,
 * assignment), never from anything the client sends about itself.
 */
class TicketPolicy
{
    public function view(User $user, Ticket $ticket): bool
    {
        return match ($user->role) {
            Role::Supervisor => true,
            Role::Agent => $ticket->assigned_agent_id === $user->id,
            Role::Requester => $ticket->requester_id === $user->id,
        };
    }

    public function create(User $user): bool
    {
        return $user->isRole(Role::Requester);
    }

    public function work(User $user, Ticket $ticket): bool
    {
        return $user->isRole(Role::Supervisor)
            || ($user->isRole(Role::Agent) && $ticket->assigned_agent_id === $user->id);
    }

    // Week 15: policies decide WHO may act; whether the ticket's current state
    // allows the action is checked in the controller and answered with 409.
    public function assign(User $user, Ticket $ticket): bool
    {
        return $user->isRole(Role::Supervisor);
    }

    public function confirm(User $user, Ticket $ticket): bool
    {
        return $ticket->requester_id === $user->id;
    }

    /** Who may see decrypted contact details and access notes. */
    public function viewProtected(User $user, Ticket $ticket): bool
    {
        return $ticket->requester_id === $user->id || $this->work($user, $ticket);
    }
}
