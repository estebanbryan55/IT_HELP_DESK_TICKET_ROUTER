import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

enum ApiErrorKind {
  validation,
  unauthenticated,
  forbidden,
  notFound,
  conflict,
  rateLimited,
  unavailable,
  network,
  server,
}

class ApiException implements Exception {
  ApiException(this.kind, this.message, {this.fieldErrors = const {}, this.correlationId});

  final ApiErrorKind kind;
  final String message;
  final Map<String, List<String>> fieldErrors;
  final String? correlationId;

  String? fieldError(String field) => fieldErrors[field]?.first;

  /// Safe to retry the same request later (the server or network was the problem).
  bool get isTransient => kind == ApiErrorKind.network || kind == ApiErrorKind.unavailable;

  @override
  String toString() => message;
}

/// Thin HTTP wrapper. The bearer token lives only in memory (never in
/// localStorage), so a page reload signs the user out; this limits how long a
/// stolen token stays usable from the browser.
class ApiClient {
  ApiClient({http.Client? client, this.onUnauthenticated, Duration? timeout})
      : _http = client ?? http.Client(),
        _timeout = timeout ?? AppConfig.requestTimeout;

  final http.Client _http;
  final Duration _timeout;
  final void Function()? onUnauthenticated;
  String? token;

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body, Map<String, String> headers = const {}]) =>
      _send('POST', path, body, headers);

  Future<Map<String, dynamic>> _send(String method, String path,
      [Map<String, dynamic>? body, Map<String, String> extraHeaders = const {}]) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        ...extraHeaders,
      });
    if (body != null) request.body = jsonEncode(body);

    http.Response response;
    try {
      // The timeout covers the whole exchange (headers and body), not just the first byte.
      response = await _http.send(request).then(http.Response.fromStream).timeout(_timeout);
    } on TimeoutException {
      throw ApiException(ApiErrorKind.network, 'The server took too long to respond. Please try again.');
    } catch (_) {
      throw ApiException(ApiErrorKind.network, 'Cannot reach the help desk service. Check your connection.');
    }

    final correlationId = response.headers['x-correlation-id'];
    final ref = correlationId != null && correlationId.length >= 8 ? ' (ref ${correlationId.substring(0, 8)})' : '';
    Map<String, dynamic> json = {};
    if (response.body.isNotEmpty) {
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        // Non-JSON error page from a proxy; fall through to status handling.
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return json;

    final serverMessage = json['message'] as String?;
    switch (response.statusCode) {
      case 401:
        if (token != null) onUnauthenticated?.call();
        throw ApiException(ApiErrorKind.unauthenticated,
            serverMessage ?? 'Your session has ended. Please sign in again.',
            correlationId: correlationId);
      case 403:
        throw ApiException(ApiErrorKind.forbidden,
            serverMessage ?? 'You are not permitted to do this.', correlationId: correlationId);
      case 404:
        // The API answers 404 both for missing tickets and for tickets the user may not see.
        throw ApiException(ApiErrorKind.notFound, 'That ticket was not found or is not available to you.',
            correlationId: correlationId);
      case 409:
        throw ApiException(ApiErrorKind.conflict,
            serverMessage ?? 'The ticket changed. Refresh and try again.', correlationId: correlationId);
      case 422:
        final errors = (json['errors'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as List).map((e) => e.toString()).toList()),
        );
        throw ApiException(ApiErrorKind.validation, serverMessage ?? 'Please correct the highlighted fields.',
            fieldErrors: errors, correlationId: correlationId);
      case 429:
        throw ApiException(ApiErrorKind.rateLimited, 'Too many attempts. Please wait a minute and try again.',
            correlationId: correlationId);
      case 502:
      case 503:
      case 504:
        throw ApiException(ApiErrorKind.unavailable,
            'The help desk service is temporarily unavailable. Please try again shortly$ref.',
            correlationId: correlationId);
      default:
        // Never show raw server output; give the reference so support can find the log entry.
        throw ApiException(ApiErrorKind.server, 'Something went wrong on the server$ref.',
            correlationId: correlationId);
    }
  }
}
