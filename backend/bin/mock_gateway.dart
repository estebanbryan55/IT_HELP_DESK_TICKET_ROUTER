// Mock notification gateway for the controlled test environment.
// It stands in for an email/SMS provider so failures can be injected on purpose.
//
//   POST /send            deliver a message (needs Bearer key + Idempotency-Key)
//   POST /admin/fault     {"failNext": 2, "status": 503} or {"delayMs": 5000, "count": 1}
//   POST /admin/reset     clear faults and delivered messages
//   GET  /admin/sent      delivered messages (addresses masked)
//   GET  /health
//
// Any recipient ending in "@invalid.test" is rejected with 422 (permanent failure).

import 'dart:convert';
import 'dart:io';

import 'package:helpdesk_backend/helpdesk_backend.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main() async {
  final settings = loadSettings();
  final apiKey = settings['GATEWAY_API_KEY'] ?? '';
  final port = int.tryParse(settings['MOCK_GATEWAY_PORT'] ?? '') ?? 8091;
  if (apiKey.isEmpty) {
    stderr.writeln('GATEWAY_API_KEY is not set (see .env.example).');
    exit(1);
  }

  var failNext = 0, failStatus = 503, delayCount = 0, delayMs = 0;
  final delivered = <String, Map<String, Object?>>{}; // idempotency key -> record

  Response json(Object body, [int status = 200]) =>
      Response(status, body: jsonEncode(body), headers: {'Content-Type': 'application/json'});
  void log(String event, Map<String, Object?> f) =>
      stdout.writeln(jsonEncode({'ts': DateTime.now().toUtc().toIso8601String(), 'service': 'mock-gateway', 'event': event, ...f}));

  final r = Router()
    ..get('/health', (Request _) => json({'status': 'ok'}))
    ..post('/send', (Request req) async {
      final key = req.headers['idempotency-key'];
      final cid = req.headers['x-correlation-id'];
      if (req.headers['authorization'] != 'Bearer $apiKey') {
        log('rejected_auth', {'correlationId': cid});
        return json({'error': 'invalid_api_key'}, 401);
      }
      if (key == null) return json({'error': 'missing_idempotency_key'}, 400);
      if (delivered.containsKey(key)) {
        log('duplicate_ignored', {'idempotencyKey': key, 'correlationId': cid});
        return json({'status': 'duplicate', 'id': delivered[key]!['id']});
      }
      if (delayCount > 0) {
        delayCount--;
        log('injected_delay', {'delayMs': delayMs, 'idempotencyKey': key, 'correlationId': cid});
        await Future.delayed(Duration(milliseconds: delayMs));
      }
      if (failNext > 0) {
        failNext--;
        log('injected_failure', {'status': failStatus, 'remaining': failNext, 'idempotencyKey': key, 'correlationId': cid});
        return json({'error': 'service_unavailable'}, failStatus);
      }
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final to = body['to'] as String? ?? '';
      if (to.endsWith('@invalid.test')) {
        log('recipient_rejected', {'to': maskAddress(to), 'idempotencyKey': key, 'correlationId': cid});
        return json({'error': 'recipient_rejected'}, 422);
      }
      final id = 'GW-${delivered.length + 1}';
      delivered[key] = {'id': id, 'to': maskAddress(to), 'subject': body['subject'], 'at': DateTime.now().toUtc().toIso8601String()};
      log('delivered', {'id': id, 'to': maskAddress(to), 'idempotencyKey': key, 'correlationId': cid});
      return json({'status': 'accepted', 'id': id}, 202);
    })
    ..post('/admin/fault', (Request req) async {
      final b = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      failNext = b['failNext'] ?? 0;
      failStatus = b['status'] ?? 503;
      delayMs = b['delayMs'] ?? 0;
      delayCount = b['delayMs'] == null ? 0 : (b['count'] ?? 1);
      log('fault_configured', {'failNext': failNext, 'status': failStatus, 'delayMs': delayMs, 'delayCount': delayCount});
      return json({'failNext': failNext, 'status': failStatus, 'delayMs': delayMs, 'delayCount': delayCount});
    })
    ..post('/admin/reset', (Request _) {
      failNext = 0;
      delayCount = 0;
      delivered.clear();
      return json({'status': 'reset'});
    })
    ..get('/admin/sent', (Request _) => json(delivered.values.toList()));

  final server = await io.serve(r.call, InternetAddress.loopbackIPv4, port);
  log('listening', {'url': 'http://127.0.0.1:${server.port}'});
}
