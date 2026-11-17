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
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

class TicketController extends Controller
{
    public function __construct(private TicketRouter $router) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        // Week 15 DEF-05: an unknown filter is a client error, not "no results".
        $filters = $request->validate([
            'status' => ['nullable', Rule::enum(TicketStatus::class)],
            'page' => ['nullable', 'integer', 'min:1'],
        ]);
        $user = $request->user();

        // Row-level scoping: each role only ever queries the tickets it may see.
        $query = Ticket::query()->with(['requester', 'agent'])->latest('id');
        match ($user->role) {
            Role::Requester => $query->where('requester_id', $user->id),
            Role::Agent => $query->where('assigned_agent_id', $user->id),
            Role::Supervisor => null,
        };

        if (isset($filters['status'])) {
            $query->where('status', $filters['status']);
        }

        return TicketResource::collection($query->paginate(20));
    }

    public function store(StoreTicketRequest $request): JsonResponse
    {
        Gate::authorize('create', Ticket::class);

        $user = $request->user();
        $key = $request->validated('idempotency_key');
        $data = $request->safe()->except('idempotency_key');
        $hash = hash('sha256', json_encode(collect($data)->sortKeys()->all()));

        // Week 15 DEF-02: a retried or double-clicked submission returns the first ticket.
        if ($key && ($existing = $this->findByKey($user, $key))) {
            return $this->replay($existing, $hash);
        }

        try {
            $ticket = $this->router->open($user, $data, 'web', $key, $hash);
        } catch (UniqueConstraintViolationException $e) {
            // Two identical requests raced past the lookup; the database unique index decided.
            if ($key && ($existing = $this->findByKey($user, $key))) {
                return $this->replay($existing, $hash);
            }
            throw $e;
        }

        return $this->detail($ticket)->response()->setStatusCode(201);
    }

    public function show(Ticket $ticket): TicketResource
    {
        $this->authorizeVisible($ticket);

        return $this->detail($ticket);
    }

    public function transition(TransitionTicketRequest $request, Ticket $ticket): JsonResponse|TicketResource
    {
        $this->authorizeVisible($ticket);
        Gate::authorize('work', $ticket);

        $to = TicketStatus::from($request->validated('status'));
        if (! $ticket->status->canMoveTo($to)) {
            return $this->conflict("A {$ticket->status->value} ticket cannot move to {$to->value}.");
        }

        $this->router->transition($ticket, $to, $request->user(), $request->validated('note'));

        return $this->detail($ticket);
    }

    public function assign(AssignTicketRequest $request, Ticket $ticket): JsonResponse|TicketResource
    {
        $this->authorizeVisible($ticket);
        Gate::authorize('assign', $ticket);

        // Week 15 DEF-03: wrong state is a conflict (409), not a permission problem (403).
        if ($ticket->status === TicketStatus::Closed) {
            return $this->conflict('A closed ticket cannot be reassigned.');
        }

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
    public function confirm(ConfirmTicketRequest $request, Ticket $ticket): JsonResponse|TicketResource
    {
        $this->authorizeVisible($ticket);
        Gate::authorize('confirm', $ticket);

        if ($ticket->status !== TicketStatus::Resolved) {
            return $this->conflict('Only a resolved ticket can be confirmed.');
        }

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

    /**
     * Week 15 DEF-01 (OWASP API1, BOLA): a ticket the caller may not see is
     * reported exactly like a missing one, so ids cannot be probed for existence.
     */
    private function authorizeVisible(Ticket $ticket): void
    {
        if (Gate::denies('view', $ticket)) {
            Log::notice('ticket.access_denied', ['ticket_id' => $ticket->id]);

            throw new NotFoundHttpException;
        }
    }

    private function findByKey(User $user, string $key): ?Ticket
    {
        return Ticket::where('requester_id', $user->id)->where('idempotency_key', $key)->first();
    }

    private function replay(Ticket $existing, string $hash): JsonResponse
    {
        if (! hash_equals((string) $existing->request_hash, $hash)) {
            return $this->conflict('This Idempotency-Key was already used for a different ticket.');
        }
        Log::info('ticket.idempotent_replay', ['ticket' => $existing->reference]);

        return $this->detail($existing)->response()->setStatusCode(200)->header('Idempotent-Replayed', 'true');
    }

    private function conflict(string $message): JsonResponse
    {
        return response()->json(['message' => $message], 409);
    }

    private function detail(Ticket $ticket): TicketResource
    {
        return new TicketResource($ticket->fresh(['requester', 'agent', 'events']));
    }
}
