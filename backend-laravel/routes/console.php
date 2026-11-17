<?php

use App\Services\JobRunner;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

// Run a job by hand: php artisan helpdesk:job aging-scan
Artisan::command('helpdesk:job {job : aging-scan | outbox-dispatch | daily-summary} {--trigger=manual}', function (JobRunner $runner, string $job) {
    $run = $runner->run($job, $this->option('trigger'));
    $this->line(json_encode($run?->toApi() ?? ['skipped' => 'already running'], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
})->purpose('Run one help desk automation job now');

// Scheduled automation. Start it with: php artisan schedule:work
$poll = config('helpdesk.outbox_poll_seconds');
$dispatch = Schedule::call(fn (JobRunner $r) => $r->run('outbox-dispatch', 'scheduled'))->name('outbox-dispatch');
match (true) {
    $poll <= 1 => $dispatch->everySecond(),
    $poll <= 2 => $dispatch->everyTwoSeconds(),
    $poll <= 5 => $dispatch->everyFiveSeconds(),
    $poll <= 10 => $dispatch->everyTenSeconds(),
    $poll <= 15 => $dispatch->everyFifteenSeconds(),
    $poll <= 30 => $dispatch->everyThirtySeconds(),
    default => $dispatch->everyMinute(),
};
Schedule::call(fn (JobRunner $r) => $r->run('aging-scan', 'scheduled'))->name('aging-scan')->everyMinute();
Schedule::call(fn (JobRunner $r) => $r->run('daily-summary-check', 'scheduled'))->name('daily-summary')->everyMinute();
