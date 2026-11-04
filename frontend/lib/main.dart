import 'package:flutter/material.dart';

import 'src/api_client.dart';
import 'src/screens/shell.dart';
import 'src/screens/sign_in.dart';
import 'src/session.dart';

void main() => runApp(HelpDeskApp(session: Session(ApiClient())));

class HelpDeskApp extends StatelessWidget {
  final Session session;
  const HelpDeskApp({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: session,
      child: MaterialApp(
        title: 'IT Help Desk Ticket Router',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF1F5FAD), useMaterial3: true),
        home: ListenableBuilder(
          listenable: session,
          builder: (context, _) => session.user == null ? const SignInScreen() : const HomeShell(),
        ),
      ),
    );
  }
}
