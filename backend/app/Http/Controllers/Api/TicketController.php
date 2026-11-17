<?php

namespace App\Http\Controllers\Api;

use App\Enums\Role;
use App\Enums\TicketStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\AssignTicketRequest;
use App\Http\Requests\ConfirmTicketRequest;
use App\Http\Requests\StoreTicketRequest;
use App\Http\Requests\TransitionTicketRequest;
use App\Http\Resources\TicketResource;
use App\Models\Ticket;
use App\Models\User;
use App\Services\TicketRouter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;

class TicketController extends Controller
{
    public function __construct(private TicketRouter $router) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        $user = $request->user();

        // Row-level scoping: each role only ever queries the tickets it may see.
        $query = Ticket::query()->with(['requester', 'agent'])->latest('id');
        match ($user->role) {
            Role::Requester => $query->where('requester_id', $user->id),
            Role::Agent => $query->where('assigned_agent_id', $user->id),
            Role::Supervisor => null,
        };

        if ($status = $request->query('status')) {
            $query->where('status', TicketStatus::tryFrom($status)?->value ?? '__none__');
        }

        return TicketResource::collection($query->paginate(20));
    }

    public function store(StoreTicketRequest $request): JsonResponse
    {
        Gate::authorize('create', Ticket::class);

        $ticket = $this->router->open($request->user(), $request->validated());

        return $this->detail($ticket)->response()->setStatusCode(201);
    }

    public function show(Ticket $ticket): TicketResource
    {
        Gate::authorize('view', $ticket);

        return $this->detail($ticket);
    }

    public function transition(TransitionTicketRequest $request, Ticket $ticket): JsonResponse|TicketResource
    {
        Gate::authorize('work', $ticket);

        $to = TicketStatus::from($request->validated('status'));
        if (! $ticket->status->canMoveTo($to)) {
            return response()->json([
                'message' => "A {$ticket->status->value} ticket cannot move to {$to->value}.",
            ], 409);
        }

        $this->router->transition($ticket, $to, $request->user(), $request->validated('note'));

        return $this->detail($ticket);
    }

    public function assign(AssignTicketRequest $request, Ticket $ticket): JsonResponse|TicketResource
    {
        Gate::authorize('assign', $ticket);

        $agent = User::where('id', $request->validated('agent_id'))
            ->where('role', Role::Agent)
            ->where('is_active', true)
            ->first();

        if (! $agent) {
            return response()->json(['message' => 'The selected agent is not available.', 'errors' => [
                'agent_id' => ['The selected agent is not available.'],
            ]], 422);
        }

        $this->router->assign($ticket, $agent, $request->user(), $request->validated('note'));

        return $this->detail($ticket);
    }

    /** Requester accepts the resolution (closes) or rejects it (reopens to in_progress). */
    public function confirm(ConfirmTicketRequest $request, Ticket $ticket): TicketResource
    {
        Gate::authorize('confirm', $ticket);

        $accepted = $request->boolean('accepted');
        $this->router->transition(
            $ticket,
            $accepted ? TicketStatus::Closed : TicketStatus::InProgress,
            $request->user(),
            $request->validated('note') ?? ($accepted ? 'resolution accepted by requester' : null),
        );

        return $this->detail($ticket);
    }

    public function agents(Request $request): JsonResponse
    {
        abort_unless($request->user()->isRole(Role::Supervisor), 403);

        return response()->json(['data' => User::where('role', Role::Agent)->where('is_active', true)
            ->orderBy('name')->get(['id', 'name', 'specialization'])]);
    }

    private function detail(Ticket $ticket): TicketResource
    {
        return new TicketResource($ticket->fresh(['requester', 'agent', 'events']));
    }
}
