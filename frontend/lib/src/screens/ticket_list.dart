import 'package:flutter/material.dart';

import '../models.dart';
import '../session.dart';
import '../widgets.dart';
import 'ticket_detail.dart';

class TicketListScreen extends StatefulWidget {
  const TicketListScreen({super.key});

  @override
  State<TicketListScreen> createState() => _TicketListScreenState();
}

class _TicketListScreenState extends State<TicketListScreen> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    final api = SessionScope.of(context).api;
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(children: [
          for (final s in [null, ...statuses])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(s == null ? 'All' : label(s)),
                selected: _status == s,
                onSelected: (_) => setState(() => _status = s),
              ),
            ),
        ]),
      ),
      Expanded(
        child: AsyncBody<List<Ticket>>(
          key: ValueKey(_status),
          load: () async => [
            for (final t in await api.get('/api/v1/tickets${_status == null ? '' : '?status=$_status'}') as List)
              Ticket.fromJson(t),
          ],
          isEmpty: (l) => l.isEmpty,
          emptyMessage: _status == null ? 'No tickets yet.' : 'No tickets with status "${label(_status!)}".',
          builder: (context, tickets, reload) => ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: tickets.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _TicketCard(
              ticket: tickets[i],
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TicketDetailScreen(ticketId: tickets[i].id)));
                reload();
              },
            ),
          ),
        ),
      ),
    ]);
  }
}

class _TicketCard extends StatelessWidget {
  final Ticket ticket;
  final VoidCallback onTap;
  const _TicketCard({required this.ticket, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final muted = Theme.of(context).textTheme.bodySmall;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(t.id, style: Theme.of(context).textTheme.labelLarge),
              StatusChip(t.status),
              Chip(
                label: Text(label(t.priority)),
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.flag_outlined, size: 16, color: t.priority == 'critical' || t.priority == 'high' ? Colors.red : null),
              ),
              SlaBadge(t),
            ]),
            const SizedBox(height: 6),
            Text(t.title, style: Theme.of(context).textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              '${label(t.category)} · ${t.assigneeName ?? 'Unassigned'} · created ${fmtTime(t.createdAt)}',
              style: muted,
            ),
          ]),
        ),
      ),
    );
  }
}
