import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/ticket.dart';

/// Holds the signed-in user and the in-memory bearer token.
class Session extends ChangeNotifier {
  Session() {
    api = ApiClient(onUnauthenticated: () => _clear('Your session expired. Please sign in again.'));
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
