<?php

namespace Database\Factories;

use App\Enums\TicketCategory;
use App\Enums\TicketPriority;
use App\Enums\TicketStatus;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Ticket>
 */
class TicketFactory extends Factory
{
    public function definition(): array
    {
        return [
            'reference' => 'HD-2026-'.str_pad((string) fake()->unique()->numberBetween(1, 999999), 6, '0', STR_PAD_LEFT),
            'requester_id' => User::factory(),
            'category' => fake()->randomElement(TicketCategory::cases()),
            'priority' => TicketPriority::Normal,
            'status' => TicketStatus::Open,
            'subject' => fake()->sentence(4),
            'description' => fake()->paragraph(),
            'contact_number' => '0917 000 '.fake()->numerify('####'),
            'sla_due_at' => now()->addDay(),
        ];
    }

    public function assignedTo(User $agent): static
    {
        return $this->state(fn () => ['assigned_agent_id' => $agent->id, 'status' => TicketStatus::Assigned]);
    }
}
