import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// API base URL is a build-time setting, never a secret:
///   flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8080
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://127.0.0.1:8080');

enum FailureKind { network, unauthenticated, forbidden, notFound, validation, conflict, badRequest, server }

class ApiFailure implements Exception {
  final FailureKind kind;
  final int? status;
  final String message;
  final Map<String, String> fieldErrors;
  final String? correlationId;

  ApiFailure(this.kind, this.message, {this.status, this.fieldErrors = const {}, this.correlationId});

  /// Text shown to users. Server detail is not exposed; the correlation id lets support find the log entry.
  String get userMessage {
    final ref = correlationId == null ? '' : ' (ref ${correlationId!.substring(0, min(8, correlationId!.length))})';
    return switch (kind) {
      FailureKind.network => 'Cannot reach the help desk service. Check your connection and try again.',
      FailureKind.unauthenticated => 'Your session is not valid. Please sign in again.',
      FailureKind.forbidden => 'You do not have permission for this action.',
      FailureKind.notFound => 'That item was not found or is not available to you.',
      FailureKind.server => 'The service had a problem. Please try again later.$ref',
      _ => message,
    };
  }

  @override
  String toString() => 'ApiFailure($kind, $status, $message)';
}

class ApiClient {
  final Uri baseUrl;
  final http.Client _http;
  final Duration timeout;

  /// Week 13 demo identity (see backend README). Replaced by a token in Week 14.
  String? userId;

  ApiClient({String? baseUrl, http.Client? client, this.timeout = const Duration(seconds: 10)})
      : baseUrl = Uri.parse(baseUrl ?? apiBaseUrl),
        _http = client ?? http.Client();

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Object? body, Map<String, String> headers = const {}]) =>
      _send('POST', path, body: body, headers: headers);
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String> headers = const {}}) async {
    final req = http.Request(method, baseUrl.resolve(path))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'X-Demo-User': ?userId,
        ...headers,
      });
    if (body != null) req.body = jsonEncode(body);

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on TimeoutException {
      throw ApiFailure(FailureKind.network, 'Request timed out.');
    } catch (_) {
      throw ApiFailure(FailureKind.network, 'Network error.');
    }

    final decoded = res.body.isEmpty ? null : _tryDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

    final err = decoded is Map ? decoded['error'] as Map? : null;
    final message = err?['message'] as String? ?? 'Request failed (${res.statusCode}).';
    final details = <String, String>{
      for (final e in ((err?['details'] as Map?) ?? const {}).entries) e.key.toString(): e.value.toString(),
    };
    final kind = switch (res.statusCode) {
      400 || 413 => FailureKind.badRequest,
      401 => FailureKind.unauthenticated,
      403 => FailureKind.forbidden,
      404 => FailureKind.notFound,
      409 => FailureKind.conflict,
      422 => FailureKind.validation,
      _ => FailureKind.server,
    };
    throw ApiFailure(kind, message,
        status: res.statusCode, fieldErrors: details, correlationId: err?['correlationId'] as String? ?? res.headers['x-correlation-id']);
  }

  static Object? _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}

/// One key per form instance, so a double click or a retry after a lost response does not create two tickets.
String newIdempotencyKey() {
  final r = Random.secure();
  return 'web-${List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join()}';
}
