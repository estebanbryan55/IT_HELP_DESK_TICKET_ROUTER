<?php

namespace App\Services;

use App\Exceptions\ApiException;
use App\Models\JobRun;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;

/** Runs the automation jobs with an overlap guard and records each run for review. */
class JobRunner
{
    public const JOBS = ['aging-scan', 'outbox-dispatch', 'daily-summary', 'daily-summary-check'];

    public function __construct(
        private readonly Store $store,
        private readonly Outbox $outbox,
        private readonly AgingScanner $aging,
        private readonly SummaryService $summaries,
        private readonly Clock $clock,
        private readonly StructuredLog $log,
    ) {}

    /** Returns null when the job was skipped because a previous run is still active. */
    public function run(string $job, string $trigger): ?JobRun
    {
        [$name, $fn, $recordIdle] = match ($job) {
            'aging-scan' => ['aging-scan', fn (string $cid) => $this->aging->run($cid), true],
            'outbox-dispatch' => ['outbox-dispatch', fn () => $this->outbox->dispatchDue(), false],
            'daily-summary' => ['daily-summary', fn (string $cid) => ['summaryId' => $this->summaries->generate($trigger, $cid)->id], true],
            // Scheduled check: generates the day's summary once the configured local hour has passed.
            'daily-summary-check' => ['daily-summary', fn (string $cid) => $this->summaryCheck($cid), false],
            default => throw ApiException::notFound('Job'),
        };

        $cid = 'job-'.substr((string) Str::uuid(), 0, 8);
        $lock = Cache::lock("helpdesk-job:$name", 600);
        if (! $lock->get()) {
            $this->log->warn('job.skipped_overlap', ['job' => $name, 'trigger' => $trigger, 'correlationId' => $cid]);

            return null;
        }

        $startedAt = $this->clock->now();
        try {
            $stats = $fn($cid);
            $status = 'ok';
        } catch (\Throwable $e) {
            $status = 'failed';
            $stats = ['error' => class_basename($e)];
            $this->log->error('job.failed', ['job' => $name, 'error' => $e->getMessage(), 'correlationId' => $cid]);
        } finally {
            $lock->release();
        }

        $run = new JobRun([
            'id' => $cid, 'job' => $name, 'trigger' => $trigger, 'started_at' => $startedAt,
            'finished_at' => $this->clock->now(), 'status' => $status, 'stats' => (object) $stats, 'correlation_id' => $cid,
        ]);
        $idle = ($stats['processed'] ?? $stats['scanned'] ?? null) === 0;
        if ($recordIdle || ! $idle || $status !== 'ok') {
            $this->store->transaction(function () use ($run) {
                $run->save();
                $keepFrom = JobRun::orderByDesc('seq')->skip(299)->value('seq');
                if ($keepFrom !== null) {
                    JobRun::where('seq', '<', $keepFrom)->delete(); // keep the latest 300
                }
            });
            $this->log->info('job.completed', ['job' => $name, 'trigger' => $trigger, 'status' => $status,
                'durationMs' => $run->durationMs(), ...$stats, 'correlationId' => $cid]);
        }

        return $run;
    }

    private function summaryCheck(string $cid): array
    {
        $now = $this->clock->now();
        $localHour = (int) $now->addHours((int) config('helpdesk.timezone_offset_hours'))->format('G');
        if ($localHour < (int) config('helpdesk.summary_hour') || $this->summaries->hasSummaryFor($this->summaries->localDate($now))) {
            return ['processed' => 0];
        }

        return ['processed' => 1, 'summaryId' => $this->summaries->generate('scheduled', $cid)->id];
    }
}
