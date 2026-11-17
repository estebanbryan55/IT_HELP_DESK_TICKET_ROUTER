<?php

namespace App\Exceptions;

use RuntimeException;

/** An error that is safe to return to the client as-is. */
class ApiException extends RuntimeException
{
    /** @param array<string, string>|null $details */
    public function __construct(
        public readonly int $status,
        public readonly string $errorCode,
        string $message,
        public readonly ?array $details = null,
    ) {
        parent::__construct($message);
    }

    /** @param array<string, string> $details */
    public static function validation(array $details): self
    {
        return new self(422, 'validation_failed', 'One or more fields are invalid.', $details);
    }

    public static function unauthenticated(): self
    {
        return new self(401, 'unauthenticated', 'Sign in is required.');
    }

    public static function forbidden(string $message = 'You are not allowed to perform this action.'): self
    {
        return new self(403, 'forbidden', $message);
    }

    public static function notFound(string $what): self
    {
        return new self(404, 'not_found', "$what was not found.");
    }

    public static function conflict(string $message): self
    {
        return new self(409, 'invalid_state', $message);
    }
}
