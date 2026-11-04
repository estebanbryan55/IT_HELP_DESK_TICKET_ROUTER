import 'package:flutter/material.dart';

import '../session.dart';
import 'automation.dart';
import 'new_ticket.dart';
import 'summary.dart';
import 'ticket_list.dart';

class _Dest {
  final String label;
  final IconData icon;
  final Widget Function() build;
  const _Dest(this.label, this.icon, this.build);
}

/// Role-based navigation: a rail on wide screens, a bottom bar on narrow screens.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _listVersion = 0; // bumps to refresh the list after a new ticket is created

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final user = session.user!;

    final dests = <_Dest>[
      _Dest(user.isRequester ? 'My tickets' : (user.isAgent ? 'My queue' : 'All tickets'), Icons.confirmation_number_outlined,
          () => TicketListScreen(key: ValueKey(_listVersion))),
      if (user.isRequester)
        _Dest('New ticket', Icons.add_circle_outline, () => NewTicketScreen(onCreated: () => setState(() {
              _listVersion++;
              _index = 0;
            }))),
      if (user.isSupervisor) _Dest('Automation', Icons.settings_suggest_outlined, () => const AutomationScreen()),
      if (!user.isRequester) _Dest('Summary', Icons.insights_outlined, () => const SummaryScreen()),
    ];
    final index = _index.clamp(0, dests.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= 800;

    return Scaffold(
      appBar: AppBar(
        title: Text(dests[index].label),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(user.displayName, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
            ),
          ),
          IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: session.signOut),
        ],
      ),
      body: Row(children: [
        if (wide)
          NavigationRail(
            selectedIndex: index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [for (final d in dests) NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label))],
          ),
        if (wide) const VerticalDivider(width: 1),
        Expanded(child: dests[index].build()),
      ]),
      bottomNavigationBar: wide || dests.length < 2
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [for (final d in dests) NavigationDestination(icon: Icon(d.icon), label: d.label)],
            ),
    );
  }
}
