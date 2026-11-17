import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpdesk_web/api/api_client.dart';
import 'package:helpdesk_web/main.dart';
import 'package:helpdesk_web/state/session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('login form validates before calling the API', (tester) async {
    await tester.pumpWidget(HelpDeskApp(session: Session()));

    await tester.tap(find.text('Sign in').last);
    await tester.pump();
    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
    await tester.tap(find.text('Sign in').last);
    await tester.pump();
    expect(find.text('Enter a valid email'), findsOneWidget);
  });

  group('ApiClient error mapping', () {
    ApiClient clientReturning(int status, Map<String, dynamic> body, {void Function()? onUnauth}) {
      final api = ApiClient(
        client: MockClient((_) async => http.Response(jsonEncode(body), status,
            headers: {'content-type': 'application/json', 'x-correlation-id': '1234abcd-0000-0000-0000-000000000000'})),
        onUnauthenticated: onUnauth,
      );
      api.token = 'hdr_test';
      return api;
    }

    test('422 exposes field errors', () async {
      final api = clientReturning(422, {
        'message': 'Invalid',
        'errors': {'subject': ['Too short']},
      });
      final e = await api.post('/tickets').then<ApiException?>((_) => null, onError: (e) => e as ApiException);
      expect(e!.kind, ApiErrorKind.validation);
      expect(e.fieldError('subject'), 'Too short');
    });

    test('401 with a token ends the session', () async {
      var expired = false;
      final api = clientReturning(401, {'message': 'Unauthenticated.'}, onUnauth: () => expired = true);
      await expectLater(api.get('/tickets'), throwsA(isA<ApiException>()));
      expect(expired, isTrue);
    });

    test('500 hides server detail and shows a reference', () async {
      final api = clientReturning(500, {'message': 'SQLSTATE[HY000] secret detail'});
      final e = await api.get('/tickets').then<ApiException?>((_) => null, onError: (e) => e as ApiException);
      expect(e!.kind, ApiErrorKind.server);
      expect(e.message, isNot(contains('SQLSTATE')));
      expect(e.message, contains('1234abcd'));
    });

    test('authorization header is sent only when signed in', () async {
      late http.BaseRequest seen;
      final api = ApiClient(client: MockClient((r) async {
        seen = r;
        return http.Response('{}', 200);
      }));
      await api.get('/tickets');
      expect(seen.headers.containsKey('Authorization'), isFalse);
      api.token = 'hdr_x';
      await api.get('/tickets');
      expect(seen.headers['Authorization'], 'Bearer hdr_x');
    });
  });
}
