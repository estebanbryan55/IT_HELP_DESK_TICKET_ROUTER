<?php

namespace Tests\Feature;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * Week 15 failure-condition tests: the database or the email gateway is
 * unavailable or slow. The API must fail safely (bounded, generic, traceable)
 * and never leak SQL, file paths, or stack traces.
 */
class DependencyFailureTest extends TestCase
{
    private function breakDatabase(): void
    {
        config([
            'database.connections.sqlite.database' => storage_path('framework/testing/does-not-exist/missing.sqlite'),
            'app.debug' => false,
        ]);
        DB::purge('sqlite');
    }

    /** DEF-04: database outage on a normal API call returns a safe 503 with a reference id. */
    public function test_def04_database_outage_returns_safe_503(): void
    {
        $this->breakDatabase();

        $response = $this->postJson('/api/v1/auth/login', ['email' => 'student@example.test', 'password' => 'whatever']);

        $response->assertStatus(503)
            ->assertJsonPath('message', 'The help desk service is temporarily unavailable. Please try again shortly.')
            ->assertJsonStructure(['message', 'correlation_id'])
            ->assertHeader('Retry-After');
        $this->assertSame($response->headers->get('X-Correlation-Id'), $response->json('correlation_id'));

        $body = $response->getContent();
        foreach (['SQLSTATE', 'sqlite', 'missing.sqlite', 'Exception', '.php'] as $leak) {
            $this->assertStringNotContainsString($leak, $body);
        }
    }

    /** DEF-04: the health endpoint degrades to 503 so a load balancer can stop routing. */
    public function test_def04_health_reports_database_unavailable(): void
    {
        $this->breakDatabase();

        $this->getJson('/api/v1/health')
            ->assertStatus(503)
            ->assertJsonPath('status', 'degraded')
            ->assertJsonPath('checks.database', 'unavailable');
    }

    /** DEF-08: gateway simulator gives up after a bounded number of attempts on timeout. */
    public function test_def08_gateway_timeout_is_bounded_and_reported(): void
    {
        config([
            'security.integration.simulator.key_id' => 'gw-test',
            'security.integration.simulator.url' => 'http://gateway.example.test/api/v1/integrations/email-gateway/tickets',
        ]);
        $attempts = 0;
        Http::fake(function () use (&$attempts) {
            $attempts++;
            throw new ConnectionException('cURL error 28: Operation timed out after 3000 milliseconds');
        });

        $this->artisan('gateway:send')
            ->expectsOutputToContain('Help desk API unreachable after 3 attempts')
            ->assertExitCode(1);

        $this->assertSame(3, $attempts);
    }

    /** DEF-08: a transient failure followed by success is recovered by the retry. */
    public function test_def08_gateway_recovers_from_one_transient_failure(): void
    {
        config([
            'security.integration.simulator.key_id' => 'gw-test',
            'security.integration.simulator.url' => 'http://gateway.example.test/api/v1/integrations/email-gateway/tickets',
        ]);
        $attempts = 0;
        Http::fake(function () use (&$attempts) {
            if (++$attempts === 1) {
                throw new ConnectionException('cURL error 7: Connection refused');
            }

            return Http::response(['reference' => 'HD-2026-000001', 'status' => 'assigned'], 201);
        });

        $this->artisan('gateway:send')->expectsOutputToContain('HTTP 201')->assertExitCode(0);
        $this->assertSame(2, $attempts);
    }
}
