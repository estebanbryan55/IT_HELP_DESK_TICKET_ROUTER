<?php

// Mock notification gateway for the controlled test environment.
// It stands in for an email/SMS provider so failures can be injected on purpose.
// Run it with PHP's built-in server (from backend-laravel/):
//
//   php -S 127.0.0.1:8091 gateway/mock_gateway.php
//
//   POST /send            deliver a message (needs Bearer key + Idempotency-Key)
//   POST /admin/fault     {"failNext": 2, "status": 503} or {"delayMs": 5000, "count": 1}
//   POST /admin/reset     clear faults and delivered messages
//   GET  /admin/sent      delivered messages (addresses masked)
//   GET  /health
//
// Any recipient ending in "@invalid.test" is rejected with 422 (permanent failure).
// State is kept in storage/app/mock_gateway_state.json because each request is a new PHP run.

$root = dirname(__DIR__);
$env = [];
foreach (@file("$root/.env", FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
    $line = trim($line);
    if ($line === '' || $line[0] === '#' || ! str_contains($line, '=')) {
        continue;
    }
    [$k, $v] = explode('=', $line, 2);
    $env[trim($k)] = trim(trim($v), '"');
}
$apiKey = getenv('GATEWAY_API_KEY') ?: ($env['GATEWAY_API_KEY'] ?? '');

function respond(array $body, int $status = 200): void
{
    http_response_code($status);
    header('Content-Type: application/json');
    echo json_encode($body, JSON_UNESCAPED_SLASHES);
}

function log_event(string $event, array $fields = []): void
{
    $line = json_encode(['ts' => gmdate('Y-m-d\TH:i:s\Z'), 'service' => 'mock-gateway', 'event' => $event, ...$fields], JSON_UNESCAPED_SLASHES);
    file_put_contents('php://stderr', $line.PHP_EOL);
    @file_put_contents(dirname(__DIR__).'/storage/logs/mock_gateway.log', $line.PHP_EOL, FILE_APPEND | LOCK_EX);
}

function mask(string $a): string
{
    $at = strpos($a, '@');

    return $at === false || $at <= 1 ? '***' : $a[0].'***'.substr($a, $at);
}

/** Runs $fn with the state file locked and saves what it returns as the new state. */
function with_state(callable $fn): mixed
{
    $path = dirname(__DIR__).'/storage/app/mock_gateway_state.json';
    $h = fopen($path, 'c+');
    flock($h, LOCK_EX);
    $raw = stream_get_contents($h);
    $state = json_decode($raw ?: '', true) ?: ['failNext' => 0, 'failStatus' => 503, 'delayCount' => 0, 'delayMs' => 0, 'delivered' => []];
    [$state, $result] = $fn($state);
    ftruncate($h, 0);
    rewind($h);
    fwrite($h, json_encode($state, JSON_UNESCAPED_SLASHES));
    flock($h, LOCK_UN);
    fclose($h);

    return $result;
}

if ($apiKey === '') {
    respond(['error' => 'gateway_not_configured'], 500);
    log_event('missing_api_key', ['hint' => 'Set GATEWAY_API_KEY in .env (see .env.example).']);

    return;
}

$method = $_SERVER['REQUEST_METHOD'];
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$headers = array_change_key_case(getallheaders(), CASE_LOWER);
$input = json_decode(file_get_contents('php://input') ?: '{}', true) ?: [];

match ("$method $path") {
    'GET /health' => respond(['status' => 'ok']),

    'POST /send' => (function () use ($headers, $apiKey, $input) {
        $key = $headers['idempotency-key'] ?? null;
        $cid = $headers['x-correlation-id'] ?? null;
        if (($headers['authorization'] ?? '') !== "Bearer $apiKey") {
            log_event('rejected_auth', ['correlationId' => $cid]);

            return respond(['error' => 'invalid_api_key'], 401);
        }
        if ($key === null) {
            return respond(['error' => 'missing_idempotency_key'], 400);
        }

        // Decide the outcome under the lock; any injected delay happens after it is released.
        [$status, $body, $delayMs] = with_state(function (array $s) use ($key, $cid, $input) {
            if (isset($s['delivered'][$key])) {
                log_event('duplicate_ignored', ['idempotencyKey' => $key, 'correlationId' => $cid]);

                return [$s, [200, ['status' => 'duplicate', 'id' => $s['delivered'][$key]['id']], 0]];
            }
            $delay = 0;
            if ($s['delayCount'] > 0) {
                $s['delayCount']--;
                $delay = $s['delayMs'];
                log_event('injected_delay', ['delayMs' => $delay, 'idempotencyKey' => $key, 'correlationId' => $cid]);
            }
            if ($s['failNext'] > 0) {
                $s['failNext']--;
                log_event('injected_failure', ['status' => $s['failStatus'], 'remaining' => $s['failNext'], 'idempotencyKey' => $key, 'correlationId' => $cid]);

                return [$s, [$s['failStatus'], ['error' => 'service_unavailable'], $delay]];
            }
            $to = (string) ($input['to'] ?? '');
            if (str_ends_with($to, '@invalid.test')) {
                log_event('recipient_rejected', ['to' => mask($to), 'idempotencyKey' => $key, 'correlationId' => $cid]);

                return [$s, [422, ['error' => 'recipient_rejected'], $delay]];
            }
            $id = 'GW-'.(count($s['delivered']) + 1);
            $s['delivered'][$key] = ['id' => $id, 'to' => mask($to), 'subject' => $input['subject'] ?? null, 'at' => gmdate('Y-m-d\TH:i:s\Z')];
            log_event('delivered', ['id' => $id, 'to' => mask($to), 'idempotencyKey' => $key, 'correlationId' => $cid]);

            return [$s, [202, ['status' => 'accepted', 'id' => $id], $delay]];
        });
        if ($delayMs > 0) {
            usleep($delayMs * 1000);
        }
        respond($body, $status);
    })(),

    'POST /admin/fault' => respond(with_state(function (array $s) use ($input) {
        $s['failNext'] = (int) ($input['failNext'] ?? 0);
        $s['failStatus'] = (int) ($input['status'] ?? 503);
        $s['delayMs'] = (int) ($input['delayMs'] ?? 0);
        $s['delayCount'] = isset($input['delayMs']) ? (int) ($input['count'] ?? 1) : 0;
        $out = ['failNext' => $s['failNext'], 'status' => $s['failStatus'], 'delayMs' => $s['delayMs'], 'delayCount' => $s['delayCount']];
        log_event('fault_configured', $out);

        return [$s, $out];
    })),

    'POST /admin/reset' => respond(with_state(fn (array $s) => [
        [...$s, 'failNext' => 0, 'delayCount' => 0, 'delivered' => []], ['status' => 'reset'],
    ])),

    'GET /admin/sent' => respond(with_state(fn (array $s) => [$s, array_values($s['delivered'])])),

    default => respond(['error' => 'not_found'], 404),
};
