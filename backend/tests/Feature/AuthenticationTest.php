<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthenticationTest extends TestCase
{
    use RefreshDatabase;

    public function test_valid_login_returns_expiring_bearer_token(): void
    {
        $user = User::factory()->create(['email' => 'sam@example.test']);

        $response = $this->postJson('/api/v1/auth/login', ['email' => 'sam@example.test', 'password' => 'password']);

        $response->assertOk()
            ->assertJsonStructure(['token', 'token_type', 'expires_at', 'user' => ['id', 'name', 'role']])
            ->assertJsonMissingPath('user.email');
        $this->assertMatchesRegularExpression('/^\d+\|hdr_/', $response->json('token'));
        $this->assertNotNull($user->tokens()->first()->expires_at);
    }

    public function test_tokens_are_stored_hashed_not_in_plain_text(): void
    {
        User::factory()->create(['email' => 'sam@example.test']);
        $plain = $this->postJson('/api/v1/auth/login', ['email' => 'sam@example.test', 'password' => 'password'])->json('token');

        $secretPart = explode('|', $plain, 2)[1];
        $this->assertDatabaseMissing('personal_access_tokens', ['token' => $secretPart]);
        $this->assertDatabaseHas('personal_access_tokens', ['token' => hash('sha256', $secretPart)]);
    }

    public function test_wrong_password_and_unknown_email_get_same_generic_error(): void
    {
        User::factory()->create(['email' => 'sam@example.test']);

        $wrong = $this->postJson('/api/v1/auth/login', ['email' => 'sam@example.test', 'password' => 'nope']);
        $unknown = $this->postJson('/api/v1/auth/login', ['email' => 'ghost@example.test', 'password' => 'nope']);

        $wrong->assertStatus(401)->assertExactJson(['message' => 'Invalid credentials.']);
        $unknown->assertStatus(401)->assertExactJson(['message' => 'Invalid credentials.']);
    }

    public function test_deactivated_account_cannot_log_in(): void
    {
        User::factory()->create(['email' => 'sam@example.test', 'is_active' => false]);

        $this->postJson('/api/v1/auth/login', ['email' => 'sam@example.test', 'password' => 'password'])
            ->assertStatus(401);
    }

    public function test_login_is_rate_limited_after_five_attempts(): void
    {
        User::factory()->create(['email' => 'sam@example.test']);

        foreach (range(1, 5) as $_) {
            $this->postJson('/api/v1/auth/login', ['email' => 'sam@example.test', 'password' => 'bad'])->assertStatus(401);
        }

        $this->postJson('/api/v1/auth/login', ['email' => 'sam@example.test', 'password' => 'password'])
            ->assertStatus(429);
    }

    public function test_missing_token_is_rejected(): void
    {
        $this->getJson('/api/v1/tickets')->assertStatus(401);
    }

    public function test_invalid_token_is_rejected(): void
    {
        $this->withToken('hdr_1|forged-token-value')->getJson('/api/v1/tickets')->assertStatus(401);
    }

    public function test_expired_token_is_rejected(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('flutter-web', ['*'], now()->addMinutes(60))->plainTextToken;

        $this->travel(61)->minutes();

        $this->withToken($token)->getJson('/api/v1/tickets')->assertStatus(401);
    }

    public function test_logout_revokes_the_token(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('flutter-web')->plainTextToken;

        $this->withToken($token)->postJson('/api/v1/auth/logout')->assertOk();
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_token_of_account_disabled_after_login_is_rejected(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('flutter-web')->plainTextToken;
        $user->update(['is_active' => false]);

        $this->withToken($token)->getJson('/api/v1/tickets')->assertStatus(403);
    }
}
