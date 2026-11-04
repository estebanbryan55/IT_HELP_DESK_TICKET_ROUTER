import 'package:helpdesk_backend/helpdesk_backend.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late TestApp app;
  setUp(() => app = makeApp());

  /// Runs the dispatcher repeatedly, moving the clock past each retry delay.
  Future<void> drain({int rounds = 10}) async {
    for (var i = 0; i < rounds; i++) {
      await app.ctx.outbox.dispatchDue();
      app.advance(const Duration(seconds: 31));
    }
  }

  OutboxMessage messageFor(String event, String recipient) =>
      app.store.state.outbox.values.singleWhere((m) => m.event == event && m.recipientId == recipient);

  test('transient failure is recovered by retry', () async {
    await app.ctx.tickets.create(app.user('req-ana'), ticketBody(), cid: 'test-transient');
    app.gateway.failTransient(4); // two messages queued (received + assigned): each fails twice

    await drain();

    final m = messageFor('ticket.received', 'req-ana');
    expect(m.status, OutboxStatus.sent);
    expect(m.attempts, 3);
    expect(m.attemptLog.map((a) => a.outcome), ['transient_failure', 'transient_failure', 'sent']);
    expect(app.ctx.log.recent.map((r) => r['event']), contains('notification.sent_after_retry'));
  });

  test('retries stop at the attempt limit and the message is dead-lettered', () async {
    await app.ctx.tickets.create(app.user('req-ana'), ticketBody(), cid: 'test-exhaust');
    app.gateway.failTransient(50);

    await drain(rounds: 12);

    final m = messageFor('ticket.received', 'req-ana');
    expect(m.status, OutboxStatus.deadLetter);
    expect(m.deadLetterReason, 'retries_exhausted');
    expect(m.attempts, 4, reason: 'never more than maxAttempts');
  });

  test('permanent failure goes straight to manual review without retrying', () async {
    await app.ctx.tickets.create(app.user('req-gio'), ticketBody(), cid: 'test-permanent');

    await drain();

    final m = messageFor('ticket.received', 'req-gio');
    expect(m.status, OutboxStatus.deadLetter);
    expect(m.deadLetterReason, 'permanent_rejection');
    expect(m.attempts, 1);
    // The workflow itself was not blocked by the failed notification.
    expect(app.store.state.tickets.values.single.status, TicketStatus.assigned);
  });

  test('enqueue is idempotent for the same key', () async {
    await app.store.transaction((s) {
      final u = s.users['sup-mara']!;
      app.ctx.outbox.enqueue(s, event: 'summary.daily', recipient: u, correlationId: 'x', occurrence: 'SUM-1');
      app.ctx.outbox.enqueue(s, event: 'summary.daily', recipient: u, correlationId: 'x', occurrence: 'SUM-1');
    });
    expect(app.store.state.outbox.length, 1);
  });

  test('messages left in "sending" after a crash are recovered on startup', () async {
    await app.ctx.tickets.create(app.user('req-ana'), ticketBody(), cid: 'test-crash');
    for (final m in app.store.state.outbox.values) {
      m.status = OutboxStatus.sending;
    }
    expect(await app.ctx.outbox.recoverInFlight(), greaterThan(0));
    await drain(rounds: 1);
    expect(app.store.state.outbox.values.every((m) => m.status == OutboxStatus.sent), isTrue);
  });

  test('supervisor can retry or dismiss a dead-lettered message', () async {
    await app.ctx.tickets.create(app.user('req-gio'), ticketBody(), cid: 'test-manual');
    await drain(rounds: 1);
    final m = messageFor('ticket.received', 'req-gio');
    final sup = app.user('sup-mara');

    await expectLater(app.ctx.outbox.dismiss(sup, m.id, 'no', 'c'), throwsA(isA<ApiException>()));
    final dismissed = await app.ctx.outbox.dismiss(sup, m.id, 'Requester contacted by phone instead.', 'c');
    expect(dismissed.status, OutboxStatus.dismissed);
    await expectLater(app.ctx.outbox.manualRetry(sup, m.id, 'c'), throwsA(isA<ApiException>()));
  });
}
