<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TransportSecurityTest extends TestCase
{
    use RefreshDatabase;

    public function test_plain_http_is_refused_when_https_is_required(): void
    {
        config(['security.require_https' => true]);

        $this->postJson('http://localhost/api/v1/auth/login', ['email' => 'a@example.test', 'password' => 'x'])
            ->assertStatus(403)
            ->assertExactJson(['message' => 'HTTPS is required.']);
    }

    public function test_https_request_is_accepted_and_gets_hsts(): void
    {
        config(['security.require_https' => true]);
        User::factory()->create(['email' => 'sam@example.test']);

        $this->postJson('https://localhost/api/v1/auth/login', ['email' => 'sam@example.test', 'password' => 'password'])
            ->assertOk()
            ->assertHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
    }

    public function test_security_headers_are_present_on_api_responses(): void
    {
        $this->getJson('/api/v1/tickets')
            ->assertHeader('X-Content-Type-Options', 'nosniff')
            ->assertHeader('X-Frame-Options', 'DENY')
            ->assertHeader('Referrer-Policy', 'no-referrer')
            ->assertHeader('Cache-Control', 'no-store, private')
            ->assertHeader('X-Correlation-Id');
    }

    public function test_wellformed_correlation_id_is_echoed_and_malformed_one_is_replaced(): void
    {
        $this->getJson('/api/v1/tickets', ['X-Correlation-Id' => 'demo-trace-0001'])
            ->assertHeader('X-Correlation-Id', 'demo-trace-0001');

        $response = $this->getJson('/api/v1/tickets', ['X-Correlation-Id' => "bad\r\nInjected: yes"]);
        $this->assertMatchesRegularExpression('/^[0-9a-f\-]{36}$/', $response->headers->get('X-Correlation-Id'));
    }

    public function test_cors_allows_only_the_configured_frontend_origin(): void
    {
        config(['cors.allowed_origins' => ['http://localhost:5000']]);

        $this->options('/api/v1/tickets', [], [
            'Origin' => 'http://localhost:5000', 'Access-Control-Request-Method' => 'GET',
        ])->assertHeader('Access-Control-Allow-Origin', 'http://localhost:5000');

        // The browser blocks the response because the allowed origin does not match the caller.
        $evil = $this->options('/api/v1/tickets', [], [
            'Origin' => 'https://evil.example', 'Access-Control-Request-Method' => 'GET',
        ]);
        $this->assertNotSame('https://evil.example', $evil->headers->get('Access-Control-Allow-Origin'));
        $this->assertNotSame('*', $evil->headers->get('Access-Control-Allow-Origin'));
    }
}
