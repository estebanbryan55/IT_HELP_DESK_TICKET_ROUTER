import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/ticket.dart';
import '../state/session.dart';
import '../widgets/common.dart';
import 'new_ticket_screen.dart';
import 'ticket_detail_screen.dart';

class TicketListScreen extends StatefulWidget {
  const TicketListScreen({super.key, required this.session});

  final Session session;

  @override
  State<TicketListScreen> createState() => _TicketListScreenState();
}

class _TicketListScreenState extends State<TicketListScreen> {
  late Future<List<Ticket>> _future;
  String? _status;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Ticket>> _load() async {
    final query = _status == null ? '' : '?status=$_status';
    final json = await widget.session.api.get('/tickets$query');
    return (json['data'] as List).map((e) => Ticket.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Week 15 DEF-10: an arrow body here returned the Future from setState, which
  // throws in debug builds, so "Try again" and "Refresh" did nothing.
  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _open(Ticket t) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TicketDetailScreen(session: widget.session, ticketId: t.id),
    ));
    if (mounted) _refresh();
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Ticket>(MaterialPageRoute(
      builder: (_) => NewTicketScreen(session: widget.session),
    ));
    if (created != null && mounted) {
      showResult(context, 'Ticket ${created.reference} submitted');
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user!;
    final title = switch (user.role) {
      'agent' => 'My assigned tickets',
      'supervisor' => 'All tickets',
      _ => 'My tickets',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _refresh),
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle),
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text('${user.name} (${labelOf(user.role)})')),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
            onSelected: (_) => widget.session.signOut(),
          ),
        ],
      ),
      floatingActionButton: user.isRequester
          ? FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New ticket'))
          : null,
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [null, 'open', 'assigned', 'in_progress', 'resolved', 'closed']
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(s == null ? 'All' : labelOf(s)),
                          selected: _status == s,
                          onSelected: (_) {
                            _status = s;
                            _refresh();
                          },
                        ),
                      ))
                  .toList(),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Ticket>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const LoadingView(label: 'Loading tickets');
                if (snap.hasError) {
                  final e = snap.error;
                  return MessageView(
                    icon: e is ApiException && e.isTransient ? Icons.cloud_off : Icons.error_outline,
                    title: 'Could not load tickets',
                    detail: e.toString(),
                    action: OutlinedButton(onPressed: _refresh, child: const Text('Try again')),
                  );
                }
                final tickets = snap.data!;
                if (tickets.isEmpty) {
                  return MessageView(
                    icon: Icons.inbox_outlined,
                    title: 'No tickets here',
                    detail: user.isRequester ? 'Use "New ticket" to report a problem.' : 'Nothing matches this filter.',
                  );
                }
                return LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 720;
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: tickets.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _TicketTile(ticket: tickets[i], wide: wide, onTap: () => _open(tickets[i])),
                  );
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.ticket, required this.wide, required this.onTap});

  final Ticket ticket;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = '${ticket.reference} · ${labelOf(ticket.category)} · ${labelOf(ticket.priority)}'
        '${ticket.agentName != null ? ' · ${ticket.agentName}' : ''}';
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Text(ticket.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(meta, maxLines: wide ? 1 : 2, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusChip(ticket.status),
            if (ticket.isOverdue)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Overdue', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}
