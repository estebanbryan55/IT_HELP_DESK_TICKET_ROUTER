<?php

use App\Http\Middleware\AssignCorrelationId;
use App\Http\Middleware\EnsureActiveUser;
use App\Http\Middleware\RequireHttps;
use App\Http\Middleware\SecurityHeaders;
use App\Support\DependencyFailure;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Context;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\MethodNotAllowedHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // TLS is terminated at the reverse proxy in deployment; trust its X-Forwarded-Proto.
        $middleware->trustProxies(at: env('TRUSTED_PROXIES', '127.0.0.1'));

        $middleware->api(prepend: [
            AssignCorrelationId::class,
            SecurityHeaders::class,
            RequireHttps::class,
        ]);

        $middleware->alias(['active' => EnsureActiveUser::class]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );

        // Generic messages: do not reveal model names, ids, or which policy failed.
        $exceptions->render(fn (NotFoundHttpException $e, Request $request) => $request->is('api/*')
            ? response()->json(['message' => 'Resource not found.'], 404)
            : null);

        $exceptions->render(fn (AccessDeniedHttpException $e, Request $request) => $request->is('api/*')
            ? response()->json(['message' => 'You are not permitted to perform this action.'], 403)
            : null);

        // Week 15 DEF-06: do not echo the route path or the list of supported methods.
        $exceptions->render(fn (MethodNotAllowedHttpException $e, Request $request) => $request->is('api/*')
            ? response()->json(['message' => 'Method not allowed.'], 405)
            : null);

        // Week 15 DEF-04: a database outage is a temporary dependency failure (503 + Retry-After),
        // not a code defect, and must never expose SQL, file paths, or driver messages.
        $exceptions->render(function (Throwable $e, Request $request) {
            if (! $request->is('api/*') || ! DependencyFailure::isDatabaseUnavailable($e)) {
                return null;
            }

            return response()->json([
                'message' => 'The help desk service is temporarily unavailable. Please try again shortly.',
                'correlation_id' => Context::get('correlation_id'),
            ], 503, ['Retry-After' => '30']);
        });

        // Week 15 DEF-04: every API 5xx carries the correlation id so a user can quote it to support;
        // when debug is off, the body is reduced to a generic message.
        $exceptions->respond(function (Response $response, Throwable $e, Request $request) {
            if (! $request->is('api/*') || $response->getStatusCode() < 500) {
                return $response;
            }
            $id = Context::get('correlation_id');
            $response->headers->set('X-Correlation-Id', (string) $id);
            if ($response->getStatusCode() === 503 || config('app.debug')) {
                return $response;
            }

            return response()->json([
                'message' => 'Something went wrong on the server.',
                'correlation_id' => $id,
            ], $response->getStatusCode(), ['X-Correlation-Id' => (string) $id]);
        });

        $exceptions->dontReport([AuthorizationException::class, ModelNotFoundException::class]);
    })->create();
