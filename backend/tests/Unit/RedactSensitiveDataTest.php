<?php

namespace Tests\Unit;

use App\Logging\RedactSensitiveData;
use PHPUnit\Framework\TestCase;

class RedactSensitiveDataTest extends TestCase
{
    public function test_secret_keys_are_masked_at_any_depth(): void
    {
        $out = RedactSensitiveData::redact([
            'user_id' => 7,
            'password' => 'hunter2',
            'payload' => ['contact_number' => '0917 555 0101', 'subject' => 'Wi-Fi'],
            'headers' => ['Authorization' => 'Bearer hdr_1|abc'],
        ]);

        $this->assertSame(7, $out['user_id']);
        $this->assertSame('[REDACTED]', $out['password']);
        $this->assertSame('[REDACTED]', $out['payload']['contact_number']);
        $this->assertSame('Wi-Fi', $out['payload']['subject']);
        $this->assertSame('[REDACTED]', $out['headers']['Authorization']);
    }

    public function test_bearer_tokens_inside_free_text_are_masked(): void
    {
        $out = RedactSensitiveData::redact(['message' => 'call failed with Bearer hdr_12|s3cr3tT0ken']);

        $this->assertSame('call failed with Bearer [REDACTED]', $out['message']);
    }
}
