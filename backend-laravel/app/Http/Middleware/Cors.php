<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/** Allows only the configured local Flutter dev origins ("http://localhost:*" = any port). */
class Cors
{
    public function handle(Request $request, Closure $next): Response
    {
        $origin = $request->header('Origin');
        $ok = is_string($origin) && self::originAllowed($origin, config('helpdesk.allowed_origins'));
        $headers = $ok ? [
            'Access-Control-Allow-Origin' => $origin,
            'Access-Control-Allow-Methods' => 'GET, POST, PATCH, OPTIONS',
            'Access-Control-Allow-Headers' => 'Content-Type, X-Demo-User, Idempotency-Key, X-Correlation-Id',
            'Access-Control-Expose-Headers' => 'X-Correlation-Id',
            'Vary' => 'Origin',
        ] : [];

        $response = $request->isMethod('OPTIONS') ? response('', $ok ? 204 : 403) : $next($request);
        foreach ($headers as $k => $v) {
            $response->headers->set($k, $v);
        }

        return $response;
    }

    /** @param list<string> $allowed */
    public static function originAllowed(string $origin, array $allowed): bool
    {
        foreach ($allowed as $pattern) {
            if (str_ends_with($pattern, ':*')) {
                $prefix = substr($pattern, 0, -1);
                if (str_starts_with($origin, $prefix) && preg_match('/^\d+$/', substr($origin, strlen($prefix)))) {
                    return true;
                }
            } elseif ($origin === $pattern) {
                return true;
            }
        }

        return false;
    }
}
