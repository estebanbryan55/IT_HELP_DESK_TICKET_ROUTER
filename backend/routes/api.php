<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\IntegrationTicketController;
use App\Http\Controllers\Api\TicketController;
use App\Http\Middleware\VerifyIntegrationSignature;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    Route::post('auth/login', [AuthController::class, 'login'])->middleware('throttle:login');

    Route::middleware(['auth:sanctum', 'active', 'throttle:api'])->group(function () {
        Route::get('auth/me', [AuthController::class, 'me']);
        Route::post('auth/logout', [AuthController::class, 'logout']);

        Route::get('tickets', [TicketController::class, 'index']);
        Route::post('tickets', [TicketController::class, 'store']);
        Route::get('tickets/{ticket}', [TicketController::class, 'show']);
        Route::post('tickets/{ticket}/transition', [TicketController::class, 'transition']);
        Route::post('tickets/{ticket}/assign', [TicketController::class, 'assign']);
        Route::post('tickets/{ticket}/confirm', [TicketController::class, 'confirm']);
        Route::get('agents', [TicketController::class, 'agents']);
    });

    Route::post('integrations/email-gateway/tickets', [IntegrationTicketController::class, 'store'])
        ->middleware([VerifyIntegrationSignature::class, 'throttle:integration']);
});
