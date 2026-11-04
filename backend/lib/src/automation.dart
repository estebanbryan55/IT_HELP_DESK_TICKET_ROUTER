import 'dart:async';

import 'package:uuid/uuid.dart';

import 'config.dart';
import 'logger.dart';
import 'models.dart';
import 'outbox.dart';
import 'store.dart';
import 'tickets.dart';

const _uuid = Uuid();

/// Scheduled job: SLA-style aging alerts, escalation, and reassignment away from unavailable agents.
class AgingScanner {
  final JsonStore store;
  final TicketService tickets;
  final Outbox outbox;
  final AppConfig config;
  final Clock clock;
  final Log log;

  AgingScanner({
    required this.store,
    required this.tickets,
    required this.outbox,
    required this.config,
    required this.clock,
    required this.log,
  });

  Future<Map<String, Object?>> run(String cid) => store.transaction((s) {
        final now = clock.now();
        var scanned = 0, warnings = 0, breaches = 0, reassigned = 0, toTriage = 0;
        final supervisors = s.users.values.where((u) => u.role == Roles.supervisor).toList();

        for (final t in s.tickets.values.where((t) => t.isOpen).toList()) {
          scanned++;

          // 1. Reassignment: the current agent was marked unavailable.
          final assignee = t.assigneeId == null ? null : s.users[t.assigneeId];
          if (assignee != null && !assignee.available) {
            final next = tickets.pickAgent(s, t.team!, excludeId: assignee.id);
            if (next != null) {
              tickets.assignTo(s, t, next, 'system:aging', cid, note: 'auto-reassigned: ${assignee.id} unavailable');
              reassigned++;
            } else {
              tickets.sendToTriage(s, t, 'system:aging', cid, 'assignee ${assignee.id} unavailable and no backup in ${t.team}');
              toTriage++;
            }
            t.updatedAt = now;
          }

          // 2. Aging: compare elapsed time with the SLA window.
          final window = t.slaDueAt.difference(t.createdAt).inSeconds;
          final ratio = window <= 0 ? 1.0 : now.difference(t.createdAt).inSeconds / window;
          final owner = t.assigneeId == null ? null : s.users[t.assigneeId];

          if (ratio >= 1.0 && !t.alerts.contains('breach')) {
            t.alerts.add('breach');
            if (!t.alerts.contains('warning')) t.alerts.add('warning'); // a skipped warning is implied
            t.escalated = true;
            t.history.add(AuditEvent(at: now, actor: 'system:aging', action: 'sla_breached', note: 'escalated to supervisor', correlationId: cid));
            for (final r in {?owner, ...supervisors}) {
              outbox.enqueue(s, event: 'sla.breach', recipient: r, ticketId: t.id, correlationId: cid);
            }
            log.warn('sla.breached', {'ticketId': t.id, 'ratio': ratio.toStringAsFixed(2), 'assigneeId': t.assigneeId, 'correlationId': cid});
            breaches++;
          } else if (ratio >= config.slaWarningRatio && ratio < 1.0 && !t.alerts.contains('warning')) {
            t.alerts.add('warning');
            t.history.add(AuditEvent(at: now, actor: 'system:aging', action: 'sla_warning', note: '${(ratio * 100).round()}% of SLA used', correlationId: cid));
            for (final r in owner == null ? supervisors : [owner]) {
              outbox.enqueue(s,
                  event: 'sla.warning', recipient: r, ticketId: t.id, correlationId: cid, vars: {'ratio': '${(ratio * 100).round()}%'});
            }
            log.info('sla.warning', {'ticketId': t.id, 'ratio': ratio.toStringAsFixed(2), 'assigneeId': t.assigneeId, 'correlationId': cid});
            warnings++;
          }
        }
        return {'scanned': scanned, 'warnings': warnings, 'breaches': breaches, 'reassigned': reassigned, 'sentToTriage': toTriage};
      });
}

/// Builds the daily support summary for supervisors.
class SummaryService {
  final JsonStore store;
  final Outbox outbox;
  final AppConfig config;
  final Clock clock;
  final Log log;

  SummaryService({required this.store, required this.outbox, required this.config, required this.clock, required this.log});

  String localDate(DateTime utc) => utc.add(Duration(hours: config.timezoneOffsetHours)).toIso8601String().substring(0, 10);

  bool hasSummaryFor(String date) => store.read((s) => s.summaries.any((x) => x.date == date && x.trigger == 'scheduled'));

  Future<SupportSummary> generate(String trigger, String cid) => store.transaction((s) {
        final now = clock.now();
        final today = localDate(now);
        bool isToday(DateTime? d) => d != null && localDate(d) == today;
        final tickets = s.tickets.values.toList();
        final open = tickets.where((t) => t.isOpen).toList();
        final closedToday = tickets.where((t) => isToday(t.closedAt)).toList();
        final resolvedDurations = [
          for (final t in tickets)
            if (t.resolvedAt != null) t.resolvedAt!.difference(t.createdAt).inMinutes,
        ];

        Map<String, int> countBy(Iterable<Ticket> list, String Function(Ticket) key) {
          final m = <String, int>{};
          for (final t in list) {
            m[key(t)] = (m[key(t)] ?? 0) + 1;
          }
          return m;
        }

        final msgs = s.outbox.values.toList();
        final data = <String, Object?>{
          'totals': {
            'all': tickets.length,
            'open': open.length,
            'submittedToday': tickets.where((t) => isToday(t.createdAt)).length,
            'closedToday': closedToday.length,
            'breachedOpen': open.where((t) => t.alerts.contains('breach')).length,
            'awaitingTriage': open.where((t) => t.status == TicketStatus.needsTriage).length,
          },
          'byStatus': countBy(tickets, (t) => t.status),
          'openByCategory': countBy(open, (t) => t.category),
          'openByAgent': countBy(open.where((t) => t.assigneeId != null), (t) => t.assigneeId!),
          'avgResolutionMinutes': resolvedDurations.isEmpty
              ? null
              : (resolvedDurations.reduce((a, b) => a + b) / resolvedDurations.length).round(),
          'notifications': {
            'sent': msgs.where((m) => m.status == OutboxStatus.sent).length,
            'sentAfterRetry': msgs.where((m) => m.status == OutboxStatus.sent && m.attemptLog.length > 1).length,
            'pendingOrRetrying': msgs.where((m) => OutboxStatus.due.contains(m.status)).length,
            'deadLetter': msgs.where((m) => m.status == OutboxStatus.deadLetter).length,
          },
        };
        final summary = SupportSummary(id: 'SUM-${s.nextSeq('summary')}', date: today, generatedAt: now, trigger: trigger, data: data);
        s.summaries.add(summary);
        if (s.summaries.length > 60) s.summaries.removeAt(0);
        for (final sup in s.users.values.where((u) => u.role == Roles.supervisor)) {
          outbox.enqueue(s,
              event: 'summary.daily', recipient: sup, correlationId: cid, occurrence: summary.id, vars: {'date': today});
        }
        log.info('summary.generated', {'summaryId': summary.id, 'date': today, 'trigger': trigger, 'open': open.length, 'correlationId': cid});
        return summary;
      });
}

/// Runs periodic jobs with an overlap guard and records each run for review.
class Scheduler {
  final JsonStore store;
  final Clock clock;
  final Log log;
  final _running = <String>{};
  final _timers = <Timer>[];

  Scheduler({required this.store, required this.clock, required this.log});

  void every(Duration interval, String job, Future<Map<String, Object?>> Function(String cid) fn, {bool recordIdle = true}) {
    _timers.add(Timer.periodic(interval, (_) => runJob(job, 'scheduled', fn, recordIdle: recordIdle)));
  }

  /// Returns null when the job was skipped because a previous run is still active.
  Future<JobRun?> runJob(String job, String trigger, Future<Map<String, Object?>> Function(String cid) fn,
      {bool recordIdle = true}) async {
    final cid = 'job-${_uuid.v4().substring(0, 8)}';
    if (!_running.add(job)) {
      log.warn('job.skipped_overlap', {'job': job, 'trigger': trigger, 'correlationId': cid});
      return null;
    }
    final run = JobRun(id: cid, job: job, trigger: trigger, startedAt: clock.now(), status: 'running', correlationId: cid);
    try {
      run.stats = await fn(cid);
      run.status = 'ok';
    } catch (e) {
      run.status = 'failed';
      run.stats = {'error': e.runtimeType.toString()};
      log.error('job.failed', {'job': job, 'error': e.toString(), 'correlationId': cid});
    } finally {
      run.finishedAt = clock.now();
      _running.remove(job);
    }
    final idle = (run.stats['processed'] ?? run.stats['scanned']) == 0;
    if (recordIdle || !idle || run.status != 'ok') {
      await store.transaction((s) {
        s.jobRuns.add(run);
        if (s.jobRuns.length > 300) s.jobRuns.removeAt(0);
      });
      log.info('job.completed', {'job': job, 'trigger': trigger, 'status': run.status, 'durationMs': run.durationMs, ...run.stats, 'correlationId': cid});
    }
    return run;
  }

  void stop() {
    for (final t in _timers) {
      t.cancel();
    }
  }
}
