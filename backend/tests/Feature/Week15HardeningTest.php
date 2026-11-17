<?php

namespace Tests\Feature;

use App\Models\Ticket;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Week 15 (IA6) hardening regression set. Each test names the defect it
 * guards (DEF-xx in docs/defect-log.md) so the failure can be traced back.
 */
class Week15HardeningTest extends TestCase
{
    use RefreshDatabase;

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'category' => 'network',
            'subject' => 'Wi-Fi keeps dropping',
            'description' => 'Wi-Fi disconnects every five minutes in the library.',
        ], $overrides);
    }

    /** DEF-01 (BOLA): a ticket the caller may not see must look exactly like a missing one. */
    public function test_def01_requester_gets_404_not_403_for_someone_elses_ticket(): void
    {
        $ticket = Ticket::factory()->create();
        Sanctum::actingAs(User::factory()->create());

        $this->getJson("/api/v1/tickets/{$ticket->id}")
            ->assertNotFound()
            ->assertExactJson(['message' => 'Resource not found.']);
    }

    /** DEF-01: same for agents probing tickets assigned to someone else, on read and write routes. */
    public function test_def01_agent_cannot_probe_other_agents_ticket(): void
    {
        $ticket = Ticket::factory()->assignedTo(User::factory()->agent()->create())->create();
        Sanctum::actingAs(User::factory()->agent()->create());

        $this->getJson("/api/v1/tickets/{$ticket->id}")->assertNotFound();
        $this->postJson("/api/v1/tickets/{$ticket->id}/transition", ['status' => 'in_progress'])->assertNotFound();
    }

    /** DEF-01: a caller who CAN see the ticket but lacks the action still gets 403. */
    public function test_def01_visible_ticket_with_missing_permission_is_still_403(): void
    {
        $me = User::factory()->create();
        $ticket = Ticket::factory()->assignedTo(User::factory()->agent()->create())->create(['requester_id' => $me->id]);
        Sanctum::actingAs($me);

        $this->postJson("/api/v1/tickets/{$ticket->id}/transition", ['status' => 'resolved', 'note' => 'x'])->assertForbidden();
    }

    /** DEF-02: a double-submitted form (same Idempotency-Key) creates one ticket. */
    public function test_def02_duplicate_submission_with_same_key_creates_one_ticket(): void
    {
        User::factory()->agent()->create();
        Sanctum::actingAs(User::factory()->create());
        $headers = ['Idempotency-Key' => 'form-7f3a9c21-0001'];

        $first = $this->postJson('/api/v1/tickets', $this->payload(), $headers)->assertCreated();
        $second = $this->postJson('/api/v1/tickets', $this->payload(), $headers)->assertOk();

        $this->assertSame($first->json('data.id'), $second->json('data.id'));
        $second->assertHeader('Idempotent-Replayed', 'true');
        $this->assertSame(1, Ticket::count());
    }

    /** DEF-02: reusing a key for a different request is a client bug and is refused. */
    public function test_def02_same_key_with_different_payload_is_conflict(): void
    {
        Sanctum::actingAs(User::factory()->create());
        $headers = ['Idempotency-Key' => 'form-7f3a9c21-0002'];

        $this->postJson('/api/v1/tickets', $this->payload(), $headers)->assertCreated();
        $this->postJson('/api/v1/tickets', $this->payload(['subject' => 'Something else']), $headers)->assertStatus(409);
        $this->assertSame(1, Ticket::count());
    }

    /** DEF-02: keys are scoped per requester, so one user cannot replay another user's ticket. */
    public function test_def02_keys_are_scoped_to_the_requester(): void
    {
        $headers = ['Idempotency-Key' => 'form-shared-key-0003'];
        Sanctum::actingAs(User::factory()->create());
        $this->postJson('/api/v1/tickets', $this->payload(), $headers)->assertCreated();

        Sanctum::actingAs(User::factory()->create());
        $this->postJson('/api/v1/tickets', $this->payload(), $headers)->assertCreated();
        $this->assertSame(2, Ticket::count());
    }

    /** DEF-02: malformed keys are rejected instead of being stored. */
    public function test_def02_malformed_idempotency_key_is_rejected(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->postJson('/api/v1/tickets', $this->payload(), ['Idempotency-Key' => 'bad key!'])
            ->assertStatus(422)->assertJsonValidationErrors('idempotency_key');
    }

    /** DEF-03: confirming a ticket that is not resolved is a state conflict, not a permission problem. */
    public function test_def03_confirm_on_unresolved_ticket_is_409(): void
    {
        $me = User::factory()->create();
        $ticket = Ticket::factory()->assignedTo(User::factory()->agent()->create())->create(['requester_id' => $me->id]);
        Sanctum::actingAs($me);

        $this->postJson("/api/v1/tickets/{$ticket->id}/confirm", ['accepted' => true])
            ->assertStatus(409)->assertJsonPath('message', 'Only a resolved ticket can be confirmed.');
    }

    /** DEF-03: reassigning a closed ticket is a state conflict. */
    public function test_def03_assign_on_closed_ticket_is_409(): void
    {
        $agent = User::factory()->agent()->create();
        $ticket = Ticket::factory()->assignedTo($agent)->create(['status' => 'closed']);
        Sanctum::actingAs(User::factory()->supervisor()->create());

        $this->postJson("/api/v1/tickets/{$ticket->id}/assign", ['agent_id' => $agent->id])->assertStatus(409);
    }

    /** DEF-05: an unknown status filter is a client error, not an empty result. */
    public function test_def05_unknown_status_filter_is_rejected(): void
    {
        Sanctum::actingAs(User::factory()->supervisor()->create());

        $this->getJson('/api/v1/tickets?status=bogus')->assertStatus(422)->assertJsonValidationErrors('status');
        $this->getJson('/api/v1/tickets?status=open')->assertOk();
    }

    /** DEF-06: a wrong HTTP method must not list the supported methods or the route path. */
    public function test_def06_method_not_allowed_is_generic(): void
    {
        $response = $this->getJson('/api/v1/auth/login')->assertStatus(405);

        $this->assertStringNotContainsString('Supported methods', $response->getContent());
        $this->assertStringNotContainsString('api/v1/auth/login', $response->getContent());
    }

    /** DEF-07: the browser must be allowed to send Idempotency-Key cross-origin (CORS preflight). */
    public function test_def07_cors_allows_idempotency_header_from_flutter_origin(): void
    {
        $this->call('OPTIONS', '/api/v1/tickets', server: [
            'HTTP_ORIGIN' => 'http://localhost:5000',
            'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'POST',
            'HTTP_ACCESS_CONTROL_REQUEST_HEADERS' => 'authorization,content-type,idempotency-key',
        ])->assertHeader('Access-Control-Allow-Origin', 'http://localhost:5000')
            ->assertHeader('Access-Control-Allow-Headers');

        $allowed = strtolower((string) $this->call('OPTIONS', '/api/v1/tickets', server: [
            'HTTP_ORIGIN' => 'http://localhost:5000',
            'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'POST',
            'HTTP_ACCESS_CONTROL_REQUEST_HEADERS' => 'idempotency-key',
        ])->headers->get('Access-Control-Allow-Headers'));
        $this->assertStringContainsString('idempotency-key', $allowed);
    }

    /** DEF-04: the health endpoint reports the database dependency. */
    public function test_def04_health_endpoint_reports_ok(): void
    {
        $this->getJson('/api/v1/health')
            ->assertOk()
            ->assertJsonPath('status', 'ok')
            ->assertJsonPath('checks.database', 'ok');
    }
}
