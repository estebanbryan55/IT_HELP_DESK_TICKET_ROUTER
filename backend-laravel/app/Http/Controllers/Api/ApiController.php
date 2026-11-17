<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\ApiException;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

abstract class ApiController
{
    private const MAX_BODY_BYTES = 16 * 1024;

    /**
     * Week 13 demo identity: the X-Demo-User header names a seeded user.
     * The role is looked up on the server; the client never asserts its own role.
     * Replaced by token-based authentication in Week 14.
     */
    protected function auth(Request $request): User
    {
        if (! config('helpdesk.demo_auth_enabled')) {
            throw ApiException::unauthenticated();
        }
        $id = $request->header('X-Demo-User');
        $user = is_string($id) ? User::find($id) : null;

        return $user ?? throw ApiException::unauthenticated();
    }

    /** @param list<string> $roles */
    protected function requireRole(User $u, array $roles): void
    {
        if (! in_array($u->role, $roles, true)) {
            throw ApiException::forbidden();
        }
    }

    /** Parses the raw body: must be empty or a JSON object of at most 16 KB. */
    protected function body(Request $request): array
    {
        $text = $request->getContent();
        if (strlen($text) > self::MAX_BODY_BYTES) {
            throw new ApiException(413, 'payload_too_large', 'Request body is too large.');
        }
        if (trim($text) === '') {
            return [];
        }
        try {
            $decoded = json_decode($text, false, 64, JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            throw new ApiException(400, 'bad_request', 'Body is not valid JSON.');
        }
        if (! $decoded instanceof \stdClass) {
            throw new ApiException(400, 'bad_request', 'Body must be a JSON object.');
        }

        return json_decode($text, true, 64, JSON_THROW_ON_ERROR);
    }

    protected function cid(Request $request): string
    {
        return $request->attributes->get('cid');
    }

    protected function json(mixed $data, int $status = 200): JsonResponse
    {
        return new JsonResponse($data, $status, [], JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION);
    }
}
