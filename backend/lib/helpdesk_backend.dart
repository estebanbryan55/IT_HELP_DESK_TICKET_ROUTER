import 'src/api.dart';
import 'src/automation.dart';
import 'src/config.dart';
import 'src/gateway.dart';
import 'src/logger.dart';
import 'src/outbox.dart';
import 'src/retry.dart';
import 'src/rules.dart';
import 'src/store.dart';
import 'src/tickets.dart';

export 'src/api.dart';
export 'src/automation.dart';
export 'src/config.dart';
export 'src/errors.dart';
export 'src/gateway.dart';
export 'src/logger.dart';
export 'src/models.dart';
export 'src/outbox.dart';
export 'src/retry.dart';
export 'src/rules.dart';
export 'src/store.dart';
export 'src/tickets.dart';

/// Wires every component together. Tests pass their own store, gateway, clock and log.
AppContext buildApp({
  required AppConfig config,
  required JsonStore store,
  required NotificationGateway gateway,
  required Log log,
  Clock? clock,
  RoutingRules? rules,
  RetryPolicy? retryPolicy,
}) {
  final c = clock ?? Clock();
  final outbox = Outbox(
    store: store,
    gateway: gateway,
    clock: c,
    log: log,
    policy: retryPolicy ??
        RetryPolicy(maxAttempts: config.retryMaxAttempts, baseDelay: config.retryBaseDelay, maxDelay: config.retryMaxDelay),
  );
  final tickets = TicketService(
    store: store,
    rules: rules ?? RoutingRules.load(config.rulesFile),
    outbox: outbox,
    config: config,
    clock: c,
    log: log,
  );
  return AppContext(
    config: config,
    store: store,
    clock: c,
    log: log,
    gateway: gateway,
    outbox: outbox,
    tickets: tickets,
    aging: AgingScanner(store: store, tickets: tickets, outbox: outbox, config: config, clock: c, log: log),
    summaries: SummaryService(store: store, outbox: outbox, config: config, clock: c, log: log),
    scheduler: Scheduler(store: store, clock: c, log: log),
  );
}

/// Registers the scheduled jobs and the event-driven nudge for the outbox.
void startAutomation(AppContext ctx) {
  final s = ctx.scheduler;
  Future<Map<String, Object?>> dispatch(String _) async => (await ctx.outbox.dispatchDue()).toJson();

  ctx.outbox.onEnqueued = () => s.runJob('outbox-dispatch', 'event', dispatch, recordIdle: false);
  s.every(ctx.config.outboxPollInterval, 'outbox-dispatch', dispatch, recordIdle: false);
  s.every(ctx.config.agingScanInterval, 'aging-scan', ctx.aging.run);
  s.every(ctx.config.summaryCheckInterval, 'daily-summary', (cid) async {
    final now = ctx.clock.now();
    final localHour = now.add(Duration(hours: ctx.config.timezoneOffsetHours)).hour;
    final date = ctx.summaries.localDate(now);
    if (localHour < ctx.config.summaryHour || ctx.summaries.hasSummaryFor(date)) return {'processed': 0};
    return {'processed': 1, 'summaryId': (await ctx.summaries.generate('scheduled', cid)).id};
  }, recordIdle: false);
}
