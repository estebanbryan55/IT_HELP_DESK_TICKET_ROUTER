<?php

namespace Tests\Feature;

use App\Exceptions\ApiException;
use App\Models\OutboxMessage;
use App\Models\Ticket;
use App\Models\TicketEvent;
use Tests\TestCase;

class WorkflowTest extends TestCase
{
    private function assertApiError(int $status, callable $fn): void
    {
        try {
            $fn();
            $this->fail("expected ApiException $status");
        } catch (ApiException $e) {
            $this->assertSame($status, $e->status, $e->getMessage());
        }
    }

    public function test_complete_normal_path_submit_route_respond_resolve_confirm_close(): void
    {
        $t = $this->tickets();
        $ticket = $t->create($this->user('req-ana'), $this->ticketBody(), null, 'c1');
        $this->assertSame(Ticket::ASSIGNED, $ticket->status);
        $this->assertSame('network', $ticket->team);
        $this->assertSame('agent-carla', $ticket->assignee_id, 'least loaded, tie broken by id');

        $agent = $this->user($ticket->assignee_id);
        $this->assertSame(Ticket::IN_PROGRESS, $t->respond($agent, $ticket->id, ['message' => 'Please restart the access point.'], 'c2')->status);
        $this->assertSame(Ticket::RESOLVED, $t->resolve($agent, $ticket->id, ['resolution' => 'Replaced faulty access point.'], 'c3')->status);
        $closed = $t->confirm($this->user('req-ana'), $ticket->id, 'c4');
        $this->assertSame(Ticket::CLOSED, $closed->status);
        $this->assertSame(
            [Ticket::ASSIGNED, Ticket::IN_PROGRESS, Ticket::RESOLVED, Ticket::CLOSED],
            $closed->history->where('action', 'status_changed')->pluck('to')->values()->all(),
        );
    }

    public function test_assignment_balances_load_across_the_team(): void
    {
        $a = $this->tickets()->create($this->user('req-ana'), $this->ticketBody(), null, 'c');
        $b = $this->tickets()->create($this->user('req-ben'), $this->ticketBody(['title' => 'No internet in library']), null, 'c');
        $this->assertEqualsCanonicalizing(['agent-carla', 'agent-noel'], [$a->assignee_id, $b->assignee_id]);
    }

    public function test_unroutable_ticket_waits_for_supervisor_triage_then_is_assigned(): void
    {
        $t = $this->tickets()->create($this->user('req-ana'),
            $this->ticketBody(['title' => 'General question', 'description' => 'Who do I ask about this thing?']), null, 'c');
        $this->assertSame(Ticket::NEEDS_TRIAGE, $t->status);
        $this->assertTrue(OutboxMessage::where('event', 'ticket.needs_triage')->where('recipient_id', 'sup-mara')->exists());

        $triaged = $this->tickets()->triage($this->user('sup-mara'), $t->id, ['category' => 'software', 'priority' => 'low'], 'c');
        $this->assertSame(Ticket::ASSIGNED, $triaged->status);
        $this->assertSame('agent-dan', $triaged->assignee_id);
    }

    public function test_replayed_idempotency_key_returns_the_same_ticket_instead_of_a_duplicate(): void
    {
        $a = $this->tickets()->create($this->user('req-ana'), $this->ticketBody(), 'form-0001', 'c');
        $b = $this->tickets()->create($this->user('req-ana'), $this->ticketBody(), 'form-0001', 'c');
        $this->assertSame($a->id, $b->id);
        $this->assertSame(1, Ticket::count());
    }

    public function test_invalid_input_is_rejected_with_field_details(): void
    {
        try {
            $this->tickets()->create($this->user('req-ana'), ['title' => 'Hi', 'priority' => 'asap', 'role' => 'admin'], null, 'c');
            $this->fail('expected validation error');
        } catch (ApiException $e) {
            $this->assertSame(422, $e->status);
            foreach (['title', 'description', 'priority', '_'] as $field) {
                $this->assertArrayHasKey($field, $e->details);
            }
        }
    }

    public function test_authorization_wrong_role_or_wrong_owner_is_refused(): void
    {
        $t = $this->tickets()->create($this->user('req-ana'), $this->ticketBody(), null, 'c');
        $this->assertApiError(404, fn () => $this->tickets()->getFor($this->user('req-ben'), $t->id));
        $this->assertApiError(404, fn () => $this->tickets()->getFor($this->user('agent-dan'), $t->id)); // other team
        $this->assertApiError(403, fn () => $this->tickets()->create($this->user('agent-carla'), $this->ticketBody(), null, 'c'));
        $this->assertApiError(403, fn () => $this->tickets()->reassign($this->user('agent-carla'), $t->id, ['agentId' => 'agent-noel', 'reason' => 'busy now'], 'c'));
        $this->assertApiError(409, fn () => $this->tickets()->confirm($this->user('req-ana'), $t->id, 'c')); // not resolved yet
    }

    public function test_a_failed_transaction_leaves_the_store_unchanged(): void
    {
        $t = $this->tickets()->create($this->user('req-ana'), $this->ticketBody(), null, 'c');
        $snapshot = fn () => json_encode([Ticket::all()->toArray(), TicketEvent::all()->toArray(), OutboxMessage::all()->toArray()]);
        $before = $snapshot();
        // Valid input, but the agent is unknown -> validation error inside the transaction.
        $this->assertApiError(422, fn () => $this->tickets()->reassign($this->user('sup-mara'), $t->id, ['agentId' => 'agent-ghost', 'reason' => 'testing rollback'], 'c'));
        $this->assertSame($before, $snapshot());
    }

    public function test_requester_can_reopen_a_resolved_ticket(): void
    {
        $t = $this->tickets()->create($this->user('req-ana'), $this->ticketBody(), null, 'c');
        $this->tickets()->resolve($this->user($t->assignee_id), $t->id, ['resolution' => 'Restarted router.'], 'c');
        $reopened = $this->tickets()->reopen($this->user('req-ana'), $t->id, ['reason' => 'Still dropping'], 'c');
        $this->assertSame(Ticket::IN_PROGRESS, $reopened->status);
        $this->assertNull($reopened->resolved_at);
    }
}
