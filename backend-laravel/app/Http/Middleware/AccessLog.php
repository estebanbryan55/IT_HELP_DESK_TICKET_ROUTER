<?php

namespace App\Http\Middleware;

use App\Services\StructuredLog;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class AccessLog
{
    public function __construct(private readonly StructuredLog $log) {}

    public function handle(Request $request, Closure $next): Response
    {
        $start = hrtime(true);
        $response = $next($request);
        $this->log->info('http.request', [
            'method' => $request->method(),
            'path' => '/'.ltrim($request->path(), '/'),
            'status' => $response->getStatusCode(),
            'durationMs' => intdiv(hrtime(true) - $start, 1_000_000),
            'userId' => $request->header('X-Demo-User'),
            'correlationId' => $request->attributes->get('cid'),
        ]);

        return $response;
    }
}
