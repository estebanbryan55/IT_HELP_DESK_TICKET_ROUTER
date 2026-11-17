<?php

namespace Tests\Feature;

use App\Enums\TicketCategory;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class TicketAuthorizationTest extends TestCase
{
    use RefreshDatabase;

    private function validTicket(array $overrides = []): array
    {
        return array_merge([
            'category' => 'network',
            'subject' => 'Wi-Fi keeps dropping',
            'description' => 'Wi-Fi disconnects every five minutes in the library.',
            'contact_number' => '0917 555 0101',
        ], $overrides);
    }

    public function test_requester_creates_ticket_and_it_is_routed_to_specialised_agent(): void
    {
        User::factory()->agent(TicketCategory::Hardware)->create();
        $network = User::factory()->agent(TicketCategory::Network)->create();
        Sanctum::actingAs(User::factory()->create());

        $response = $this->postJson('/api/v1/tickets', $this->validTicket());

        $response->assertCreated()
            ->assertJsonPath('data.status', 'assigned')
            ->assertJsonPath('data.agent.id', $network->id);
        $this->assertDatabaseHas('ticket_events', ['action' => 'assigned']);
    }

    public function test_invalid_input_is_rejected_with_field_errors(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->postJson('/api/v1/tickets', $this->validTicket([
            'category' => 'printer-magic',
            'subject' => 'x',
            'contact_number' => '<script>',
            'asset_tag' => 'lower case!',
        ]))->assertStatus(422)->assertJsonValidationErrors(['category', 'subject', 'contact_number', 'asset_tag']);
    }

    public function test_requester_cannot_view_another_requesters_ticket(): void
    {
        $ticket = Ticket::factory()->create();
        Sanctum::actingAs(User::factory()->create());

        $this->getJson("/api/v1/tickets/{$ticket->id}")
            ->assertStatus(403)
            ->assertExactJson(['message' => 'You are not permitted to perform this action.']);
    }

    public function test_ticket_list_is_scoped_to_the_caller(): void
    {
        $me = User::factory()->create();
        Ticket::factory()->count(2)->create(['requester_id' => $me->id]);
        Ticket::factory()->count(3)->create();
        Sanctum::actingAs($me);

        $this->getJson('/api/v1/tickets')->assertOk()->assertJsonCount(2, 'data');
    }

    public function test_requester_cannot_change_status_or_assign(): void
    {
        $me = User::factory()->create();
        $ticket = Ticket::factory()->assignedTo(User::factory()->agent()->create())->create(['requester_id' => $me->id]);
        Sanctum::actingAs($me);

        $this->postJson("/api/v1/tickets/{$ticket->id}/transition", ['status' => 'resolved', 'note' => 'fixed'])->assertStatus(403);
        $this->postJson("/api/v1/tickets/{$ticket->id}/assign", ['agent_id' => $me->id])->assertStatus(403);
    }

    public function test_agent_cannot_work_a_ticket_assigned_to_someone_else(): void
    {
        $ticket = Ticket::factory()->assignedTo(User::factory()->agent()->create())->create();
        Sanctum::actingAs(User::factory()->agent()->create());

        $this->getJson("/api/v1/tickets/{$ticket->id}")->assertStatus(403);
        $this->postJson("/api/v1/tickets/{$ticket->id}/transition", ['status' => 'in_progress'])->assertStatus(403);
    }

    public function test_full_workflow_assign_resolve_confirm_close(): void
    {
        $requester = User::factory()->create();
        $agent = User::factory()->agent()->create();
        $ticket = Ticket::factory()->assignedTo($agent)->create(['requester_id' => $requester->id]);

        Sanctum::actingAs($agent);
        $this->postJson("/api/v1/tickets/{$ticket->id}/transition", ['status' => 'in_progress'])->assertOk();
        $this->postJson("/api/v1/tickets/{$ticket->id}/transition", ['status' => 'resolved'])
            ->assertStatus(422)->assertJsonValidationErrors('note');
        $this->postJson("/api/v1/tickets/{$ticket->id}/transition", ['status' => 'resolved', 'note' => 'Reset the access point.'])
            ->assertOk()->assertJsonPath('data.status', 'resolved');

        Sanctum::actingAs($requester);
        $this->postJson("/api/v1/tickets/{$ticket->id}/confirm", ['accepted' => true])
            ->assertOk()->assertJsonPath('data.status', 'closed');

        $this->assertSame(
            ['assigned', 'in_progress', 'resolved', 'closed'],
            ['assigned', ...$ticket->events()->pluck('to_status')->all()],
        );
    }

    public function test_invalid_status_transition_is_refused(): void
    {
        $agent = User::factory()->agent()->create();
        $ticket = Ticket::factory()->assignedTo($agent)->create(['status' => 'closed']);
        Sanctum::actingAs($agent);

        $this->postJson("/api/v1/tickets/{$ticket->id}/transition", ['status' => 'in_progress'])->assertStatus(409);
    }

    public function test_supervisor_can_reassign_only_to_an_active_agent(): void
    {
        $ticket = Ticket::factory()->assignedTo(User::factory()->agent()->create())->create();
        $other = User::factory()->agent()->create();
        $inactive = User::factory()->agent()->create(['is_active' => false]);
        Sanctum::actingAs(User::factory()->supervisor()->create());

        $this->postJson("/api/v1/tickets/{$ticket->id}/assign", ['agent_id' => $inactive->id])->assertStatus(422);
        $this->postJson("/api/v1/tickets/{$ticket->id}/assign", ['agent_id' => $other->id])
            ->assertOk()->assertJsonPath('data.agent.id', $other->id);
    }

    public function test_unknown_ticket_returns_generic_not_found(): void
    {
        Sanctum::actingAs(User::factory()->supervisor()->create());

        $this->getJson('/api/v1/tickets/999999')->assertStatus(404)->assertExactJson(['message' => 'Resource not found.']);
    }
}
