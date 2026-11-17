import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../models/ticket.dart';

/// Holds the signed-in user and the in-memory bearer token.
class Session extends ChangeNotifier {
  /// [client] and [timeout] are injectable so state tests can simulate the API.
  Session({http.Client? client, Duration? timeout}) {
    api = ApiClient(
      client: client,
      timeout: timeout,
      onUnauthenticated: () => _clear('Your session expired. Please sign in again.'),
    );
  }

  late final ApiClient api;
  UserInfo? user;
  DateTime? expiresAt;
  String? notice;

  bool get isSignedIn => user != null;

  Future<void> signIn(String email, String password) async {
    final json = await api.post('/auth/login', {'email': email.trim(), 'password': password});
    api.token = json['token'] as String;
    expiresAt = DateTime.tryParse(json['expires_at'] as String? ?? '');
    user = UserInfo.fromJson(json['user'] as Map<String, dynamic>);
    notice = null;
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await api.post('/auth/logout');
    } catch (_) {
      // Token is dropped locally even if the server cannot be reached.
    }
    _clear(null);
  }

  void _clear(String? message) {
    api.token = null;
    user = null;
    expiresAt = null;
    notice = message;
    notifyListeners();
  }
}
