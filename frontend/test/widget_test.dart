import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpdesk_web/main.dart';
import 'package:helpdesk_web/src/api_client.dart';
import 'package:helpdesk_web/src/screens/new_ticket.dart';
import 'package:helpdesk_web/src/session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _ana = {'id': 'req-ana', 'displayName': 'Ana Reyes (Student)', 'role': 'requester', 'team': null, 'available': true};

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Future<Session> _signedIn(MockClient client) async {
  final s = Session(ApiClient(baseUrl: 'http://api.test', client: client));
  await s.signInAs('req-ana');
  return s;
}

Widget _form(Session s) => SessionScope(
      session: s,
      child: MaterialApp(home: Scaffold(body: NewTicketScreen(onCreated: () {}))),
    );

void main() {
  test('client validators mirror server rules', () {
    expect(validateTitle(''), isNotNull);
    expect(validateTitle('Hi'), isNotNull);
    expect(validateTitle('Wifi down'), isNull);
    expect(validateDescription('short'), isNotNull);
    expect(validateDescription('Long enough description'), isNull);
  });

  testWidgets('empty form shows validation messages and sends nothing', (tester) async {
    var posts = 0;
    final s = await _signedIn(MockClient((r) async {
      if (r.method == 'POST') posts++;
      return _json(_ana);
    }));
    await tester.pumpWidget(_form(s));
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();

    expect(find.text('Title is required.'), findsOneWidget);
    expect(find.text('Description is required.'), findsOneWidget);
    expect(find.text('Choose a priority.'), findsOneWidget);
    expect(posts, 0);
  });

  testWidgets('server validation errors are shown on the matching field', (tester) async {
    String? idemKey;
    final s = await _signedIn(MockClient((r) async {
      if (r.method == 'POST') {
        idemKey = r.headers['Idempotency-Key'];
        return _json({
          'error': {'code': 'validation_failed', 'message': 'One or more fields are invalid.', 'details': {'title': 'Title rejected by server.'}}
        }, 422);
      }
      return _json(_ana);
    }));
    await tester.pumpWidget(_form(s));
    await tester.enterText(find.byKey(const Key('title')), 'Printer jam');
    await tester.enterText(find.byKey(const Key('description')), 'The 2F printer is jammed again.');
    await tester.tap(find.byKey(const Key('priority')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Medium').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.text('Title rejected by server.'), findsOneWidget);
    expect(idemKey, startsWith('web-'), reason: 'each submission carries an idempotency key');
  });

  testWidgets('network failure shows an understandable message with retry', (tester) async {
    final app = HelpDeskApp(session: Session(ApiClient(baseUrl: 'http://api.test', client: MockClient((_) async => throw http.ClientException('offline')))));
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.textContaining('Cannot reach the help desk service'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('server error hides internals and shows a reference id', (tester) async {
    final app = HelpDeskApp(
      session: Session(ApiClient(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => _json({
              'error': {'code': 'internal_error', 'message': 'Unexpected server error.', 'correlationId': 'abcdef12-3456'}
            }, 500)),
      )),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.textContaining('The service had a problem'), findsOneWidget);
    expect(find.textContaining('ref abcdef12'), findsOneWidget);
  });
}
