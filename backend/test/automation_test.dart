import 'package:helpdesk_backend/helpdesk_backend.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late TestApp app;
  setUp(() => app = makeApp());

  int count(String event) => app.store.state.outbox.values.where((m) => m.event == event).length;

  test('aging scan sends one warning at 75% and one breach escalation at 100%', () async {
    // medium priority = 24h SLA
    final t = await app.ctx.tickets.create(app.user('req-ana'), ticketBody(), cid: 'c');

    app.advance(const Duration(hours: 10));
    expect((await app.ctx.aging.run('scan-1'))['warnings'], 0);

    app.advance(const Duration(hours: 9)); // 19h = 79%
    expect((await app.ctx.aging.run('scan-2'))['warnings'], 1);
    expect((await app.ctx.aging.run('scan-3'))['warnings'], 0, reason: 'no duplicate warning');

    app.advance(const Duration(hours: 6)); // 25h
    expect((await app.ctx.aging.run('scan-4'))['breaches'], 1);
    await app.ctx.aging.run('scan-5');

    final ticket = app.store.state.tickets[t.id]!;
    expect(ticket.escalated, isTrue);
    expect(count('sla.warning'), 1);
    expect(count('sla.breach'), 2, reason: 'assignee + supervisor, once each');
  });

  test('resolved tickets are not aged', () async {
    final t = await app.ctx.tickets.create(app.user('req-ana'), ticketBody(), cid: 'c');
    await app.ctx.tickets.resolve(app.user(t.assigneeId!), t.id, {'resolution': 'Fixed it quickly.'}, 'c');
    app.advance(const Duration(days: 3));
    final stats = await app.ctx.aging.run('scan');
    expect(stats['scanned'], 0);
  });

  test('tickets of an unavailable agent are reassigned to a teammate', () async {
    final t = await app.ctx.tickets.create(app.user('req-ana'), ticketBody(), cid: 'c');
    final first = t.assigneeId!;
    await app.ctx.tickets.setAvailability(app.user('sup-mara'), first, {'available': false}, 'c');

    final stats = await app.ctx.aging.run('scan');
    expect(stats['reassigned'], 1);
    final after = app.store.state.tickets[t.id]!;
    expect(after.assigneeId, isNot(first));
    expect(after.team, 'network');
    expect(count('ticket.reassigned'), 1);
  });

  test('without a backup agent the ticket returns to triage', () async {
    final t = await app.ctx.tickets.create(app.user('req-ana'), ticketBody(title: 'Laptop screen cracked', description: 'My laptop screen is cracked.'), cid: 'c');
    expect(t.assigneeId, 'agent-eli');
    await app.ctx.tickets.setAvailability(app.user('sup-mara'), 'agent-eli', {'available': false}, 'c');
    final stats = await app.ctx.aging.run('scan');
    expect(stats['sentToTriage'], 1);
    expect(app.store.state.tickets[t.id]!.status, TicketStatus.needsTriage);
  });

  test('daily summary counts tickets and notification health', () async {
    await app.ctx.tickets.create(app.user('req-ana'), ticketBody(), cid: 'c');
    await app.ctx.tickets.create(app.user('req-gio'), ticketBody(title: 'Printer jam', description: 'Printer on 2F is jammed.'), cid: 'c');
    await app.ctx.outbox.dispatchDue();
    final s = await app.ctx.summaries.generate('manual', 'c');
    final totals = s.data['totals'] as Map;
    expect(totals['open'], 2);
    expect((s.data['notifications'] as Map)['deadLetter'], 1);
    expect(count('summary.daily'), 1);
  });

  test('scheduler skips a run while the same job is still active', () async {
    final sched = app.ctx.scheduler;
    final slow = sched.runJob('aging-scan', 'scheduled', (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return {'scanned': 0};
    });
    final overlapping = await sched.runJob('aging-scan', 'scheduled', (_) async => {'scanned': 0});
    expect(overlapping, isNull);
    expect((await slow)!.status, 'ok');
  });
}
