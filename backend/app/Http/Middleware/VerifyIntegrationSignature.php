<?php

namespace App\Http\Middleware;

use App\Models\IntegrationNonce;
use App\Services\MessageSigner;
use Closure;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

/**
 * Authenticates messages from the email gateway:
 *   X-Key-Id, X-Timestamp (unix seconds), X-Nonce, X-Signature (hex HMAC-SHA256).
 * Rejects unknown keys, stale/future timestamps, bad signatures (altered body)
 * and reused nonces (replay). Rejections share one generic message so a caller
 * cannot learn which check failed; the reason goes to the protected log.
 */
class VerifyIntegrationSignature
{
    public function handle(Request $request, Closure $next): Response
    {
        $keyId = (string) $request->header('X-Key-Id', '');
        $timestamp = (string) $request->header('X-Timestamp', '');
        $nonce = (string) $request->header('X-Nonce', '');
        $signature = (string) $request->header('X-Signature', '');

        $keys = config('security.integration.keys');
        $tolerance = config('security.integration.tolerance_seconds');

        if ($keyId === '' || ! isset($keys[$keyId])) {
            return $this->reject('unknown_key', $keyId);
        }
        if (! ctype_digit($timestamp) || ! preg_match('/^[A-Za-z0-9\-]{16,64}$/', $nonce) || ! ctype_xdigit($signature)) {
            return $this->reject('malformed_headers', $keyId);
        }
        if (abs(time() - (int) $timestamp) > $tolerance) {
            return $this->reject('expired_timestamp', $keyId);
        }
        if (! MessageSigner::verify($keys[$keyId], (int) $timestamp, $nonce, $request->getContent(), $signature)) {
            return $this->reject('bad_signature', $keyId);
        }

        // Only after the MAC is valid do we record the nonce, so forged traffic cannot fill the table.
        try {
            IntegrationNonce::create(['key_id' => $keyId, 'nonce' => $nonce, 'received_at' => now()]);
        } catch (UniqueConstraintViolationException) {
            Log::warning('integration.rejected', ['reason' => 'replayed_nonce', 'key_id' => $keyId]);

            return response()->json(['message' => 'Duplicate message.'], 409);
        }

        return $next($request);
    }

    private function reject(string $reason, string $keyId): Response
    {
        Log::warning('integration.rejected', ['reason' => $reason, 'key_id' => mb_substr($keyId, 0, 40)]);

        return response()->json(['message' => 'Message authentication failed.'], 401);
    }
}
