import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../session.dart';
import '../widgets.dart';

/// Demo sign-in for Week 13: pick a fictional seeded user. Real authentication arrives in Week 14.
class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(Icons.support_agent, size: 36, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text('IT Help Desk Ticket Router', style: Theme.of(context).textTheme.titleLarge)),
                  ]),
                  const SizedBox(height: 8),
                  Text('Demo environment — fictional users only. Choose who to sign in as.',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Flexible(
                    child: AsyncBody<List<UserInfo>>(
                      load: () async => [
                        for (final u in await session.api.get('/api/v1/demo/users') as List) UserInfo.fromJson(u),
                      ],
                      isEmpty: (l) => l.isEmpty,
                      builder: (context, users, _) => ListView(shrinkWrap: true, children: [
                        for (final u in users)
                          ListTile(
                            leading: Icon(switch (u.role) {
                              'supervisor' => Icons.admin_panel_settings_outlined,
                              'agent' => Icons.headset_mic_outlined,
                              _ => Icons.person_outline,
                            }),
                            title: Text(u.displayName),
                            subtitle: Text('${label(u.role)}${u.team == null ? '' : ' · ${u.team} team'}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              try {
                                await session.signInAs(u.id);
                              } on ApiFailure catch (e) {
                                if (context.mounted) showSnack(context, e.userMessage, error: true);
                              }
                            },
                          ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
