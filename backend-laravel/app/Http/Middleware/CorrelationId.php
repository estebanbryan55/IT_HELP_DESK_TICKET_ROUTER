<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

/** Accepts a well-formed X-Correlation-Id from the client or creates one, and echoes it on every response. */
class CorrelationId
{
    public const PATTERN = '/^[A-Za-z0-9\-]{8,64}$/';

    public function handle(Request $request, Closure $next): Response
    {
        $incoming = $request->header('X-Correlation-Id');
        $cid = is_string($incoming) && preg_match(self::PATTERN, $incoming) ? $incoming : (string) Str::uuid();
        $request->attributes->set('cid', $cid);
        $response = $next($request);
        $response->headers->set('X-Correlation-Id', $cid);

        return $response;
    }
}
