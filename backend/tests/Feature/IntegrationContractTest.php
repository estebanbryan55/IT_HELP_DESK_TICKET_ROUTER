<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Week 15 functional, boundary, and contract tests that describe behaviour
 * the Flutter client relies on (status codes, shapes, limits).
 */
class IntegrationContractTest extends TestCase
{
    use RefreshDatabase;

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'category' => 'hardware',
            'subject' => 'Projector not detected',
            'description' => 'The projector in Room 305 shows no signal.',
        ], $overrides);
    }

    public function test_subject_boundaries_5_and_120_accepted_4_and_121_rejected(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->postJson('/api/v1/tickets', $this->payload(['subject' => str_repeat('a', 5)]))->assertCreated();
        $this->postJson('/api/v1/tickets', $this->payload(['subject' => str_repeat('a', 120)]))->assertCreated();
        $this->postJson('/api/v1/tickets', $this->payload(['subject' => str_repeat('a', 4)]))->assertJsonValidationErrors('subject');
        $this->postJson('/api/v1/tickets', $this->payload(['subject' => str_repeat('a', 121)]))->assertJsonValidationErrors('subject');
    }

    public function test_description_boundaries_10_and_2000(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->postJson('/api/v1/tickets', $this->payload(['description' => str_repeat('d', 10)]))->assertCreated();
        $this->postJson('/api/v1/tickets', $this->payload(['description' => str_repeat('d', 2000)]))->assertCreated();
        $this->postJson('/api/v1/tickets', $this->payload(['description' => str_repeat('d', 9)]))->assertJsonValidationErrors('description');
        $this->postJson('/api/v1/tickets', $this->payload(['description' => str_repeat('d', 2001)]))->assertJsonValidationErrors('description');
    }

    public function test_whitespace_only_subject_is_treated_as_missing(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->postJson('/api/v1/tickets', $this->payload(['subject' => '          ']))->assertJsonValidationErrors('subject');
    }

    public function test_malformed_json_is_a_validation_error_not_a_server_error(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->call('POST', '/api/v1/tickets', server: [
            'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json',
        ], content: '{"category": "network", "subject": ')->assertStatus(422);
    }

    public function test_client_cannot_set_server_owned_fields(): void
    {
        $me = User::factory()->create();
        Sanctum::actingAs($me);

        $this->postJson('/api/v1/tickets', $this->payload([
            'status' => 'closed', 'requester_id' => 999, 'reference' => 'HD-HACKED', 'source' => 'email_gateway',
        ]))->assertCreated()
            ->assertJsonPath('data.status', 'open')
            ->assertJsonPath('data.requester.id', $me->id)
            ->assertJsonPath('data.source', 'web');
    }

    public function test_html_in_text_fields_is_stored_and_returned_as_plain_data(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->postJson('/api/v1/tickets', $this->payload(['subject' => '<b>Bold</b> printer']))
            ->assertCreated()
            ->assertJsonPath('data.subject', '<b>Bold</b> printer')
            ->assertHeader('Content-Type', 'application/json');
    }

    public function test_ticket_response_shape_matches_flutter_model(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->postJson('/api/v1/tickets', $this->payload())->assertCreated()->assertJsonStructure(['data' => [
            'id', 'reference', 'category', 'priority', 'status', 'subject', 'description', 'is_overdue',
            'requester' => ['id', 'name'], 'sla_due_at', 'created_at', 'events' => [['action', 'to_status', 'created_at']],
        ]]);
    }

    public function test_list_is_paginated_with_meta(): void
    {
        $me = User::factory()->create();
        \App\Models\Ticket::factory()->count(25)->create(['requester_id' => $me->id]);
        Sanctum::actingAs($me);

        $this->getJson('/api/v1/tickets')->assertOk()->assertJsonCount(20, 'data')->assertJsonPath('meta.total', 25);
        $this->getJson('/api/v1/tickets?page=2')->assertOk()->assertJsonCount(5, 'data');
    }

    public function test_every_api_response_carries_a_correlation_id(): void
    {
        $this->getJson('/api/v1/tickets')->assertUnauthorized()->assertHeader('X-Correlation-Id');
        $this->getJson('/api/v1/tickets', ['X-Correlation-Id' => 'trace-abc-12345'])->assertHeader('X-Correlation-Id', 'trace-abc-12345');
        // Malformed incoming ids are replaced, not echoed (header injection / log forging).
        $this->getJson('/api/v1/tickets', ['X-Correlation-Id' => "bad\nid"])->assertHeader('X-Correlation-Id');
        $this->assertNotSame("bad\nid", $this->getJson('/api/v1/tickets', ['X-Correlation-Id' => 'x'])->headers->get('X-Correlation-Id'));
    }
}
