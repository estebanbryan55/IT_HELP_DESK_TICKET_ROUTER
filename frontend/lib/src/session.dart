import 'package:flutter/widgets.dart';

import 'api_client.dart';
import 'models.dart';

class Session extends ChangeNotifier {
  final ApiClient api;
  UserInfo? user;

  Session(this.api);

  /// Week 13 demo sign-in: the server confirms the identity and returns the role.
  Future<void> signInAs(String userId) async {
    api.userId = userId;
    try {
      user = UserInfo.fromJson(await api.get('/api/v1/me'));
    } catch (_) {
      api.userId = null;
      rethrow;
    }
    notifyListeners();
  }

  void signOut() {
    api.userId = null;
    user = null;
    notifyListeners();
  }
}

class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({super.key, required Session session, required super.child}) : super(notifier: session);

  static Session of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}
