import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../session.dart';
import '../widgets.dart';

class TicketDetailScreen extends StatefulWidget {
  final String ticketId;
  const TicketDetailScreen({super.key, required this.ticketId});

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  int _version = 0;
  bool _busy = false;

  Future<void> _act(Future<dynamic> Function() call, String success) async {
    setState(() => _busy = true);
    try {
      await call();
      if (!mounted) return;
      showSnack(context, success);
      setState(() => _version++);
    } on ApiFailure catch (e) {
      if (!mounted) return;
      final fields = e.fieldErrors.values.join(' ');
      showSnack(context, fields.isEmpty ? e.userMessage : fields, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final api = session.api;
    return Scaffold(
      appBar: AppBar(title: Text(widget.ticketId)),
      body: AsyncBody<Ticket>(
        key: ValueKey(_version),
        load: () async => Ticket.fromJson(await api.get('/api/v1/tickets/${widget.ticketId}')),
        builder: (context, t, _) {
          final wide = MediaQuery.sizeOf(context).width >= 900;
          final main = [
            _InfoCard(ticket: t),
            const SizedBox(height: 12),
            _ActionsCard(ticket: t, user: session.user!, busy: _busy, act: _act),
            const SizedBox(height: 12),
            _ConversationCard(ticket: t),
          ];
          final side = [_HistoryCard(ticket: t)];
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: main)),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: side)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...main, const SizedBox(height: 12), ...side]),
          );
        },
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Ticket ticket;
  const _InfoCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    Widget field(String name, String value) => SizedBox(
          width: 220,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: Theme.of(context).textTheme.labelSmall),
            Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ]),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            StatusChip(t.status),
            SlaBadge(t),
            if (t.escalated) const Chip(label: Text('Escalated'), visualDensity: VisualDensity.compact),
          ]),
          const SizedBox(height: 8),
          SelectableText(t.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SelectableText(t.description),
          const Divider(height: 24),
          Wrap(spacing: 16, runSpacing: 12, children: [
            field('Category', label(t.category)),
            field('Priority', label(t.priority)),
            field('Team', t.team ?? '—'),
            field('Assignee', t.assigneeName ?? 'Unassigned'),
            field('Requester', t.requesterName ?? t.requesterId),
            field('SLA due', fmtTime(t.slaDueAt)),
            field('Routing', t.routingReason.isEmpty ? '—' : t.routingReason),
          ]),
        ]),
      ),
    );
  }
}

typedef _Act = Future<void> Function(Future<dynamic> Function() call, String success);

class _ActionsCard extends StatelessWidget {
  final Ticket ticket;
  final UserInfo user;
  final bool busy;
  final _Act act;
  const _ActionsCard({required this.ticket, required this.user, required this.busy, required this.act});

  @override
  Widget build(BuildContext context) {
    final api = SessionScope.of(context).api;
    final t = ticket;
    final path = '/api/v1/tickets/${t.id}';
    final isAssignee = t.assigneeId == user.id;
    final staff = isAssignee || user.isSupervisor;
    final buttons = <Widget>[];

    if (staff && t.isOpen && t.status != 'needs_triage') {
      buttons.add(OutlinedButton.icon(
        icon: const Icon(Icons.reply),
        label: const Text('Respond'),
        onPressed: busy
            ? null
            : () async {
                final msg = await _askText(context, 'Respond to requester', 'Message', min: 2);
                if (msg != null) await act(() => api.post('$path/responses', {'message': msg}), 'Response sent.');
              },
      ));
      buttons.add(FilledButton.icon(
        icon: const Icon(Icons.task_alt),
        label: const Text('Resolve'),
        onPressed: busy
            ? null
            : () async {
                final note = await _askText(context, 'Resolve ticket', 'Resolution summary', min: 5);
                if (note != null) await act(() => api.post('$path/resolve', {'resolution': note}), 'Ticket resolved.');
              },
      ));
    }
    if (user.isRequester && (t.isOpen || t.status == 'resolved')) {
      buttons.add(OutlinedButton.icon(
        icon: const Icon(Icons.comment_outlined),
        label: const Text('Add comment'),
        onPressed: busy
            ? null
            : () async {
                final msg = await _askText(context, 'Add a comment', 'Comment', min: 2);
                if (msg != null) await act(() => api.post('$path/responses', {'message': msg}), 'Comment added.');
              },
      ));
    }
    if (user.isRequester && t.status == 'resolved') {
      buttons.add(FilledButton.icon(
        icon: const Icon(Icons.check),
        label: const Text('Confirm fixed'),
        onPressed: busy ? null : () => act(() => api.post('$path/confirm'), 'Thanks! Ticket closed.'),
      ));
      buttons.add(OutlinedButton.icon(
        icon: const Icon(Icons.undo),
        label: const Text('Not fixed — reopen'),
        onPressed: busy
            ? null
            : () async {
                final reason = await _askText(context, 'Reopen ticket', 'What is still wrong?', min: 5);
                if (reason != null) await act(() => api.post('$path/reopen', {'reason': reason}), 'Ticket reopened.');
              },
      ));
    }
    if (user.isSupervisor && t.status == 'needs_triage') {
      buttons.add(FilledButton.icon(
        icon: const Icon(Icons.alt_route),
        label: const Text('Triage'),
        onPressed: busy
            ? null
            : () async {
                final r = await showDialog<(String, String)>(context: context, builder: (_) => const _TriageDialog());
                if (r != null) {
                  await act(() => api.post('$path/triage', {'category': r.$1, 'priority': r.$2}), 'Ticket triaged and assigned.');
                }
              },
      ));
    }
    if (user.isSupervisor && t.isOpen) {
      buttons.add(OutlinedButton.icon(
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Reassign'),
        onPressed: busy
            ? null
            : () async {
                final agents = [for (final a in await api.get('/api/v1/agents') as List) UserInfo.fromJson(a)];
                if (!context.mounted) return;
                final r = await showDialog<(String, String)>(
                    context: context, builder: (_) => _ReassignDialog(agents: agents, currentId: t.assigneeId));
                if (r != null) {
                  await act(() => api.post('$path/reassign', {'agentId': r.$1, 'reason': r.$2}), 'Ticket reassigned.');
                }
              },
      ));
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Actions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (buttons.isEmpty)
            Text(t.status == 'closed' ? 'This ticket is closed.' : 'No actions available for your role.',
                style: Theme.of(context).textTheme.bodySmall)
          else
            Wrap(spacing: 8, runSpacing: 8, children: buttons),
        ]),
      ),
    );
  }
}

Future<String?> _askText(BuildContext context, String title, String fieldLabel, {required int min}) {
  final controller = TextEditingController();
  final key = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: Form(
          key: key,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(labelText: fieldLabel, border: const OutlineInputBorder()),
            validator: (v) => (v?.trim().length ?? 0) < min ? 'Enter at least $min characters.' : null,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (key.currentState!.validate()) Navigator.pop(ctx, controller.text.trim());
          },
          child: const Text('Submit'),
        ),
      ],
    ),
  );
}

class _TriageDialog extends StatefulWidget {
  const _TriageDialog();
  @override
  State<_TriageDialog> createState() => _TriageDialogState();
}

class _TriageDialogState extends State<_TriageDialog> {
  String _category = 'software';
  String _priority = 'medium';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Triage ticket'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final c in categories.where((c) => c != 'auto' && c != 'other')) DropdownMenuItem(value: c, child: Text(label(c)))],
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Priority'),
            items: [for (final p in priorities) DropdownMenuItem(value: p, child: Text(label(p)))],
            onChanged: (v) => setState(() => _priority = v!),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, (_category, _priority)), child: const Text('Route')),
        ],
      );
}

class _ReassignDialog extends StatefulWidget {
  final List<UserInfo> agents;
  final String? currentId;
  const _ReassignDialog({required this.agents, required this.currentId});
  @override
  State<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<_ReassignDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  String? _agent;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Reassign ticket'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: _agent,
                decoration: const InputDecoration(labelText: 'Agent'),
                items: [
                  for (final a in widget.agents.where((a) => a.id != widget.currentId))
                    DropdownMenuItem(
                      value: a.id,
                      enabled: a.available,
                      child: Text('${a.displayName} · ${a.team} · ${a.openTickets ?? 0} open${a.available ? '' : ' (unavailable)'}'),
                    ),
                ],
                onChanged: (v) => setState(() => _agent = v),
                validator: (v) => v == null ? 'Choose an agent.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                decoration: const InputDecoration(labelText: 'Reason'),
                validator: (v) => (v?.trim().length ?? 0) < 5 ? 'Enter at least 5 characters.' : null,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) Navigator.pop(context, (_agent!, _reason.text.trim()));
            },
            child: const Text('Reassign'),
          ),
        ],
      );
}

class _ConversationCard extends StatelessWidget {
  final Ticket ticket;
  const _ConversationCard({required this.ticket});

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Conversation', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (ticket.responses.isEmpty) Text('No messages yet.', style: Theme.of(context).textTheme.bodySmall),
            for (final r in ticket.responses)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(r.authorId == ticket.requesterId ? Icons.person_outline : Icons.headset_mic_outlined),
                title: Text(r.message),
                subtitle: Text('${r.authorId} · ${fmtTime(r.at)}'),
              ),
          ]),
        ),
      );
}

const _actionLabels = {
  'sla_warning': 'SLA warning',
  'sla_breached': 'SLA breached',
  'requester_comment': 'Requester comment',
};

class _HistoryCard extends StatelessWidget {
  final Ticket ticket;
  const _HistoryCard({required this.ticket});

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Audit trail', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final h in ticket.history.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(h.actor.startsWith('system:') ? Icons.smart_toy_outlined : Icons.person_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (h.action == 'status_changed')
                        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(label(h.from ?? ''), style: const TextStyle(fontWeight: FontWeight.w600)),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.arrow_forward, size: 14)),
                          Text(label(h.to ?? ''), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ])
                      else
                        Text(_actionLabels[h.action] ?? label(h.action), style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (h.note != null && h.note!.isNotEmpty) Text(h.note!, style: Theme.of(context).textTheme.bodySmall),
                      Text('${h.actor} · ${fmtTime(h.at)}', style: Theme.of(context).textTheme.labelSmall),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      );
}
