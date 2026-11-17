<?php

use App\Exceptions\ApiException;
use App\Http\Middleware\AccessLog;
use App\Http\Middleware\CorrelationId;
use App\Http\Middleware\Cors;
use App\Services\StructuredLog;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Middleware\HandleCors;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\MethodNotAllowedHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/** Error body shared by every failure: {"error": {code, message, details?, correlationId}}. */
$fail = function (Request $request, int $status, string $code, string $message, ?array $details = null): JsonResponse {
    $error = ['code' => $code, 'message' => $message];
    if ($details !== null) {
        $error['details'] = $details;
    }
    $error['correlationId'] = $request->attributes->get('cid');

    return new JsonResponse(['error' => $error], $status);
};

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        api: __DIR__.'/../routes/api.php',
        apiPrefix: '',
        commands: __DIR__.'/../routes/console.php',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Stateless JSON API: our own CORS rules replace the framework default.
        $middleware->remove(HandleCors::class);
        $middleware->prepend([CorrelationId::class, Cors::class, AccessLog::class]);
        $middleware->api(remove: [\Illuminate\Routing\Middleware\SubstituteBindings::class]);
    })
    ->withExceptions(function (Exceptions $exceptions) use ($fail): void {
        $exceptions->dontReport(ApiException::class);
        $exceptions->shouldRenderJsonWhen(fn () => true);

        $exceptions->render(function (ApiException $e, Request $request) use ($fail) {
            if ($e->status >= 500) {
                app(StructuredLog::class)->error('api.error', ['code' => $e->errorCode, 'correlationId' => $request->attributes->get('cid')]);
            }

            return $fail($request, $e->status, $e->errorCode, $e->getMessage(), $e->details);
        });
        $exceptions->render(fn (NotFoundHttpException|MethodNotAllowedHttpException $e, Request $request) => $fail($request, 404, 'not_found', 'Route was not found.'));
        $exceptions->render(function (Throwable $e, Request $request) use ($fail) {
            // Full detail stays in the protected log; the client gets a generic message.
            app(StructuredLog::class)->error('api.unhandled', [
                'error' => $e->getMessage(),
                'stack' => implode(' | ', array_slice(explode("\n", $e->getTraceAsString()), 0, 5)),
                'correlationId' => $request->attributes->get('cid'),
            ]);

            return $fail($request, 500, 'internal_error', 'Unexpected server error. Quote the correlation id when reporting it.');
        });
    })->create();
