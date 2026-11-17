<?php

namespace Tests\Feature;

use App\Models\JobRun;
use App\Models\Ticket;
use App\Services\AgingScanner;
use App\Services\JobRunner;
use App\Services\SummaryService;
use Illuminate\Support\Facades\Cache;
use Tests\TestCase;

class AutomationTest extends TestCase
{
    private function aging(string $cid = 'scan'): array
    {
        return $this->app->make(AgingScanner::class)->run($cid);
    }

    public function test_aging_scan_sends_one_warning_at_75_percent_and_one_breach_escalation_at_100_percent(): void
    {
        // medium priority = 24h SLA
        $t = $this->tickets()->create($this->user('req-ana'), $this->ticketBody(), null, 'c');

        $this->advance(10 * 3600);
        $this->assertSame(0, $this->aging('scan-1')['warnings']);

        $this->advance(9 * 3600); // 19h = 79%
        $this->assertSame(1, $this->aging('scan-2')['warnings']);
        $this->assertSame(0, $this->aging('scan-3')['warnings'], 'no duplicate warning');

        $this->advance(6 * 3600); // 25h
        $this->assertSame(1, $this->aging('scan-4')['breaches']);
        $this->aging('scan-5');

        $this->assertTrue(Ticket::find($t->id)->escalated);
        $this->assertSame(1, $this->countEvent('sla.warning'));
        $this->assertSame(2, $this->countEvent('sla.breach'), 'assignee + supervisor, once each');
    }

    public function test_resolved_tickets_are_not_aged(): void
    {
        $t = $this->tickets()->create($this->user('req-ana'), $this->ticketBody(), null, 'c');
        $this->tickets()->resolve($this->user($t->assignee_id), $t->id, ['resolution' => 'Fixed it quickly.'], 'c');
        $this->advance(3 * 86400);
        $this->assertSame(0, $this->aging()['scanned']);
    }

    public function test_tickets_of_an_unavailable_agent_are_reassigned_to_a_teammate(): void
    {
        $t = $this->tickets()->create($this->user('req-ana'), $this->ticketBody(), null, 'c');
        $first = $t->assignee_id;
        $this->tickets()->setAvailability($this->user('sup-mara'), $first, ['available' => false], 'c');

        $this->assertSame(1, $this->aging()['reassigned']);
        $after = Ticket::find($t->id);
        $this->assertNotSame($first, $after->assignee_id);
        $this->assertSame('network', $after->team);
        $this->assertSame(1, $this->countEvent('ticket.reassigned'));
    }

    public function test_without_a_backup_agent_the_ticket_returns_to_triage(): void
    {
        $t = $this->tickets()->create($this->user('req-ana'),
            $this->ticketBody(['title' => 'Laptop screen cracked', 'description' => 'My laptop screen is cracked.']), null, 'c');
        $this->assertSame('agent-eli', $t->assignee_id);
        $this->tickets()->setAvailability($this->user('sup-mara'), 'agent-eli', ['available' => false], 'c');

        $this->assertSame(1, $this->aging()['sentToTriage']);
        $this->assertSame(Ticket::NEEDS_TRIAGE, Ticket::find($t->id)->status);
    }

    public function test_daily_summary_counts_tickets_and_notification_health(): void
    {
        $this->tickets()->create($this->user('req-ana'), $this->ticketBody(), null, 'c');
        $this->tickets()->create($this->user('req-gio'), $this->ticketBody(['title' => 'Printer jam', 'description' => 'Printer on 2F is jammed.']), null, 'c');
        $this->outbox()->dispatchDue();

        $s = $this->app->make(SummaryService::class)->generate('manual', 'c');
        $this->assertSame(2, $s->data->totals->open);
        $this->assertSame(1, $s->data->notifications->deadLetter);
        $this->assertSame(1, $this->countEvent('summary.daily'));
    }

    public function test_job_runner_skips_a_run_while_the_same_job_is_still_active(): void
    {
        $held = Cache::lock('helpdesk-job:aging-scan', 60);
        $this->assertTrue($held->get()); // a run that is still in progress

        $this->assertNull($this->app->make(JobRunner::class)->run('aging-scan', 'scheduled'));
        $this->assertContains('job.skipped_overlap', $this->logEvents());

        $held->release();
        $this->assertSame('ok', $this->app->make(JobRunner::class)->run('aging-scan', 'scheduled')->status);
    }

    public function test_idle_outbox_runs_are_not_recorded_but_busy_ones_are(): void
    {
        $runner = $this->app->make(JobRunner::class);
        $runner->run('outbox-dispatch', 'scheduled');
        $this->assertSame(0, JobRun::count());

        $this->tickets()->create($this->user('req-ana'), $this->ticketBody(), null, 'c');
        $run = $runner->run('outbox-dispatch', 'scheduled');
        $this->assertSame(2, $run->stats->sent);
        $this->assertSame(1, JobRun::count());
    }
}
