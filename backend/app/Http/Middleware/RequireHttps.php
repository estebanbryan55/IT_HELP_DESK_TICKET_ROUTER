<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Refuses API calls made over plain HTTP. Redirecting would be unsafe for an
 * API because the bearer token has already been sent in clear text, so the
 * request is rejected and the client must be fixed.
 */
class RequireHttps
{
    public function handle(Request $request, Closure $next): Response
    {
        if (config('security.require_https') && ! $request->secure()) {
            return response()->json(['message' => 'HTTPS is required.'], 403);
        }

        return $next($request);
    }
}
