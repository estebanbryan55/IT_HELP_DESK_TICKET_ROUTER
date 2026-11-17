<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Readiness probe for a load balancer or uptime monitor. Reports only
 * ok/unavailable per dependency, never error text, versions, or paths.
 */
class HealthController extends Controller
{
    public function __invoke(): JsonResponse
    {
        $started = microtime(true);
        try {
            DB::select('select 1');
            $database = 'ok';
        } catch (Throwable $e) {
            Log::error('health.database_unavailable', ['exception' => $e::class]);
            $database = 'unavailable';
        }

        $healthy = $database === 'ok';

        return response()->json([
            'status' => $healthy ? 'ok' : 'degraded',
            'checks' => ['database' => $database],
            'duration_ms' => (int) round((microtime(true) - $started) * 1000),
        ], $healthy ? 200 : 503, $healthy ? [] : ['Retry-After' => '30']);
    }
}
