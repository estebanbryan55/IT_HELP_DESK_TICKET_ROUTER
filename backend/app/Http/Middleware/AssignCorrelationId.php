<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Context;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

/**
 * Gives every request a correlation id (accepted from the client only if it
 * is well-formed) so logs, audit events, and the response can be matched.
 */
class AssignCorrelationId
{
    public function handle(Request $request, Closure $next): Response
    {
        $incoming = (string) $request->header('X-Correlation-Id', '');
        $id = preg_match('/^[A-Za-z0-9\-]{8,64}$/', $incoming) ? $incoming : (string) Str::uuid();

        Context::add('correlation_id', $id);

        $response = $next($request);
        $response->headers->set('X-Correlation-Id', $id);

        return $response;
    }
}
