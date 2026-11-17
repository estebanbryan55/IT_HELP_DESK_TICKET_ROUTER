<?php

namespace Tests\Feature;

use Tests\TestCase;

class ApiTest extends TestCase
{
    private function as(string $user): array
    {
        return ['X-Demo-User' => $user];
    }

    public function test_requests_without_identity_get_401_with_a_safe_error_body(): void
    {
        $res = $this->getJson('/api/v1/tickets');
        $res->assertStatus(401)->assertJsonPath('error.code', 'unauthenticated');
        $this->assertSame($res->headers->get('X-Correlation-Id'), $res->json('error.correlationId'));
    }

    public function test_correlation_id_from_the_client_is_echoed_when_well_formed(): void
    {
        $this->getJson('/api/v1/me', [...$this->as('req-ana'), 'X-Correlation-Id' => 'demo-12345678'])
            ->assertHeader('X-Correlation-Id', 'demo-12345678');
        $bad = $this->getJson('/api/v1/me', [...$this->as('req-ana'), 'X-Correlation-Id' => 'bad id!']);
        $this->assertNotSame('bad id!', $bad->headers->get('X-Correlation-Id'));
    }

    public function test_create_returns_201_and_validation_returns_422_with_field_details(): void
    {
        $ok = $this->postJson('/api/v1/tickets', $this->ticketBody(), $this->as('req-ana'));
        $ok->assertStatus(201)->assertJsonPath('status', 'assigned')->assertJsonMissingPath('email');
        $this->assertSame('Carla Dizon', $ok->json('assigneeName'));

        $this->postJson('/api/v1/tickets', ['title' => 'x'], $this->as('req-ana'))
            ->assertStatus(422)->assertJsonStructure(['error' => ['details' => ['title']]]);
    }

    public function test_malformed_json_is_a_400_not_a_500(): void
    {
        $this->call('POST', '/api/v1/tickets', [], [], [], ['HTTP_X_DEMO_USER' => 'req-ana', 'CONTENT_TYPE' => 'application/json'], '{not json')
            ->assertStatus(400)->assertJsonPath('error.code', 'bad_request');
        $this->call('POST', '/api/v1/tickets', [], [], [], ['HTTP_X_DEMO_USER' => 'req-ana'], '[1, 2]')
            ->assertStatus(400);
    }

    public function test_automation_endpoints_are_supervisor_only(): void
    {
        $this->getJson('/api/v1/automation/notifications', $this->as('agent-carla'))->assertStatus(403);
        $this->getJson('/api/v1/automation/notifications', $this->as('sup-mara'))->assertOk();
    }

    public function test_notification_list_masks_recipient_addresses(): void
    {
        $this->postJson('/api/v1/tickets', $this->ticketBody(), $this->as('req-ana'));
        $list = $this->getJson('/api/v1/automation/notifications', $this->as('sup-mara'))->json();
        $this->assertNotEmpty($list);
        foreach ($list as $m) {
            $this->assertStringContainsString('***', $m['recipientAddress']);
            $this->assertArrayNotHasKey('body', $m);
        }
    }

    public function test_cors_preflight_allows_the_local_flutter_dev_origin_only(): void
    {
        $this->call('OPTIONS', '/api/v1/tickets', server: ['HTTP_ORIGIN' => 'http://localhost:5173'])
            ->assertStatus(204)->assertHeader('Access-Control-Allow-Origin', 'http://localhost:5173');
        $this->call('OPTIONS', '/api/v1/tickets', server: ['HTTP_ORIGIN' => 'https://evil.example'])
            ->assertStatus(403)->assertHeaderMissing('Access-Control-Allow-Origin');
    }

    public function test_unknown_route_is_a_json_404(): void
    {
        $this->getJson('/api/v1/nope', $this->as('req-ana'))->assertStatus(404)->assertJsonPath('error.code', 'not_found');
        $this->getJson('/', $this->as('req-ana'))->assertStatus(404);
    }

    public function test_job_runs_and_summary_endpoints(): void
    {
        $this->postJson('/api/v1/tickets', $this->ticketBody(), $this->as('req-ana'));
        $this->postJson('/api/v1/automation/jobs/daily-summary/run', [], $this->as('sup-mara'))
            ->assertOk()->assertJsonPath('job', 'daily-summary')->assertJsonPath('status', 'ok');
        $this->getJson('/api/v1/summaries/latest', $this->as('agent-dan'))
            ->assertOk()->assertJsonPath('data.totals.open', 1)->assertJsonPath('trigger', 'manual');
        $this->getJson('/api/v1/automation/runs', $this->as('sup-mara'))->assertOk()->assertJsonCount(1);
        $this->postJson('/api/v1/automation/jobs/unknown/run', [], $this->as('sup-mara'))->assertStatus(404);
    }

    public function test_dev_clock_advance_moves_the_shared_clock(): void
    {
        $this->postJson('/api/v1/dev/clock/advance', ['minutes' => 90], $this->as('sup-mara'))
            ->assertOk()->assertJsonPath('offsetMinutes', 90);
        $this->postJson('/api/v1/dev/clock/advance', ['minutes' => 0], $this->as('sup-mara'))->assertStatus(422);
        $this->postJson('/api/v1/dev/clock/advance', ['minutes' => 5], $this->as('agent-dan'))->assertStatus(403);
    }

    public function test_demo_users_and_agents_hide_email_addresses(): void
    {
        $users = $this->getJson('/api/v1/demo/users')->assertOk()->assertJsonCount(9)->json();
        $this->assertSame('req-ana', $users[0]['id']);
        $this->assertArrayNotHasKey('email', $users[0]);
        $this->getJson('/api/v1/agents', $this->as('sup-mara'))->assertOk()->assertJsonCount(5)->assertJsonPath('0.openTickets', 0);
    }
}
