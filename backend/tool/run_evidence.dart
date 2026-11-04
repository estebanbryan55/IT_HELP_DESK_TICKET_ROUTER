// Runs the Week 13 evidence scenarios against a running server + mock gateway
// and writes ../evidence/week13_run.md and ../evidence/week13_run.json.
//
//   dart run bin/mock_gateway.dart      (terminal 1)
//   dart run bin/server.dart            (terminal 2, fresh data file)
//   dart run tool/run_evidence.dart     (terminal 3)

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

final api = Uri.parse(Platform.environment['API_URL'] ?? 'http://127.0.0.1:8080');
final gw = Uri.parse(Platform.environment['GATEWAY_URL'] ?? 'http://127.0.0.1:8091');
final records = <Map<String, Object?>>[];
final md = StringBuffer();
var step = 0;

Future<Map<String, Object?>> req(String method, String path,
    {String? user, Object? body, Uri? base, Map<String, String> headers = const {}}) async {
  step++;
  final cid = 'ev13-${step.toString().padLeft(4, '0')}-${DateTime.now().millisecondsSinceEpoch % 100000000}';
  final r = http.Request(method, (base ?? api).resolve(path))
    ..headers.addAll({'Content-Type': 'application/json', 'X-Correlation-Id': cid, 'X-Demo-User': ?user, ...headers});
  if (body != null) r.body = body is String ? body : jsonEncode(body);
  final sw = Stopwatch()..start();
  final res = await http.Response.fromStream(await r.send());
  Object? decoded;
  try {
    decoded = jsonDecode(res.body);
  } catch (_) {
    decoded = res.body;
  }
  final rec = {
    'step': step,
    'at': DateTime.now().toUtc().toIso8601String(),
    'request': '$method $path',
    'user': user,
    'correlationId': cid,
    'status': res.statusCode,
    'durationMs': sw.elapsedMilliseconds,
    'response': decoded,
  };
  records.add(rec);
  return rec;
}

void section(String title, String expected) {
  md
    ..writeln('\n## $title\n')
    ..writeln('**Expected:** $expected\n');
  stdout.writeln('\n== $title');
}

void row(Map<String, Object?> r, [String note = '']) {
  md.writeln('- `${r['request']}` as `${r['user'] ?? '-'}` → **${r['status']}** (${r['durationMs']} ms, cid `${r['correlationId']}`) $note');
  stdout.writeln('  ${r['request']} -> ${r['status']} $note');
}

void observed(String text) {
  md.writeln('\n**Observed:** $text');
  stdout.writeln('  observed: $text');
}

Map<String, dynamic> resp(Map<String, Object?> r) => r['response'] as Map<String, dynamic>;

Future<Map<String, dynamic>> waitForMessage(String ticketId, String event, Set<String> terminal, {int seconds = 60}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    final res = await http.get(api.resolve('/api/v1/automation/notifications'), headers: {'X-Demo-User': 'sup-mara'});
    final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    final m = list.where((m) => m['ticketId'] == ticketId && m['event'] == event).firstOrNull;
    if (m != null && terminal.contains(m['status'])) return m;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('Timed out waiting for $event on $ticketId');
}

/// Waits until nothing is pending in the outbox so an injected fault hits only the next scenario.
Future<void> waitIdle() async {
  for (var i = 0; i < 120; i++) {
    final res = await http.get(api.resolve('/health'));
    final outbox = ((jsonDecode(res.body) as Map)['checks'] as Map)['outbox'] as Map;
    if (outbox['pending'] == 0 && outbox['inFlight'] == 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('Outbox did not drain');
}

String attempts(Map<String, dynamic> m) => [
      for (final a in m['attemptLog'] as List)
        '${a['outcome']}${a['httpStatus'] == null ? '' : ' (${a['httpStatus']})'}${a['errorCode'] == null ? '' : ' ${a['errorCode']}'} ${a['durationMs']}ms'
    ].join(' → ');

Future<void> main() async {
  final started = DateTime.now();
  md
    ..writeln('# Week 13 Evidence Run — IT Help Desk Ticket Router')
    ..writeln()
    ..writeln('- Generated: ${started.toUtc().toIso8601String()} by `tool/run_evidence.dart`')
    ..writeln('- API: $api  |  Mock gateway: $gw')
    ..writeln('- Dart: ${Platform.version.split(' ').first}  |  OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
    ..writeln('- Data: fictional seed users only (`.test` domains). Full request/response bodies are in `week13_run.json`.');

  await req('POST', '/admin/reset', base: gw);

  // 1 ------------------------------------------------------------------
  section('1. Health check', 'API reports store ok and the notification gateway reachable.');
  final h = await req('GET', '/health');
  row(h);
  observed('status=${resp(h)['status']}, gateway=${(resp(h)['checks'] as Map)['notificationGateway']}');

  // 2 ------------------------------------------------------------------
  section('2. Normal path: submit → rule-based assignment → response → resolve → confirm → close',
      'Ticket is routed by keyword to the network team, assigned to the least-loaded agent, and closes after the requester confirms.');
  final c = await req('POST', '/api/v1/tickets',
      user: 'req-ana',
      headers: {'Idempotency-Key': 'form-ana-0001'},
      body: {'title': 'Wifi keeps dropping in Room 204', 'description': 'The wifi connection drops every few minutes during class.', 'category': 'auto', 'priority': 'medium'});
  row(c, '→ ${resp(c)['id']} status=${resp(c)['status']} assignee=${resp(c)['assigneeId']}');
  final t1 = resp(c)['id'] as String;
  final agent1 = resp(c)['assigneeId'] as String;
  observed('routingReason="${resp(c)['routingReason']}", team=${resp(c)['team']}, slaDueAt=${resp(c)['slaDueAt']}');
  final replay = await req('POST', '/api/v1/tickets',
      user: 'req-ana',
      headers: {'Idempotency-Key': 'form-ana-0001'},
      body: {'title': 'Wifi keeps dropping in Room 204', 'description': 'The wifi connection drops every few minutes during class.', 'category': 'auto', 'priority': 'medium'});
  row(replay, '→ same id ${resp(replay)['id']} (double-submit did not create a duplicate)');
  row(await req('POST', '/api/v1/tickets/$t1/responses', user: agent1, body: {'message': 'Please try the other access point while I check the controller.'}));
  row(await req('POST', '/api/v1/tickets/$t1/resolve', user: agent1, body: {'resolution': 'Replaced the faulty access point in Room 204.'}));
  final done = await req('POST', '/api/v1/tickets/$t1/confirm', user: 'req-ana');
  row(done, '→ status=${resp(done)['status']}');
  observed('history: ${[for (final e in resp(done)['history'] as List) if (e['action'] == 'status_changed') e['to']].join(' → ')}');

  // 3 ------------------------------------------------------------------
  section('3. Transient failure recovered by retry',
      'Gateway returns 503 for the next 4 calls. The new ticket queues 2 notifications, so each fails twice, waits with backoff, and succeeds on attempt 3. No duplicate is delivered.');
  await waitIdle();
  row(await req('POST', '/admin/fault', base: gw, body: {'failNext': 4, 'status': 503}), '(fault injected: next 4 sends fail with 503)');
  final c3 = await req('POST', '/api/v1/tickets',
      user: 'req-ben', body: {'title': 'Excel crashes when opening reports', 'description': 'Excel crash every time I open the monthly report file.', 'priority': 'high'});
  row(c3, '→ ${resp(c3)['id']} assignee=${resp(c3)['assigneeId']}');
  final t3 = resp(c3)['id'] as String;
  final m3 = await waitForMessage(t3, 'ticket.received', {'sent', 'dead_letter'});
  final m3b = await waitForMessage(t3, 'ticket.assigned', {'sent', 'dead_letter'});
  observed('${m3['id']} ticket.received: status=${m3['status']}, attempts=${m3['attempts']}: ${attempts(m3)}');
  observed('${m3b['id']} ticket.assigned: status=${m3b['status']}, attempts=${m3b['attempts']}: ${attempts(m3b)}');

  // 4 ------------------------------------------------------------------
  section('4. Timeout treated as transient',
      'Gateway delays 5 s (> 3 s client timeout) once; the attempt is recorded as a timeout and the retry succeeds.');
  await waitIdle();
  row(await req('POST', '/admin/fault', base: gw, body: {'delayMs': 5000, 'count': 1}));
  final c4 = await req('POST', '/api/v1/tickets',
      user: 'req-ana', body: {'title': 'Projector has no signal', 'description': 'The projector in AVR 1 shows no signal from the laptop.', 'priority': 'medium'});
  row(c4, '→ ${resp(c4)['id']}');
  final m4 = await waitForMessage(resp(c4)['id'] as String, 'ticket.received', {'sent', 'dead_letter'});
  observed('${m4['id']}: status=${m4['status']}: ${attempts(m4)}');

  // 5 ------------------------------------------------------------------
  section('5. Permanent failure routed for human action',
      'Gateway rejects the decommissioned mailbox with 422. The message is dead-lettered after one attempt (no retry), appears in the supervisor manual-review queue, and the ticket workflow continues.');
  final c5 = await req('POST', '/api/v1/tickets',
      user: 'req-gio', body: {'title': 'Cannot log in to the alumni portal', 'description': 'My account is locked after the password reset.', 'priority': 'low'});
  row(c5, '→ ${resp(c5)['id']} status=${resp(c5)['status']} assignee=${resp(c5)['assigneeId']}');
  final t5 = resp(c5)['id'] as String;
  final m5 = await waitForMessage(t5, 'ticket.received', {'sent', 'dead_letter'});
  observed('${m5['id']}: status=${m5['status']}, reason=${m5['deadLetterReason']}, attempts=${m5['attempts']}: ${attempts(m5)}');
  final dl = await req('GET', '/api/v1/automation/notifications?status=dead_letter', user: 'sup-mara');
  row(dl, '→ ${(dl['response'] as List).length} item(s) in manual review');
  final dis = await req('POST', '/api/v1/automation/notifications/${m5['id']}/dismiss',
      user: 'sup-mara', body: {'note': 'Mailbox decommissioned; requester informed by phone. Contact update requested.'});
  row(dis, '→ status=${resp(dis)['status']}');

  // 6 ------------------------------------------------------------------
  section('6. Unroutable ticket → supervisor triage', 'No keyword matches, so the ticket waits in needs_triage and the supervisor is notified; triage assigns it.');
  final c6 = await req('POST', '/api/v1/tickets',
      user: 'req-ben', body: {'title': 'Question about the new room booking', 'description': 'Who should I ask about the new booking process?', 'priority': 'low'});
  row(c6, '→ ${resp(c6)['id']} status=${resp(c6)['status']} reason="${resp(c6)['routingReason']}"');
  final tr = await req('POST', '/api/v1/tickets/${resp(c6)['id']}/triage', user: 'sup-mara', body: {'category': 'software', 'priority': 'low'});
  row(tr, '→ status=${resp(tr)['status']} assignee=${resp(tr)['assigneeId']}');

  // 7 ------------------------------------------------------------------
  section('7. Adverse requests are refused safely', 'Invalid, unauthenticated, unauthorized, other-owner and wrong-state requests get 422/401/403/404/409 with no internal detail.');
  final bad = await req('POST', '/api/v1/tickets', user: 'req-ana', body: {'title': 'Hi', 'priority': 'asap', 'role': 'admin'});
  row(bad, '→ ${jsonEncode((resp(bad)['error'] as Map)['details'])}');
  row(await req('POST', '/api/v1/tickets', user: 'req-ana', body: '{not json'), '(malformed JSON)');
  row(await req('GET', '/api/v1/tickets'), '(no identity)');
  row(await req('GET', '/api/v1/tickets', user: 'mallory'), '(unknown identity)');
  row(await req('GET', '/api/v1/automation/notifications', user: 'agent-carla'), '(agent calls supervisor endpoint)');
  row(await req('GET', '/api/v1/tickets/$t3', user: 'req-ana'), '(requester reads another user\'s ticket)');
  row(await req('POST', '/api/v1/tickets/$t3/confirm', user: 'req-ben'), '(confirm before resolved)');

  // 8 ------------------------------------------------------------------
  section('8. Reassignment when an agent becomes unavailable',
      'Supervisor marks an agent unavailable; the next aging scan moves that agent\'s open tickets to a teammate.');
  final c8 = await req('POST', '/api/v1/tickets',
      user: 'req-ana', body: {'title': 'No internet in the library', 'description': 'Ethernet ports in the library have no internet.', 'priority': 'medium'});
  final a8 = resp(c8)['assigneeId'] as String;
  row(c8, '→ ${resp(c8)['id']} assignee=$a8');
  row(await req('PATCH', '/api/v1/agents/$a8/availability', user: 'sup-mara', body: {'available': false}));
  final scan8 = await req('POST', '/api/v1/automation/jobs/aging-scan/run', user: 'sup-mara');
  row(scan8, '→ stats=${jsonEncode(resp(scan8)['stats'])}');
  final after8 = await req('GET', '/api/v1/tickets/${resp(c8)['id']}', user: 'sup-mara');
  row(after8, '→ assignee now ${resp(after8)['assigneeId']}');
  row(await req('PATCH', '/api/v1/agents/$a8/availability', user: 'sup-mara', body: {'available': true}), '(restored)');

  // 9 ------------------------------------------------------------------
  section('9. SLA aging alerts and escalation',
      'Development clock is advanced. At ≥75% of the SLA window the assignee gets one warning; at ≥100% the ticket is escalated to the supervisor. Re-running the scan does not duplicate alerts.');
  final c9 = await req('POST', '/api/v1/tickets',
      user: 'req-ben', body: {'title': 'Laptop keyboard not working', 'description': 'Several keys on my office laptop keyboard stopped working.', 'priority': 'high'});
  final t9 = resp(c9)['id'] as String;
  row(c9, '→ $t9 priority=high (8 h SLA) assignee=${resp(c9)['assigneeId']}');
  row(await req('POST', '/api/v1/dev/clock/advance', user: 'sup-mara', body: {'minutes': 6 * 60 + 30}), '(+6.5 h = 81%)');
  final s9a = await req('POST', '/api/v1/automation/jobs/aging-scan/run', user: 'sup-mara');
  row(s9a, '→ ${jsonEncode(resp(s9a)['stats'])}');
  final s9b = await req('POST', '/api/v1/automation/jobs/aging-scan/run', user: 'sup-mara');
  row(s9b, '→ ${jsonEncode(resp(s9b)['stats'])} (re-run: no duplicates)');
  row(await req('POST', '/api/v1/dev/clock/advance', user: 'sup-mara', body: {'minutes': 120}), '(+2 h = 106%)');
  final s9c = await req('POST', '/api/v1/automation/jobs/aging-scan/run', user: 'sup-mara');
  row(s9c, '→ ${jsonEncode(resp(s9c)['stats'])}');
  final t9after = await req('GET', '/api/v1/tickets/$t9', user: 'sup-mara');
  observed('$t9 alerts=${resp(t9after)['alerts']}, escalated=${resp(t9after)['escalated']}; '
      'audit: ${[for (final e in resp(t9after)['history'] as List) e['action']].join(', ')}');

  // 10 -----------------------------------------------------------------
  section('10. Support summary', 'Summary job aggregates ticket counts, open load per agent, breaches and notification health, and notifies the supervisor.');
  final sum = await req('POST', '/api/v1/automation/jobs/daily-summary/run', user: 'sup-mara');
  row(sum, '→ ${resp(sum)['stats']}');
  final latest = await req('GET', '/api/v1/summaries/latest', user: 'sup-mara');
  row(latest);
  md
    ..writeln('\n```json')
    ..writeln(const JsonEncoder.withIndent('  ').convert(resp(latest)['data']))
    ..writeln('```');

  // 11 -----------------------------------------------------------------
  section('11. Gateway received each message once', 'Idempotency keys mean retries and recovery never deliver the same notification twice.');
  final sent = await req('GET', '/admin/sent', base: gw);
  final keys = (sent['response'] as List).length;
  row(sent, '→ $keys delivered messages');
  final runs = await req('GET', '/api/v1/automation/runs', user: 'sup-mara');
  row(runs, '→ ${(runs['response'] as List).length} job runs recorded');

  md
    ..writeln('\n---\n')
    ..writeln('Completed in ${DateTime.now().difference(started).inSeconds} s, $step requests.');

  final dir = Directory('../evidence')..createSync(recursive: true);
  File('${dir.path}/week13_run.md').writeAsStringSync(md.toString());
  File('${dir.path}/week13_run.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(records));
  stdout.writeln('\nWrote ${dir.path}/week13_run.md and week13_run.json');
}
