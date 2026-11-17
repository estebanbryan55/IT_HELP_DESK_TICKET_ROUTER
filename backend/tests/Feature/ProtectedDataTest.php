<?php

namespace Tests\Feature;

use App\Models\Ticket;
use App\Models\User;
use Illuminate\Encryption\Encrypter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ProtectedDataTest extends TestCase
{
    use RefreshDatabase;

    public function test_contact_number_and_access_note_are_encrypted_at_rest(): void
    {
        $ticket = Ticket::factory()->create(['contact_number' => '0917 555 0101', 'access_note' => 'Key at front desk']);

        $raw = DB::table('tickets')->where('id', $ticket->id)->first();

        $this->assertStringNotContainsString('0917', $raw->contact_number);
        $this->assertStringNotContainsString('front desk', $raw->access_note);
        $this->assertSame('0917 555 0101', $ticket->fresh()->contact_number);
    }

    public function test_same_plaintext_produces_different_ciphertext(): void
    {
        $a = Ticket::factory()->create(['contact_number' => '0917 555 0101']);
        $b = Ticket::factory()->create(['contact_number' => '0917 555 0101']);

        $this->assertNotSame(
            DB::table('tickets')->where('id', $a->id)->value('contact_number'),
            DB::table('tickets')->where('id', $b->id)->value('contact_number'),
        );
    }

    public function test_altered_ciphertext_is_detected_and_not_returned(): void
    {
        Log::spy();
        $requester = User::factory()->create();
        $ticket = Ticket::factory()->create(['requester_id' => $requester->id, 'contact_number' => '0917 555 0101']);

        // Flip one character inside the encrypted payload's ciphertext.
        $payload = json_decode(base64_decode(DB::table('tickets')->where('id', $ticket->id)->value('contact_number')), true);
        $payload['value'][5] = $payload['value'][5] === 'A' ? 'B' : 'A';
        DB::table('tickets')->where('id', $ticket->id)->update(['contact_number' => base64_encode(json_encode($payload))]);

        Sanctum::actingAs($requester);
        $this->getJson("/api/v1/tickets/{$ticket->id}")
            ->assertOk()
            ->assertJsonPath('data.contact_number', null);

        Log::shouldHaveReceived('warning')->withArgs(fn ($msg) => $msg === 'integrity.decrypt_failed')->once();
    }

    public function test_ciphertext_from_a_different_key_is_rejected(): void
    {
        $ticket = Ticket::factory()->create();
        $foreign = (new Encrypter(random_bytes(32), 'AES-256-CBC'))->encryptString('0917 555 0101');
        DB::table('tickets')->where('id', $ticket->id)->update(['contact_number' => $foreign]);

        $this->assertNull($ticket->fresh()->contact_number);
    }

    public function test_unassigned_agent_never_sees_protected_fields_and_supervisor_does(): void
    {
        $assigned = User::factory()->agent()->create();
        $ticket = Ticket::factory()->assignedTo($assigned)->create([
            'contact_number' => '0917 555 0101', 'access_note' => 'Key at front desk',
        ]);

        Sanctum::actingAs($assigned);
        $this->getJson("/api/v1/tickets/{$ticket->id}")
            ->assertJsonPath('data.contact_number', '0917 555 0101')
            ->assertJsonPath('data.access_note', 'Key at front desk');

        Sanctum::actingAs(User::factory()->supervisor()->create());
        $this->getJson("/api/v1/tickets/{$ticket->id}")->assertJsonPath('data.contact_number', '0917 555 0101');
    }

    public function test_list_endpoint_does_not_expose_protected_fields(): void
    {
        $me = User::factory()->create();
        Ticket::factory()->create(['requester_id' => $me->id, 'contact_number' => '0917 555 0101']);
        Sanctum::actingAs($me);

        $this->getJson('/api/v1/tickets')
            ->assertOk()
            ->assertJsonMissingPath('data.0.contact_number')
            ->assertJsonMissingPath('data.0.access_note')
            ->assertJsonMissingPath('data.0.description');
    }

    public function test_api_responses_never_include_password_hashes(): void
    {
        $me = User::factory()->create();
        Ticket::factory()->create(['requester_id' => $me->id]);
        Sanctum::actingAs($me);

        $body = $this->getJson('/api/v1/tickets')->getContent().$this->getJson('/api/v1/auth/me')->getContent();

        $this->assertStringNotContainsString('password', $body);
        $this->assertStringNotContainsString('$2y$', $body);
    }
}
