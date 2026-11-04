import 'dart:convert';

import 'package:helpdesk_backend/helpdesk_backend.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Handler handler;
  setUp(() => handler = buildHandler(makeApp().ctx));

  Future<(int, dynamic, Map<String, String>)> call(String method, String path,
      {String? user, Object? body, Map<String, String> headers = const {}}) async {
    final res = await handler(Request(method, Uri.parse('http://localhost$path'),
        headers: {'x-demo-user': ?user, 'content-type': 'application/json', ...headers},
        body: body == null ? null : jsonEncode(body)));
    final text = await res.readAsString();
    return (res.statusCode, text.isEmpty ? null : jsonDecode(text), res.headers);
  }

  test('requests without identity get 401 with a safe error body', () async {
    final (status, body, headers) = await call('GET', '/api/v1/tickets');
    expect(status, 401);
    expect(body['error']['code'], 'unauthenticated');
    expect(body['error']['correlationId'], headers['x-correlation-id']);
  });

  test('correlation id from the client is echoed when well-formed', () async {
    final (_, _, headers) = await call('GET', '/api/v1/me', user: 'req-ana', headers: {'x-correlation-id': 'demo-12345678'});
    expect(headers['x-correlation-id'], 'demo-12345678');
  });

  test('create returns 201; validation returns 422 with field details', () async {
    final (ok, ticket, _) = await call('POST', '/api/v1/tickets', user: 'req-ana', body: ticketBody());
    expect(ok, 201);
    expect(ticket['status'], 'assigned');
    expect(ticket.containsKey('email'), isFalse);

    final (bad, err, _) = await call('POST', '/api/v1/tickets', user: 'req-ana', body: {'title': 'x'});
    expect(bad, 422);
    expect(err['error']['details'], contains('title'));
  });

  test('malformed JSON is a 400, not a 500', () async {
    final res = await handler(Request('POST', Uri.parse('http://localhost/api/v1/tickets'),
        headers: {'x-demo-user': 'req-ana'}, body: '{not json'));
    expect(res.statusCode, 400);
  });

  test('automation endpoints are supervisor-only', () async {
    expect((await call('GET', '/api/v1/automation/notifications', user: 'agent-carla')).$1, 403);
    expect((await call('GET', '/api/v1/automation/notifications', user: 'sup-mara')).$1, 200);
  });

  test('notification list masks recipient addresses', () async {
    await call('POST', '/api/v1/tickets', user: 'req-ana', body: ticketBody());
    final (_, list, _) = await call('GET', '/api/v1/automation/notifications', user: 'sup-mara');
    expect(list, isNotEmpty);
    for (final m in list) {
      expect(m['recipientAddress'], contains('***'));
      expect(m.containsKey('body'), isFalse);
    }
  });

  test('CORS preflight allows the local Flutter dev origin only', () async {
    final ok = await handler(Request('OPTIONS', Uri.parse('http://localhost/api/v1/tickets'),
        headers: {'origin': 'http://localhost:5173'}));
    expect(ok.statusCode, 204);
    expect(ok.headers['access-control-allow-origin'], 'http://localhost:5173');

    final denied = await handler(Request('OPTIONS', Uri.parse('http://localhost/api/v1/tickets'),
        headers: {'origin': 'https://evil.example'}));
    expect(denied.statusCode, 403);
  });

  test('unknown route is a JSON 404', () async {
    final (status, body, _) = await call('GET', '/api/v1/nope', user: 'req-ana');
    expect(status, 404);
    expect(body['error']['code'], 'not_found');
  });
}
