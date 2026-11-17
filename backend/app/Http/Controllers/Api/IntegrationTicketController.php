<?php

namespace App\Http\Controllers\Api;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Http\Requests\IntegrationTicketRequest;
use App\Models\User;
use App\Services\TicketRouter;
use Illuminate\Http\JsonResponse;

/**
 * Receives tickets forwarded by the email gateway. The request has already
 * passed VerifyIntegrationSignature (authenticity, integrity, freshness).
 */
class IntegrationTicketController extends Controller
{
    public function store(IntegrationTicketRequest $request, TicketRouter $router): JsonResponse
    {
        $requester = User::where('email', strtolower($request->validated('requester_email')))
            ->where('role', Role::Requester)
            ->where('is_active', true)
            ->first();

        // Unknown senders are not auto-registered; the gateway routes them to manual review.
        if (! $requester) {
            return response()->json(['message' => 'Requester is not registered.'], 422);
        }

        $ticket = $router->open($requester, $request->safe()->except('requester_email'), 'email_gateway');

        return response()->json([
            'reference' => $ticket->reference,
            'status' => $ticket->status->value,
        ], 201);
    }
}
