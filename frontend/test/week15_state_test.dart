// Week 15 (IA6) Flutter Web state tests. The real screens run against a
// simulated API (MockClient), so each UI state can be produced on demand:
// loading, success, empty, validation, unauthenticated, not found, network
// failure, service unavailable, timeout + safe retry, and narrow layout.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpdesk_web/main.dart';
import 'package:helpdesk_web/state/session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _ref = '1234abcd-0000-0000-0000-000000000000';

http.Response _json(int status, Object body) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json', 'x-correlation-id': _ref});

Map<String, dynamic> _ticket({int id = 7, String subject = 'Wi-Fi drops in Lab 3', String status = 'assigned'}) => {
      'id': id,
      'reference': 'HD-2026-${id.toString().padLeft(6, '0')}',
      'category': 'network',
      'priority': 'high',
      'status': status,
      'subject': subject,
      'is_overdue': false,
      'agent': {'id': 4, 'name': 'Nico Network'},
      'requester': {'id': 1, 'name': 'Sam Student'},
      'events': [],
    };

final _login = {
  'token': 'hdr_test',
  'expires_at': '2026-11-17T08:00:00+00:00',
  'user': {'id': 1, 'name': 'Sam Student', 'role': 'requester'},
};

/// Routes "METHOD /path" to a handler; unknown routes fail the test loudly.
MockClient _api(Map<String, FutureOr<http.Response> Function(http.Request)> routes) => MockClient((req) async {
      final key = '${req.method} ${req.url.path.replaceFirst('/api/v1', '')}';
      final handler = routes[key];
      if (handler == null) throw StateError('Unexpected request: $key');
      return handler(req);
    });

Future<void> _signIn(WidgetTester tester, Session session) async {
  await tester.pumpWidget(HelpDeskApp(session: session));
  await tester.enterText(find.byType(TextFormField).at(0), 'student@example.test');
  await tester.enterText(find.byType(TextFormField).at(1), 'Demo-Pass-2026!');
  await tester.tap(find.text('Sign in').last);
  await tester.pump(); // request in flight
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('ST-01 sign in, loading indicator, then ticket list (success state)', (tester) async {
    final gate = Completer<http.Response>();
    final session = Session(client: _api({
      'POST /auth/login': (_) => _json(200, _login),
      'GET /tickets': (_) => gate.future,
    }));
    await _signIn(tester, session);

    expect(find.bySemanticsLabel('Loading tickets'), findsOneWidget);
    gate.complete(_json(200, {'data': [_ticket()]}));
    await tester.pumpAndSettle();

    expect(find.text('My tickets'), findsOneWidget);
    expect(find.text('Wi-Fi drops in Lab 3'), findsOneWidget);
    expect(find.text('New ticket'), findsOneWidget);
  });

  testWidgets('ST-02 empty state guides the requester', (tester) async {
    final session = Session(client: _api({
      'POST /auth/login': (_) => _json(200, _login),
      'GET /tickets': (_) => _json(200, {'data': []}),
    }));
    await _signIn(tester, session);
    await tester.pumpAndSettle();

    expect(find.text('No tickets here'), findsOneWidget);
    expect(find.text('Use "New ticket" to report a problem.'), findsOneWidget);
  });

  testWidgets('ST-03 network failure shows retry, and retry recovers', (tester) async {
    var calls = 0;
    final session = Session(client: _api({
      'POST /auth/login': (_) => _json(200, _login),
      'GET /tickets': (_) {
        if (++calls == 1) throw http.ClientException('XMLHttpRequest error.');
        return _json(200, {'data': [_ticket()]});
      },
    }));
    await _signIn(tester, session);
    await tester.pumpAndSettle();

    expect(find.text('Could not load tickets'), findsOneWidget);
    expect(find.textContaining('Cannot reach the help desk service'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi drops in Lab 3'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('ST-04 503 dependency outage shows a safe message with a reference', (tester) async {
    final session = Session(client: _api({
      'POST /auth/login': (_) => _json(200, _login),
      'GET /tickets': (_) => _json(503, {'message': 'SQLSTATE[HY000] should never be shown', 'correlation_id': _ref}),
    }));
    await _signIn(tester, session);
    await tester.pumpAndSettle();

    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(find.textContaining('ref 1234abcd'), findsOneWidget);
    expect(find.textContaining('SQLSTATE'), findsNothing);
  });

  testWidgets('ST-05 expired token (401) returns to sign-in with a notice', (tester) async {
    final session = Session(client: _api({
      'POST /auth/login': (_) => _json(200, _login),
      'GET /tickets': (_) => _json(401, {'message': 'Unauthenticated.'}),
    }));
    await _signIn(tester, session);
    await tester.pumpAndSettle();

    expect(session.isSignedIn, isFalse);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Your session expired. Please sign in again.'), findsOneWidget);
  });

  testWidgets('ST-06 ticket the user may not see shows "not found" without a retry loop', (tester) async {
    final session = Session(client: _api({
      'POST /auth/login': (_) => _json(200, _login),
      'GET /tickets': (_) => _json(200, {'data': [_ticket()]}),
      'GET /tickets/7': (_) => _json(404, {'message': 'Resource not found.'}),
    }));
    await _signIn(tester, session);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wi-Fi drops in Lab 3'));
    await tester.pumpAndSettle();

    expect(find.text('Ticket not found'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Back to list'), findsOneWidget);
  });

  testWidgets('ST-07 login rate limit (429) and outage (503) are explained, password cleared', (tester) async {
    var calls = 0;
    final session = Session(client: _api({
      'POST /auth/login': (_) => ++calls == 1
          ? _json(429, {'message': 'Too Many Attempts.'})
          : _json(503, {'message': 'x', 'correlation_id': _ref}),
    }));
    await _signIn(tester, session);
    await tester.pumpAndSettle();
    expect(find.textContaining('Too many attempts'), findsOneWidget);
    expect((tester.widget(find.byType(EditableText).at(1)) as EditableText).controller.text, isEmpty);

    await tester.enterText(find.byType(TextFormField).at(1), 'Demo-Pass-2026!');
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
  });

  group('New ticket form', () {
    Future<void> openForm(WidgetTester tester, Session session, {bool desktop = true}) async {
      if (desktop) {
        // Desktop browser window tall enough for the whole form (ListView builds lazily).
        tester.view.physicalSize = const Size(1280, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }
      await _signIn(tester, session);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New ticket'));
      await tester.pumpAndSettle();
    }

    Future<void> fillValid(WidgetTester tester) async {
      await tester.tap(find.text('Category *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Network').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Subject *'), 'Wi-Fi drops in Lab 3');
      await tester.enterText(find.widgetWithText(TextFormField, 'Description *'), 'Connection drops every five minutes.');
    }

    testWidgets('ST-08 server validation error appears under the matching field', (tester) async {
      final session = Session(client: _api({
        'POST /auth/login': (_) => _json(200, _login),
        'GET /tickets': (_) => _json(200, {'data': []}),
        'POST /tickets': (_) => _json(422, {
              'message': 'The given data was invalid.',
              'errors': {'subject': ['The subject contains a blocked word.']},
            }),
      }));
      await openForm(tester, session);
      await fillValid(tester);
      await tester.tap(find.text('Submit ticket'));
      await tester.pumpAndSettle();

      expect(find.text('The subject contains a blocked word.'), findsOneWidget);
    });

    testWidgets('ST-09 client validation blocks the request entirely', (tester) async {
      var posts = 0;
      final session = Session(client: _api({
        'POST /auth/login': (_) => _json(200, _login),
        'GET /tickets': (_) => _json(200, {'data': []}),
        'POST /tickets': (_) => _json(201, {'data': _ticket()}).also(() => posts++),
      }));
      await openForm(tester, session);
      await tester.enterText(find.widgetWithText(TextFormField, 'Subject *'), 'abc');
      await tester.tap(find.text('Submit ticket'));
      await tester.pumpAndSettle();

      expect(find.text('Choose a category'), findsOneWidget);
      expect(find.text('Subject must be at least 5 characters'), findsOneWidget);
      expect(find.text('Description must be at least 10 characters'), findsOneWidget);
      expect(posts, 0);
    });

    testWidgets('ST-10 timeout then retry reuses the same Idempotency-Key (no duplicate ticket)', (tester) async {
      final keys = <String?>[];
      final session = Session(
        timeout: const Duration(milliseconds: 100),
        client: _api({
          'POST /auth/login': (_) => _json(200, _login),
          'GET /tickets': (_) => _json(200, {'data': []}),
          'POST /tickets': (req) async {
            keys.add(req.headers['Idempotency-Key']);
            if (keys.length == 1) {
              // First attempt: the server is slow and the client gives up.
              await Future<void>.delayed(const Duration(seconds: 1));
            }
            return _json(keys.length == 1 ? 201 : 200, {'data': _ticket()});
          },
        }),
      );
      await openForm(tester, session);
      await fillValid(tester);

      await tester.tap(find.text('Submit ticket'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150)); // past the 100 ms timeout
      expect(find.textContaining('took too long'), findsOneWidget);
      expect(find.textContaining('press Submit again to retry safely'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1)); // let the slow response drain

      await tester.tap(find.text('Submit ticket'));
      await tester.pumpAndSettle();

      expect(keys, hasLength(2));
      expect(keys.first, matches(RegExp(r'^tk-[0-9a-f]{32}$')));
      expect(keys.last, keys.first);
      // The form closed with the (replayed) ticket and the list is shown again.
      expect(find.text('Submit ticket'), findsNothing);
      expect(find.text('My tickets'), findsOneWidget);
    });

    testWidgets('ST-11 double-click sends one request (button disabled while busy)', (tester) async {
      var posts = 0;
      final gate = Completer<http.Response>();
      final session = Session(client: _api({
        'POST /auth/login': (_) => _json(200, _login),
        'GET /tickets': (_) => _json(200, {'data': []}),
        'POST /tickets': (_) {
          posts++;
          return gate.future;
        },
      }));
      await openForm(tester, session);
      await fillValid(tester);

      await tester.tap(find.text('Submit ticket'));
      await tester.pump();
      await tester.tap(find.text('Submit ticket'), warnIfMissed: false);
      await tester.pump();
      expect(posts, 1);

      gate.complete(_json(201, {'data': _ticket()}));
      await tester.pumpAndSettle();
    });

    testWidgets('ST-12 narrow 375 px browser: fields stack vertically without overflow', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final session = Session(client: _api({
        'POST /auth/login': (_) => _json(200, _login),
        'GET /tickets': (_) => _json(200, {'data': [_ticket()]}),
      }));
      await openForm(tester, session, desktop: false);

      final category = tester.getTopLeft(find.text('Category *'));
      final priority = tester.getTopLeft(find.text('Priority'));
      expect(priority.dy, greaterThan(category.dy));
      expect(tester.takeException(), isNull);
    });
  });
}

extension _Also<T> on T {
  T also(void Function() fn) {
    fn();
    return this;
  }
}
