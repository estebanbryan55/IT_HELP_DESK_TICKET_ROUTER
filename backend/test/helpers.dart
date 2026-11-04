import 'dart:math';

import 'package:helpdesk_backend/helpdesk_backend.dart';

/// Gateway whose responses are scripted per call. Default outcome is success.
class FakeGateway implements NotificationGateway {
  final List<SendResult> script = [];
  final List<OutboxMessage> calls = [];

  void failTransient(int times, {int status = 503}) {
    for (var i = 0; i < times; i++) {
      script.add(SendResult(FailureKind.transient, httpStatus: status, errorCode: 'service_unavailable', durationMs: 5));
    }
  }

  @override
  Future<SendResult> send(OutboxMessage m) async {
    calls.add(m);
    if (m.recipientAddress.endsWith('@invalid.test')) {
      return SendResult(FailureKind.permanent, httpStatus: 422, errorCode: 'recipient_rejected', durationMs: 3);
    }
    if (script.isNotEmpty) return script.removeAt(0);
    return SendResult(FailureKind.none, httpStatus: 202, durationMs: 4);
  }

  @override
  Future<bool> ping() async => true;
}

class TestApp {
  final AppContext ctx;
  final FakeGateway gateway;
  TestApp(this.ctx, this.gateway);

  JsonStore get store => ctx.store;
  AppUser user(String id) => store.state.users[id]!;
  void advance(Duration d) => ctx.clock.offset += d;
}

AppConfig testConfig([Map<String, String> extra = const {}]) => AppConfig.fromMap({
      'GATEWAY_API_KEY': 'test-key',
      'RULES_FILE': 'config/routing_rules.json',
      'DATA_FILE': 'none',
      'LOG_FILE': 'none',
      ...extra,
    });

TestApp makeApp({int maxAttempts = 4}) {
  final gateway = FakeGateway();
  final clock = Clock();
  final ctx = buildApp(
    config: testConfig(),
    store: JsonStore.memory(),
    gateway: gateway,
    clock: clock,
    log: Log(echo: false, now: clock.now),
    retryPolicy: RetryPolicy(
      maxAttempts: maxAttempts,
      baseDelay: const Duration(seconds: 2),
      maxDelay: const Duration(seconds: 30),
      random: Random(42),
    ),
  );
  return TestApp(ctx, gateway);
}

Map<String, dynamic> ticketBody({
  String title = 'Wifi keeps dropping in room 204',
  String description = 'The wifi connection drops every few minutes during class.',
  String category = 'auto',
  String priority = 'medium',
}) =>
    {'title': title, 'description': description, 'category': category, 'priority': priority};
