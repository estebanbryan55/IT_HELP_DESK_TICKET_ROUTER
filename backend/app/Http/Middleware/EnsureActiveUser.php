<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/** Blocks tokens that belong to an account deactivated after the token was issued. */
class EnsureActiveUser
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->user() && ! $request->user()->is_active) {
            $request->user()->currentAccessToken()?->delete();

            return response()->json(['message' => 'Account is disabled.'], 403);
        }

        return $next($request);
    }
}
