import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/ticket.dart';
import '../state/session.dart';
import '../widgets/common.dart';

class TicketDetailScreen extends StatefulWidget {
  const TicketDetailScreen({super.key, required this.session, required this.ticketId});

  final Session session;
  final int ticketId;

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  late Future<Ticket> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Ticket> _load() async {
    final json = await widget.session.api.get('/tickets/${widget.ticketId}');
    return Ticket.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<void> _act(String path, Map<String, dynamic> body, String done) async {
    setState(() => _busy = true);
    try {
      final json = await widget.session.api.post('/tickets/${widget.ticketId}/$path', body);
      if (!mounted) return;
      setState(() => _future = Future.value(Ticket.fromJson(json['data'] as Map<String, dynamic>)));
      showResult(context, done);
    } on ApiException catch (e) {
      if (mounted) showResult(context, e.fieldErrors.values.firstOrNull?.first ?? e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askNote(String title, {required bool required}) {
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: form,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLength: 500,
            maxLines: 3,
            decoration: InputDecoration(labelText: required ? 'Note *' : 'Note (optional)'),
            validator: (v) => required && (v == null || v.trim().isEmpty) ? 'A note is required' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(ctx, controller.text.trim());
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _reassign() async {
    List<dynamic> agents;
    try {
      agents = (await widget.session.api.get('/agents'))['data'] as List;
    } on ApiException catch (e) {
      if (mounted) showResult(context, e.message, error: true);
      return;
    }
    if (!mounted) return;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Assign to agent'),
        children: agents
            .map((a) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, a['id'] as int),
                  child: Text('${a['name']} (${labelOf(a['specialization'] as String? ?? 'general')})'),
                ))
            .toList(),
      ),
    );
    if (picked != null) await _act('assign', {'agent_id': picked}, 'Ticket reassigned');
  }

  List<Widget> _actions(Ticket t) {
    final user = widget.session.user!;
    final canWork = user.isSupervisor || (user.isAgent && t.agentId == user.id);
    return [
      if (canWork && t.status == 'assigned')
        FilledButton.tonal(
          onPressed: () => _act('transition', {'status': 'in_progress'}, 'Marked in progress'),
          child: const Text('Start work'),
        ),
      if (canWork && (t.status == 'assigned' || t.status == 'in_progress'))
        FilledButton(
          onPressed: () async {
            final note = await _askNote('Resolution note', required: true);
            if (note != null) await _act('transition', {'status': 'resolved', 'note': note}, 'Ticket resolved');
          },
          child: const Text('Resolve'),
        ),
      if (user.isSupervisor && t.status != 'closed')
        OutlinedButton(onPressed: _reassign, child: const Text('Reassign')),
      if (user.isRequester && t.status == 'resolved') ...[
        FilledButton(
          onPressed: () => _act('confirm', {'accepted': true}, 'Thanks! Ticket closed'),
          child: const Text('Confirm fixed'),
        ),
        OutlinedButton(
          onPressed: () async {
            final note = await _askNote('What is still wrong?', required: true);
            if (note != null) await _act('confirm', {'accepted': false, 'note': note}, 'Ticket reopened');
          },
          child: const Text('Not fixed'),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ticket details')),
      body: FutureBuilder<Ticket>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView(label: 'Loading ticket');
          if (snap.hasError) {
            final e = snap.error;
            final forbidden = e is ApiException && e.kind == ApiErrorKind.forbidden;
            return MessageView(
              icon: forbidden ? Icons.block : Icons.error_outline,
              title: forbidden ? 'Access denied' : 'Could not load this ticket',
              detail: e.toString(),
              action: forbidden
                  ? null
                  : OutlinedButton(onPressed: () => setState(() => _future = _load()), child: const Text('Try again')),
            );
          }
          final t = snap.data!;
          final actions = _actions(t);
          return LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 900;
            final main = _MainPanel(ticket: t, actions: actions, busy: _busy);
            final history = _HistoryPanel(events: t.events);
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: wide
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(flex: 3, child: main),
                          const SizedBox(width: 16),
                          Expanded(flex: 2, child: history),
                        ])
                      : Column(children: [main, const SizedBox(height: 16), history]),
                ),
              ),
            );
          });
        },
      ),
    );
  }
}

class _MainPanel extends StatelessWidget {
  const _MainPanel({required this.ticket, required this.actions, required this.busy});

  final Ticket ticket;
  final List<Widget> actions;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(t.reference, style: text.labelLarge),
              StatusChip(t.status),
              if (t.isOverdue) Chip(label: const Text('SLA overdue'), visualDensity: VisualDensity.compact),
            ]),
            const SizedBox(height: 8),
            Text(t.subject, style: text.titleLarge),
            const SizedBox(height: 12),
            Text(t.description ?? ''),
            const Divider(height: 32),
            _Field('Category', labelOf(t.category)),
            _Field('Priority', labelOf(t.priority)),
            _Field('Requester', t.requesterName ?? '-'),
            _Field('Assigned agent', t.agentName ?? 'Unassigned'),
            if (t.slaDueAt != null) _Field('Due', _fmt(t.slaDueAt!)),
            if (t.assetTag != null) _Field('Asset tag', t.assetTag!),
            if (t.contactNumber != null) _Field('Contact number', t.contactNumber!, icon: Icons.lock_outline),
            if (t.accessNote != null) _Field('Access note', t.accessNote!, icon: Icons.lock_outline),
            if (t.resolutionNote != null) _Field('Resolution', t.resolutionNote!),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              busy ? const LinearProgressIndicator() : Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value, {this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (icon != null) ...[Icon(icon, size: 16, semanticLabel: 'protected'), const SizedBox(width: 4)],
          Expanded(child: SelectableText(value)),
        ]),
      );
}

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({required this.events});

  final List<TicketEvent> events;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('History', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final e in events)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history, size: 20),
                title: Text(e.toStatus != null ? '${labelOf(e.action)} → ${labelOf(e.toStatus!)}' : labelOf(e.action)),
                subtitle: Text([if (e.createdAt != null) _fmt(e.createdAt!), if (e.note != null) e.note!].join('\n')),
              ),
          ]),
        ),
      );
}

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
