<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\ApiException;
use App\Http\Middleware\CorrelationId;
use App\Models\Ticket;
use App\Models\User;
use App\Services\TicketService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class TicketController extends ApiController
{
    public function __construct(private readonly TicketService $tickets) {}

    public function index(Request $request): JsonResponse
    {
        $user = $this->auth($request);
        $status = $request->query('status');
        if ($status !== null && ! in_array($status, Ticket::STATUSES, true)) {
            throw ApiException::validation(['status' => 'Unknown status.']);
        }
        $names = $this->names();

        return $this->json($this->tickets->listFor($user, $status)->map(fn (Ticket $t) => $t->toApi($names))->values());
    }

    public function store(Request $request): JsonResponse
    {
        $user = $this->auth($request);
        $key = $request->header('Idempotency-Key');
        if ($key !== null && ! preg_match(CorrelationId::PATTERN, $key)) {
            throw ApiException::validation(['Idempotency-Key' => 'Must be 8-64 letters, digits or dashes.']);
        }
        $t = $this->tickets->create($user, $this->body($request), $key, $this->cid($request));

        return $this->json($t->toApi($this->names()), 201);
    }

    public function show(Request $request, string $id): JsonResponse
    {
        return $this->view($this->tickets->getFor($this->auth($request), $id));
    }

    public function respond(Request $request, string $id): JsonResponse
    {
        return $this->view($this->tickets->respond($this->auth($request), $id, $this->body($request), $this->cid($request)));
    }

    public function resolve(Request $request, string $id): JsonResponse
    {
        return $this->view($this->tickets->resolve($this->auth($request), $id, $this->body($request), $this->cid($request)));
    }

    public function confirm(Request $request, string $id): JsonResponse
    {
        return $this->view($this->tickets->confirm($this->auth($request), $id, $this->cid($request)));
    }

    public function reopen(Request $request, string $id): JsonResponse
    {
        return $this->view($this->tickets->reopen($this->auth($request), $id, $this->body($request), $this->cid($request)));
    }

    public function reassign(Request $request, string $id): JsonResponse
    {
        return $this->view($this->tickets->reassign($this->auth($request), $id, $this->body($request), $this->cid($request)));
    }

    public function triage(Request $request, string $id): JsonResponse
    {
        return $this->view($this->tickets->triage($this->auth($request), $id, $this->body($request), $this->cid($request)));
    }

    private function view(Ticket $t): JsonResponse
    {
        return $this->json($t->toApi($this->names()));
    }

    /** @return array<string, string> */
    private function names(): array
    {
        return User::pluck('display_name', 'id')->all();
    }
}
