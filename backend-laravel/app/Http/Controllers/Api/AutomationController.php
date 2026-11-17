<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\ApiException;
use App\Models\JobRun;
use App\Models\OutboxMessage;
use App\Models\SupportSummary;
use App\Models\User;
use App\Services\Clock;
use App\Services\JobRunner;
use App\Services\Outbox;
use App\Services\StructuredLog;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AutomationController extends ApiController
{
    public function notifications(Request $request): JsonResponse
    {
        $this->requireRole($this->auth($request), [User::SUPERVISOR]);
        $status = $request->query('status');
        $list = OutboxMessage::when($status !== null, fn ($q) => $q->where('status', $status))
            ->orderByDesc('created_at')->orderByDesc('id')->limit(200)->get();

        return $this->json($list->map->toPublic());
    }

    public function retry(Request $request, Outbox $outbox, string $id): JsonResponse
    {
        $user = $this->auth($request);
        $this->requireRole($user, [User::SUPERVISOR]);

        return $this->json($outbox->manualRetry($user, $id, $this->cid($request))->toPublic());
    }

    public function dismiss(Request $request, Outbox $outbox, string $id): JsonResponse
    {
        $user = $this->auth($request);
        $this->requireRole($user, [User::SUPERVISOR]);
        $note = $this->body($request)['note'] ?? '';

        return $this->json($outbox->dismiss($user, $id, is_string($note) ? $note : '', $this->cid($request))->toPublic());
    }

    public function runs(Request $request): JsonResponse
    {
        $this->requireRole($this->auth($request), [User::SUPERVISOR]);
        $job = $request->query('job');
        $runs = JobRun::when($job !== null, fn ($q) => $q->where('job', $job))->orderByDesc('seq')->limit(100)->get();

        return $this->json($runs->map->toApi());
    }

    public function runJob(Request $request, JobRunner $runner, string $job): JsonResponse
    {
        $this->requireRole($this->auth($request), [User::SUPERVISOR]);
        if (! in_array($job, ['aging-scan', 'outbox-dispatch', 'daily-summary'], true)) {
            throw ApiException::notFound('Job');
        }
        $run = $runner->run($job, 'manual') ?? throw ApiException::conflict('Job is already running.');

        return $this->json($run->toApi());
    }

    public function latestSummary(Request $request): JsonResponse
    {
        $this->requireRole($this->auth($request), [User::SUPERVISOR, User::AGENT]);
        $latest = SupportSummary::orderByDesc('seq')->first() ?? throw ApiException::notFound('Summary');

        return $this->json($latest->toApi());
    }

    /** Development only: moves the shared clock forward so SLA aging can be demonstrated. */
    public function advanceClock(Request $request, Clock $clock, StructuredLog $log): JsonResponse
    {
        if (! config('helpdesk.dev_tools')) {
            throw ApiException::notFound('Resource');
        }
        $user = $this->auth($request);
        $this->requireRole($user, [User::SUPERVISOR]);
        $minutes = $this->body($request)['minutes'] ?? null;
        if (! is_int($minutes) || $minutes < 1 || $minutes > 7 * 24 * 60) {
            throw ApiException::validation(['minutes' => 'Must be 1-10080.']);
        }
        $clock->advance($minutes * 60);
        $offsetMinutes = intdiv($clock->offsetSeconds(), 60);
        $log->warn('dev.clock_advanced', ['minutes' => $minutes, 'offsetMinutes' => $offsetMinutes, 'actorId' => $user->id, 'correlationId' => $this->cid($request)]);

        return $this->json(['now' => Clock::iso($clock->now()), 'offsetMinutes' => $offsetMinutes]);
    }
}
