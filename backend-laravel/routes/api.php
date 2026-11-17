<?php

use App\Http\Controllers\Api\AutomationController;
use App\Http\Controllers\Api\IdentityController;
use App\Http\Controllers\Api\TicketController;
use Illuminate\Support\Facades\Route;

// Contract: ../docs/openapi.yaml. Paths are registered without a prefix (see bootstrap/app.php).

Route::get('/health', [IdentityController::class, 'health']);

Route::prefix('api/v1')->group(function () {
    Route::get('demo/users', [IdentityController::class, 'demoUsers']);
    Route::get('me', [IdentityController::class, 'me']);
    Route::get('agents', [IdentityController::class, 'agents']);
    Route::patch('agents/{id}/availability', [IdentityController::class, 'setAvailability']);

    Route::get('tickets', [TicketController::class, 'index']);
    Route::post('tickets', [TicketController::class, 'store']);
    Route::get('tickets/{id}', [TicketController::class, 'show']);
    Route::post('tickets/{id}/responses', [TicketController::class, 'respond']);
    Route::post('tickets/{id}/resolve', [TicketController::class, 'resolve']);
    Route::post('tickets/{id}/confirm', [TicketController::class, 'confirm']);
    Route::post('tickets/{id}/reopen', [TicketController::class, 'reopen']);
    Route::post('tickets/{id}/reassign', [TicketController::class, 'reassign']);
    Route::post('tickets/{id}/triage', [TicketController::class, 'triage']);

    Route::get('automation/notifications', [AutomationController::class, 'notifications']);
    Route::post('automation/notifications/{id}/retry', [AutomationController::class, 'retry']);
    Route::post('automation/notifications/{id}/dismiss', [AutomationController::class, 'dismiss']);
    Route::get('automation/runs', [AutomationController::class, 'runs']);
    Route::post('automation/jobs/{job}/run', [AutomationController::class, 'runJob']);

    Route::get('summaries/latest', [AutomationController::class, 'latestSummary']);

    Route::post('dev/clock/advance', [AutomationController::class, 'advanceClock']);
});
