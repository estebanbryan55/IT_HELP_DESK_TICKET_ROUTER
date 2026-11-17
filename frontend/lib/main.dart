import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/ticket_list_screen.dart';
import 'state/session.dart';

void main() => runApp(HelpDeskApp(session: Session()));

class HelpDeskApp extends StatelessWidget {
  const HelpDeskApp({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IT Help Desk Ticket Router',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1B5E9A), useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF1B5E9A), brightness: Brightness.dark, useMaterial3: true),
      home: ListenableBuilder(
        listenable: session,
        // Signing in/out (or a 401 expiring the session) swaps the whole
        // navigator subtree, so no protected screen stays on the stack.
        builder: (context, _) => session.isSignedIn
            ? Navigator(
                key: ValueKey(session.user!.id),
                onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => TicketListScreen(session: session)),
              )
            : LoginScreen(session: session),
      ),
    );
  }
}
