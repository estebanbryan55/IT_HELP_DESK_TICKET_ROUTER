import 'package:helpdesk_backend/helpdesk_backend.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late TestApp app;
  setUp(() => app = makeApp());

  Matcher apiError(int status) => throwsA(isA<ApiException>().having((e) => e.status, 'status', status));

  test('complete normal path: submit, route, respond, resolve, confirm, close', () async {
    final t = app.ctx.tickets;
    final ticket = await t.create(app.user('req-ana'), ticketBody(), cid: 'c1');
    expect(ticket.status, TicketStatus.assigned);
    expect(ticket.team, 'network');
    expect(ticket.assigneeId, 'agent-carla', reason: 'least loaded, tie broken by id');

    final agent = app.user(ticket.assigneeId!);
    expect((await t.respond(agent, ticket.id, {'message': 'Please restart the access point.'}, 'c2')).status,
        TicketStatus.inProgress);
    expect((await t.resolve(agent, ticket.id, {'resolution': 'Replaced faulty access point.'}, 'c3')).status,
        TicketStatus.resolved);
    final closed = await t.confirm(app.user('req-ana'), ticket.id, 'c4');
    expect(closed.status, TicketStatus.closed);
    expect(closed.history.where((h) => h.action == 'status_changed').map((h) => h.to),
        [TicketStatus.assigned, TicketStatus.inProgress, TicketStatus.resolved, TicketStatus.closed]);
  });

  test('assignment balances load across the team', () async {
    final a = await app.ctx.tickets.create(app.user('req-ana'), ticketBody(), cid: 'c');
    final b = await app.ctx.tickets.create(app.user('req-ben'), ticketBody(title: 'No internet in library'), cid: 'c');
    expect({a.assigneeId, b.assigneeId}, {'agent-carla', 'agent-noel'});
  });

  test('unroutable ticket waits for supervisor triage, then is assigned', () async {
    final t = await app.ctx.tickets.create(
        app.user('req-ana'), ticketBody(title: 'General question', description: 'Who do I ask about this thing?'),
        cid: 'c');
    expect(t.status, TicketStatus.needsTriage);
    expect(app.store.state.outbox.values.any((m) => m.event == 'ticket.needs_triage' && m.recipientId == 'sup-mara'), isTrue);

    final triaged = await app.ctx.tickets.triage(app.user('sup-mara'), t.id, {'category': 'software', 'priority': 'low'}, 'c');
    expect(triaged.status, TicketStatus.assigned);
    expect(triaged.assigneeId, 'agent-dan');
  });

  test('replayed Idempotency-Key returns the same ticket instead of a duplicate', () async {
    final a = await app.ctx.tickets.create(app.user('req-ana'), ticketBody(), idempotencyKey: 'form-0001', cid: 'c');
    final b = await app.ctx.tickets.create(app.user('req-ana'), ticketBody(), idempotencyKey: 'form-0001', cid: 'c');
    expect(b.id, a.id);
    expect(app.store.state.tickets.length, 1);
  });

  test('invalid input is rejected with field details', () async {
    try {
      await app.ctx.tickets.create(app.user('req-ana'), {'title': 'Hi', 'priority': 'asap', 'role': 'admin'}, cid: 'c');
      fail('expected validation error');
    } on ApiException catch (e) {
      expect(e.status, 422);
      expect(e.details!.keys, containsAll(['title', 'description', 'priority', '_']));
    }
  });

  test('authorization: wrong role or wrong owner is refused', () async {
    final t = await app.ctx.tickets.create(app.user('req-ana'), ticketBody(), cid: 'c');
    expect(() => app.ctx.tickets.getFor(app.user('req-ben'), t.id), apiError(404));
    expect(() => app.ctx.tickets.getFor(app.user('agent-dan'), t.id), apiError(404), reason: 'other team');
    expect(() => app.ctx.tickets.create(app.user('agent-carla'), ticketBody(), cid: 'c'), apiError(403));
    expect(() => app.ctx.tickets.reassign(app.user('agent-carla'), t.id, {'agentId': 'agent-noel', 'reason': 'busy now'}, 'c'),
        apiError(403));
    await expectLater(app.ctx.tickets.confirm(app.user('req-ana'), t.id, 'c'), apiError(409), reason: 'not resolved yet');
  });

  test('a failed transaction leaves the store unchanged', () async {
    final t = await app.ctx.tickets.create(app.user('req-ana'), ticketBody(), cid: 'c');
    final before = app.store.state.toJson().toString();
    // Valid input, but the agent is unknown -> validation error inside the transaction.
    await expectLater(
        app.ctx.tickets.reassign(app.user('sup-mara'), t.id, {'agentId': 'agent-ghost', 'reason': 'testing rollback'}, 'c'),
        apiError(422));
    expect(app.store.state.toJson().toString(), before);
  });

  test('requester can reopen a resolved ticket', () async {
    final t = await app.ctx.tickets.create(app.user('req-ana'), ticketBody(), cid: 'c');
    final agent = app.user(t.assigneeId!);
    await app.ctx.tickets.resolve(agent, t.id, {'resolution': 'Restarted router.'}, 'c');
    final reopened = await app.ctx.tickets.reopen(app.user('req-ana'), t.id, {'reason': 'Still dropping'}, 'c');
    expect(reopened.status, TicketStatus.inProgress);
    expect(reopened.resolvedAt, isNull);
  });
}
