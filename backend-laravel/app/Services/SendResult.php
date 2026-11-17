<?php

namespace App\Services;

final class SendResult
{
    /** $failure: none | transient | permanent */
    public function __construct(
        public readonly string $failure,
        public readonly int $durationMs,
        public readonly ?int $httpStatus = null,
        public readonly ?string $errorCode = null,
    ) {}

    public function ok(): bool
    {
        return $this->failure === 'none';
    }
}
