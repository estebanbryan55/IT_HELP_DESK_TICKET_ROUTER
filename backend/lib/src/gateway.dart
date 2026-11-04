import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'retry.dart';

class SendResult {
  final FailureKind failure;
  final int? httpStatus;
  final String? errorCode;
  final int durationMs;

  SendResult(this.failure, {this.httpStatus, this.errorCode, required this.durationMs});

  bool get ok => failure == FailureKind.none;
}

abstract interface class NotificationGateway {
  Future<SendResult> send(OutboxMessage message);
  Future<bool> ping();
}

/// Calls the external notification service over HTTP with a hard timeout.
class HttpNotificationGateway implements NotificationGateway {
  final Uri baseUrl;
  final String apiKey;
  final Duration timeout;
  final http.Client _client;

  HttpNotificationGateway({required this.baseUrl, required this.apiKey, required this.timeout, http.Client? client})
      : _client = client ?? http.Client();

  @override
  Future<SendResult> send(OutboxMessage m) async {
    final sw = Stopwatch()..start();
    try {
      final res = await _client
          .post(
            baseUrl.resolve('/send'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
              'Idempotency-Key': m.idempotencyKey,
              'X-Correlation-Id': m.correlationId,
            },
            body: jsonEncode({'to': m.recipientAddress, 'subject': m.subject, 'body': m.body}),
          )
          .timeout(timeout);
      final kind = classifyHttpStatus(res.statusCode);
      String? code;
      if (kind != FailureKind.none) {
        try {
          code = (jsonDecode(res.body) as Map)['error']?.toString();
        } catch (_) {
          code = 'http_${res.statusCode}';
        }
      }
      return SendResult(kind, httpStatus: res.statusCode, errorCode: code, durationMs: sw.elapsedMilliseconds);
    } on TimeoutException {
      return SendResult(FailureKind.transient, errorCode: 'timeout', durationMs: sw.elapsedMilliseconds);
    } on SocketException {
      return SendResult(FailureKind.transient, errorCode: 'connection_refused', durationMs: sw.elapsedMilliseconds);
    } on http.ClientException {
      return SendResult(FailureKind.transient, errorCode: 'connection_error', durationMs: sw.elapsedMilliseconds);
    }
  }

  @override
  Future<bool> ping() async {
    try {
      final res = await _client.get(baseUrl.resolve('/health')).timeout(const Duration(seconds: 1));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
