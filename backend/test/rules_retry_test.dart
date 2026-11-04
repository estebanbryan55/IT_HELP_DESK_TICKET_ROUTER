import 'dart:math';

import 'package:helpdesk_backend/helpdesk_backend.dart';
import 'package:test/test.dart';

void main() {
  final rules = RoutingRules.load('config/routing_rules.json');

  RoutingDecision decide(String title, String desc, {String category = 'auto', String priority = 'medium'}) =>
      rules.decide(title: title, description: desc, requestedCategory: category, requestedPriority: priority);

  group('RoutingRules', () {
    test('routes by keyword to the matching team', () {
      final d = decide('VPN will not connect', 'The vpn says no connection from home.');
      expect(d.category, 'network');
      expect(d.team, 'network');
    });

    test('explicit category from requester wins over keywords', () {
      final d = decide('Printer and wifi', 'printer is jammed', category: 'hardware');
      expect(d.category, 'hardware');
      expect(d.reason, contains('requester'));
    });

    test('no keyword match goes to triage (team null)', () {
      final d = decide('Question about something', 'I have a general question for the office.');
      expect(d.category, 'other');
      expect(d.team, isNull);
    });

    test('equal keyword scores are ambiguous and go to triage', () {
      final d = decide('Printer on the network', 'printer cannot reach the network');
      expect(d.team, isNull);
      expect(d.reason, contains('ambiguous'));
    });

    test('priority keywords raise but never lower priority', () {
      expect(decide('Internet outage', 'whole building has no internet').priority, 'critical');
      expect(decide('Monitor flicker', 'urgent for my exam', priority: 'low').priority, 'high');
      expect(decide('Monitor flicker', 'urgent for my exam', priority: 'critical').priority, 'critical');
    });
  });

  group('RetryPolicy', () {
    final policy = RetryPolicy(
      maxAttempts: 4,
      baseDelay: const Duration(seconds: 2),
      maxDelay: const Duration(seconds: 30),
      random: Random(1),
    );

    test('delay grows exponentially, stays within jitter bounds and the cap', () {
      for (var attempt = 1; attempt <= 8; attempt++) {
        final exp = min(30000, 2000 * pow(2, attempt - 1).toInt());
        final d = policy.delayAfter(attempt).inMilliseconds;
        expect(d, inInclusiveRange(exp ~/ 2, exp), reason: 'attempt $attempt');
      }
    });

    test('attempt budget is bounded', () {
      expect(policy.canRetry(3), isTrue);
      expect(policy.canRetry(4), isFalse);
    });

    test('HTTP status classification', () {
      expect(classifyHttpStatus(202), FailureKind.none);
      for (final s in [408, 429, 500, 502, 503]) {
        expect(classifyHttpStatus(s), FailureKind.transient, reason: '$s');
      }
      for (final s in [400, 401, 403, 404, 422]) {
        expect(classifyHttpStatus(s), FailureKind.permanent, reason: '$s');
      }
    });
  });
}
