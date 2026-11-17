<?php

namespace App\Services;

/**
 * Bounded exponential backoff with "equal jitter":
 * delay(n) = e/2 + random(0, e/2), where e = min(maxDelay, baseDelay * 2^(n-1)).
 * Jitter spreads retries so many failed messages do not hit the gateway at the same instant.
 */
class RetryPolicy
{
    /** @var callable(int, int): int */
    private $random;

    public function __construct(
        public readonly int $maxAttempts,
        public readonly int $baseDelayMs,
        public readonly int $maxDelayMs,
        ?callable $random = null,
    ) {
        $this->random = $random ?? random_int(...);
    }

    /** $attempt is the number of attempts already made (1 after the first failure). Returns milliseconds. */
    public function delayAfter(int $attempt): int
    {
        $exp = min($this->maxDelayMs, $this->baseDelayMs * (2 ** ($attempt - 1)));
        $half = intdiv($exp, 2);

        return $half + ($half === 0 ? 0 : ($this->random)(0, $half));
    }

    public function canRetry(int $attemptsMade): bool
    {
        return $attemptsMade < $this->maxAttempts;
    }

    /** Classifies a gateway outcome: none | transient | permanent. Only transient failures are retried. */
    public static function classifyHttpStatus(int $status): string
    {
        if ($status >= 200 && $status < 300) {
            return 'none';
        }
        if (in_array($status, [408, 425, 429], true) || $status >= 500) {
            return 'transient';
        }

        return 'permanent'; // other 4xx: bad recipient, bad request, auth problem
    }
}
