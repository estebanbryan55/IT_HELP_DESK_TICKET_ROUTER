<?php

namespace App\Support;

use Illuminate\Database\LostConnectionDetector;
use Illuminate\Database\SQLiteDatabaseDoesNotExistException;
use PDOException;
use Throwable;

/**
 * Decides whether an exception means "a dependency is down" (answer 503 and
 * let the client retry later) rather than "the code is wrong" (answer 500).
 */
class DependencyFailure
{
    private const UNAVAILABLE_PATTERNS = [
        'unable to open database file',
        'database is locked',
        'No connection could be made',
        'Connection refused',
        'Connection timed out',
        'server has gone away',
    ];

    public static function isDatabaseUnavailable(Throwable $e): bool
    {
        for ($current = $e; $current; $current = $current->getPrevious()) {
            if ($current instanceof SQLiteDatabaseDoesNotExistException) {
                return true;
            }

            if ($current instanceof PDOException || $current instanceof \Illuminate\Database\QueryException) {
                if ((new LostConnectionDetector)->causedByLostConnection($current)) {
                    return true;
                }
                foreach (self::UNAVAILABLE_PATTERNS as $pattern) {
                    if (stripos($current->getMessage(), $pattern) !== false) {
                        return true;
                    }
                }
            }
        }

        return false;
    }
}
