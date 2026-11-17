<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\ApiException;
use App\Models\OutboxMessage;
use App\Models\User;
use App\Services\Clock;
use App\Services\NotificationGateway;
use App\Services\TicketService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class IdentityController extends ApiController
{
    public function health(NotificationGateway $gateway, Clock $clock): JsonResponse
    {
        $gatewayUp = $gateway->ping();
        try {
            $counts = [
                'pending' => OutboxMessage::whereIn('status', OutboxMessage::DUE)->count(),
                'inFlight' => OutboxMessage::where('status', OutboxMessage::SENDING)->count(),
                'deadLetter' => OutboxMessage::where('status', OutboxMessage::DEAD_LETTER)->count(),
            ];
            $storeOk = true;
        } catch (\Throwable) {
            $counts = null;
            $storeOk = false;
        }

        return $this->json([
            'status' => $gatewayUp && $storeOk ? 'ok' : 'degraded',
            'version' => config('helpdesk.version'),
            'time' => Clock::iso($storeOk ? $clock->now() : now()),
            'checks' => [
                'store' => $storeOk ? 'ok' : 'unavailable',
                'notificationGateway' => $gatewayUp ? 'ok' : 'unreachable',
                'outbox' => $counts,
            ],
        ]);
    }

    public function demoUsers(): JsonResponse
    {
        if (! config('helpdesk.demo_auth_enabled')) {
            throw ApiException::notFound('Resource');
        }

        return $this->json(User::orderByRaw($this->seedOrder())->get()->map->toPublic());
    }

    public function me(Request $request): JsonResponse
    {
        return $this->json($this->auth($request)->toPublic());
    }

    public function agents(Request $request): JsonResponse
    {
        $this->requireRole($this->auth($request), [User::SUPERVISOR, User::AGENT]);
        $agents = User::where('role', User::AGENT)->withCount('openTickets')->orderByRaw($this->seedOrder())->get();

        return $this->json($agents->map(fn (User $u) => [...$u->toPublic(), 'openTickets' => $u->open_tickets_count]));
    }

    public function setAvailability(Request $request, TicketService $tickets, string $id): JsonResponse
    {
        $agent = $tickets->setAvailability($this->auth($request), $id, $this->body($request), $this->cid($request));

        return $this->json($agent->toPublic());
    }

    /** Requesters, then agents, then supervisors, the same order the users were seeded in. */
    private function seedOrder(): string
    {
        return DB::getDriverName() === 'mysql'
            ? "FIELD(role, 'requester', 'agent', 'supervisor'), FIELD(id, 'req-ana', 'req-ben', 'req-gio', 'agent-carla', 'agent-noel', 'agent-dan', 'agent-eli', 'agent-faith'), id"
            : "CASE role WHEN 'requester' THEN 0 WHEN 'agent' THEN 1 ELSE 2 END, id";
    }
}
