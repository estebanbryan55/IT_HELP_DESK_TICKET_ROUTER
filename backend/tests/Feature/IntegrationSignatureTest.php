<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\MessageSigner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class IntegrationSignatureTest extends TestCase
{
    use RefreshDatabase;

    private const URL = '/api/v1/integrations/email-gateway/tickets';
    private const KEY_ID = 'gw-test';
    private const SECRET = 'test-only-secret-not-for-production';

    protected function setUp(): void
    {
        parent::setUp();
        User::factory()->create(['email' => 'student@example.test']);
    }

    private function body(array $overrides = []): string
    {
        return json_encode(array_merge([
            'requester_email' => 'student@example.test',
            'category' => 'software',
            'subject' => 'Cannot open the LMS',
            'description' => 'The LMS shows a blank page after login.',
        ], $overrides));
    }

    private function send(string $body, array $headerOverrides = [], ?string $signedBody = null): TestResponse
    {
        $timestamp = $headerOverrides['X-Timestamp'] ?? (string) time();
        $nonce = $headerOverrides['X-Nonce'] ?? (string) Str::uuid();
        $headers = array_merge([
            'X-Key-Id' => self::KEY_ID,
            'X-Timestamp' => $timestamp,
            'X-Nonce' => $nonce,
            'X-Signature' => MessageSigner::sign(self::SECRET, (int) $timestamp, $nonce, $signedBody ?? $body),
            'Content-Type' => 'application/json',
            'Accept' => 'application/json',
        ], $headerOverrides);

        return $this->call('POST', self::URL, [], [], [], $this->transformHeadersToServerVars($headers), $body);
    }

    public function test_valid_signed_message_creates_ticket(): void
    {
        $this->send($this->body())->assertCreated()->assertJsonPath('status', 'open');
        $this->assertDatabaseHas('tickets', ['source' => 'email_gateway']);
    }

    public function test_altered_body_is_rejected(): void
    {
        $original = $this->body();
        $altered = $this->body(['category' => 'account']);

        $this->send($altered, [], $original)->assertStatus(401)
            ->assertExactJson(['message' => 'Message authentication failed.']);
        $this->assertDatabaseCount('tickets', 0);
    }

    public function test_expired_timestamp_is_rejected(): void
    {
        $this->send($this->body(), ['X-Timestamp' => (string) (time() - 301)])->assertStatus(401);
    }

    public function test_future_timestamp_beyond_tolerance_is_rejected(): void
    {
        $this->send($this->body(), ['X-Timestamp' => (string) (time() + 301)])->assertStatus(401);
    }

    public function test_replayed_message_is_rejected(): void
    {
        $nonce = (string) Str::uuid();
        $timestamp = (string) time();

        $this->send($this->body(), ['X-Nonce' => $nonce, 'X-Timestamp' => $timestamp])->assertCreated();
        $this->send($this->body(), ['X-Nonce' => $nonce, 'X-Timestamp' => $timestamp])->assertStatus(409);
        $this->assertDatabaseCount('tickets', 1);
    }

    public function test_signature_from_wrong_secret_is_rejected(): void
    {
        $nonce = (string) Str::uuid();
        $timestamp = time();
        $forged = MessageSigner::sign('attacker-guess', $timestamp, $nonce, $this->body());

        $this->send($this->body(), ['X-Nonce' => $nonce, 'X-Timestamp' => (string) $timestamp, 'X-Signature' => $forged])
            ->assertStatus(401);
    }

    public function test_unknown_key_id_is_rejected(): void
    {
        $this->send($this->body(), ['X-Key-Id' => 'gw-retired'])->assertStatus(401);
    }

    public function test_missing_headers_are_rejected(): void
    {
        $this->postJson(self::URL, json_decode($this->body(), true))->assertStatus(401);
    }

    public function test_unregistered_requester_is_not_auto_created(): void
    {
        $this->send($this->body(['requester_email' => 'stranger@example.test']))->assertStatus(422);
        $this->assertDatabaseMissing('users', ['email' => 'stranger@example.test']);
    }

    public function test_rejected_forgeries_do_not_consume_nonces(): void
    {
        $nonce = (string) Str::uuid();
        $this->send($this->body(), ['X-Nonce' => $nonce, 'X-Signature' => str_repeat('a', 64)])->assertStatus(401);

        $this->assertDatabaseCount('integration_nonces', 0);
    }
}
