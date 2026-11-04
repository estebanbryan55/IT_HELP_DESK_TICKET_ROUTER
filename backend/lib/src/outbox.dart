import 'config.dart';
import 'errors.dart';
import 'gateway.dart';
import 'logger.dart';
import 'models.dart';
import 'retry.dart';
import 'store.dart';

/// Message text carries only the ticket number and status (data minimisation):
/// no ticket description or requester details leave the system.
const _templates = <String, String>{
  'ticket.received': 'We received your ticket {ticket}. You will be told when an agent is assigned.',
  'ticket.assigned': 'Ticket {ticket} ({priority}) has been assigned to you.',
  'ticket.needs_triage': 'Ticket {ticket} could not be routed automatically and needs triage.',
  'ticket.response': 'Support replied on ticket {ticket}.',
  'ticket.resolved': 'Ticket {ticket} was marked resolved. Please confirm or reopen it.',
  'ticket.reopened': 'Ticket {ticket} was reopened by the requester.',
  'ticket.closed': 'Ticket {ticket} was confirmed and closed.',
  'ticket.reassigned': 'Ticket {ticket} was reassigned to you.',
  'sla.warning': 'Ticket {ticket} has used {ratio} of its SLA time.',
  'sla.breach': 'Ticket {ticket} has breached its SLA and was escalated.',
  'summary.daily': 'The support summary for {date} is ready.',
};

class DispatchStats {
  int sent = 0, retried = 0, deadLettered = 0;
  int get processed => sent + retried + deadLettered;
  Map<String, Object?> toJson() => {'processed': processed, 'sent': sent, 'retried': retried, 'deadLettered': deadLettered};
}

class Outbox {
  final JsonStore store;
  final NotificationGateway gateway;
  final RetryPolicy policy;
  final Clock clock;
  final Log log;
  final int batchSize;

  /// Called after something is enqueued so delivery starts without waiting for the next poll.
  void Function()? onEnqueued;

  Outbox({
    required this.store,
    required this.gateway,
    required this.policy,
    required this.clock,
    required this.log,
    this.batchSize = 20,
  });

  /// Adds a message inside the caller's transaction (transactional outbox):
  /// the state change and its notification are saved together or not at all.
  /// The idempotency key makes a repeated enqueue a no-op.
  OutboxMessage? enqueue(
    StoreState s, {
    required String event,
    required AppUser recipient,
    required String correlationId,
    String? ticketId,
    String occurrence = '0',
    Map<String, String> vars = const {},
  }) {
    final key = '${ticketId ?? 'system'}:$event:${recipient.id}:$occurrence';
    if (s.outbox.values.any((m) => m.idempotencyKey == key)) {
      log.info('outbox.duplicate_skipped', {'idempotencyKey': key, 'correlationId': correlationId});
      return null;
    }
    var text = _templates[event] ?? event;
    for (final e in {'ticket': ticketId ?? '', ...vars}.entries) {
      text = text.replaceAll('{${e.key}}', e.value);
    }
    final now = clock.now();
    final m = OutboxMessage(
      id: 'MSG-${s.nextSeq('message').toString().padLeft(5, '0')}',
      idempotencyKey: key,
      ticketId: ticketId,
      event: event,
      recipientId: recipient.id,
      recipientAddress: recipient.email,
      subject: '[Help Desk] ${ticketId ?? 'Summary'}: $event',
      body: text,
      correlationId: correlationId,
      createdAt: now,
      status: OutboxStatus.pending,
      attempts: 0,
      nextAttemptAt: now,
    );
    s.outbox[m.id] = m;
    log.info('outbox.enqueued', {
      'messageId': m.id,
      'notificationEvent': event,
      'ticketId': ticketId,
      'recipientId': recipient.id,
      'correlationId': correlationId,
    });
    Future.microtask(() => onEnqueued?.call());
    return m;
  }

  /// Startup recovery: a message left in "sending" means the process stopped mid-call.
  /// It is safe to resend because the gateway de-duplicates by idempotency key.
  Future<int> recoverInFlight() => store.transaction((s) {
        var n = 0;
        for (final m in s.outbox.values.where((m) => m.status == OutboxStatus.sending)) {
          m.status = OutboxStatus.retrying;
          m.nextAttemptAt = clock.now();
          n++;
          log.warn('outbox.recovered_in_flight', {'messageId': m.id, 'correlationId': m.correlationId});
        }
        return n;
      });

  /// Sends every due message once. Gateway calls happen outside the store lock.
  Future<DispatchStats> dispatchDue() async {
    final stats = DispatchStats();
    final due = await store.transaction((s) {
      final now = clock.now();
      final list = s.outbox.values
          .where((m) => OutboxStatus.due.contains(m.status) && !m.nextAttemptAt.isAfter(now))
          .toList()
        ..sort((a, b) => a.nextAttemptAt.compareTo(b.nextAttemptAt));
      final batch = list.take(batchSize).toList();
      for (final m in batch) {
        m.status = OutboxStatus.sending; // checkpoint before the external call
      }
      return [for (final m in batch) m.id];
    });

    for (final id in due) {
      final message = store.read((s) => s.outbox[id]!);
      final result = await gateway.send(message);
      await store.transaction((s) => _recordOutcome(s.outbox[id]!, result, stats));
    }
    return stats;
  }

  void _recordOutcome(OutboxMessage m, SendResult r, DispatchStats stats) {
    final now = clock.now();
    m.attempts++;
    final fields = {
      'messageId': m.id,
      'ticketId': m.ticketId,
      'notificationEvent': m.event,
      'attempt': m.attempts,
      'maxAttempts': policy.maxAttempts,
      'httpStatus': r.httpStatus,
      'errorCode': r.errorCode,
      'durationMs': r.durationMs,
      'correlationId': m.correlationId,
    };

    if (r.ok) {
      m.attemptLog.add(DeliveryAttempt(at: now, outcome: 'sent', httpStatus: r.httpStatus, durationMs: r.durationMs));
      m.status = OutboxStatus.sent;
      m.sentAt = now;
      m.lastErrorCode = null;
      stats.sent++;
      log.info(m.attempts > 1 ? 'notification.sent_after_retry' : 'notification.sent', fields);
      return;
    }

    final transient = r.failure == FailureKind.transient;
    m.attemptLog.add(DeliveryAttempt(
      at: now,
      outcome: transient ? 'transient_failure' : 'permanent_failure',
      httpStatus: r.httpStatus,
      errorCode: r.errorCode,
      durationMs: r.durationMs,
    ));
    m.lastErrorCode = r.errorCode;

    if (transient && policy.canRetry(m.attempts)) {
      final delay = policy.delayAfter(m.attempts);
      m.status = OutboxStatus.retrying;
      m.nextAttemptAt = now.add(delay);
      stats.retried++;
      log.warn('notification.retry_scheduled', {...fields, 'retryInMs': delay.inMilliseconds});
      return;
    }

    m.status = OutboxStatus.deadLetter;
    m.deadLetterReason = transient ? 'retries_exhausted' : 'permanent_rejection';
    stats.deadLettered++;
    log.error('notification.dead_lettered', {...fields, 'reason': m.deadLetterReason, 'action': 'manual_review_required'});
  }

  /// Supervisor action after fixing the cause (e.g. correcting a mailbox).
  Future<OutboxMessage> manualRetry(AppUser actor, String id, String correlationId) => store.transaction((s) {
        final m = s.outbox[id] ?? (throw ApiException.notFound('Notification'));
        if (m.status != OutboxStatus.deadLetter) {
          throw ApiException.conflict('Only dead-lettered notifications can be retried.');
        }
        m.status = OutboxStatus.pending;
        m.attempts = 0; // a fresh retry budget; earlier attempts stay in attemptLog
        m.nextAttemptAt = clock.now();
        m.resolutionNote = 'manual retry by ${actor.id}';
        log.info('notification.manual_retry', {'messageId': id, 'actorId': actor.id, 'correlationId': correlationId});
        Future.microtask(() => onEnqueued?.call());
        return m;
      });

  Future<OutboxMessage> dismiss(AppUser actor, String id, String note, String correlationId) => store.transaction((s) {
        final m = s.outbox[id] ?? (throw ApiException.notFound('Notification'));
        if (m.status != OutboxStatus.deadLetter) {
          throw ApiException.conflict('Only dead-lettered notifications can be dismissed.');
        }
        if (note.trim().length < 5) throw ApiException.validation({'note': 'Explain the resolution (at least 5 characters).'});
        m.status = OutboxStatus.dismissed;
        m.resolutionNote = '${actor.id}: ${note.trim()}';
        log.info('notification.dismissed', {'messageId': id, 'actorId': actor.id, 'correlationId': correlationId});
        return m;
      });
}
