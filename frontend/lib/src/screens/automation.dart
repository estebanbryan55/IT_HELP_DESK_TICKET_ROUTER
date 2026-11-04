import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../session.dart';
import '../widgets.dart';

/// Supervisor view of the automation: manual-review queue, notification outbox, job runs, agent availability.
class AutomationScreen extends StatelessWidget {
  const AutomationScreen({super.key});

  @override
  Widget build(BuildContext context) => const DefaultTabController(
        length: 4,
        child: Column(children: [
          TabBar(isScrollable: true, tabs: [
            Tab(icon: Icon(Icons.report_outlined), text: 'Manual review'),
            Tab(icon: Icon(Icons.outbox_outlined), text: 'Notifications'),
            Tab(icon: Icon(Icons.schedule), text: 'Job runs'),
            Tab(icon: Icon(Icons.groups_outlined), text: 'Agents'),
          ]),
          Expanded(child: TabBarView(children: [_ManualReview(), _Notifications(), _JobRuns(), _Agents()])),
        ]),
      );
}

String _attemptText(Map<String, dynamic> a) =>
    '${label(a['outcome'] as String)}${a['httpStatus'] == null ? '' : ' (${a['httpStatus']})'}'
    '${a['errorCode'] == null ? '' : ' · ${a['errorCode']}'} · ${a['durationMs']} ms';

class _ManualReview extends StatefulWidget {
  const _ManualReview();
  @override
  State<_ManualReview> createState() => _ManualReviewState();
}

class _ManualReviewState extends State<_ManualReview> {
  int _v = 0;

  Future<void> _run(Future<dynamic> Function() call, String ok) async {
    try {
      await call();
      if (!mounted) return;
      showSnack(context, ok);
      setState(() => _v++);
    } on ApiFailure catch (e) {
      if (mounted) showSnack(context, e.fieldErrors.values.join(' ').isNotEmpty ? e.fieldErrors.values.join(' ') : e.userMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = SessionScope.of(context).api;
    return AsyncBody<List<OutboxItem>>(
      key: ValueKey(_v),
      load: () async => [for (final m in await api.get('/api/v1/automation/notifications?status=dead_letter') as List) OutboxItem.fromJson(m)],
      isEmpty: (l) => l.isEmpty,
      emptyIcon: Icons.verified_outlined,
      emptyMessage: 'No failed notifications need attention.',
      builder: (context, items, _) => ListView(padding: const EdgeInsets.all(12), children: [
        for (final m in items)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(m.id, style: Theme.of(context).textTheme.labelLarge),
                  StatusChip(m.status),
                  Text(m.deadLetterReason == 'permanent_rejection' ? 'Rejected by gateway' : 'Retries exhausted'),
                ]),
                const SizedBox(height: 6),
                Text('${m.event} to ${m.recipientId} (${m.recipientAddress}) · ticket ${m.ticketId ?? '—'}'),
                for (final a in m.attemptLog) Text('• ${_attemptText(a)}', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.replay),
                    label: const Text('Retry now'),
                    onPressed: () => _run(() => api.post('/api/v1/automation/notifications/${m.id}/retry'), '${m.id} queued for retry.'),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.done_all),
                    label: const Text('Resolve manually'),
                    onPressed: () async {
                      final note = await _askNote(context);
                      if (note != null) {
                        await _run(() => api.post('/api/v1/automation/notifications/${m.id}/dismiss', {'note': note}), '${m.id} closed.');
                      }
                    },
                  ),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }

  Future<String?> _askNote(BuildContext context) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How was this handled?'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Resolution note (min 5 characters)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }
}

class _Notifications extends StatefulWidget {
  const _Notifications();
  @override
  State<_Notifications> createState() => _NotificationsState();
}

class _NotificationsState extends State<_Notifications> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    final api = SessionScope.of(context).api;
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          for (final s in [null, 'pending', 'retrying', 'sent', 'dead_letter', 'dismissed'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(label: Text(s == null ? 'All' : label(s)), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
            ),
        ]),
      ),
      Expanded(
        child: AsyncBody<List<OutboxItem>>(
          key: ValueKey(_status),
          load: () async => [
            for (final m in await api.get('/api/v1/automation/notifications${_status == null ? '' : '?status=$_status'}') as List)
              OutboxItem.fromJson(m),
          ],
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No notifications.',
          builder: (context, items, _) => ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final m = items[i];
              return ExpansionTile(
                leading: StatusChip(m.status),
                title: Text('${m.id} · ${m.event}'),
                subtitle: Text('${m.recipientId} · ticket ${m.ticketId ?? '—'} · ${m.attempts} attempt(s)'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Created ${fmtTime(m.createdAt)}${m.status == 'retrying' ? ' · next attempt ${fmtTime(m.nextAttemptAt)}' : ''}'),
                  for (final a in m.attemptLog) Text('• ${_attemptText(a)}'),
                  if (m.resolutionNote != null) Text('Note: ${m.resolutionNote}'),
                ],
              );
            },
          ),
        ),
      ),
    ]);
  }
}

class _JobRuns extends StatefulWidget {
  const _JobRuns();
  @override
  State<_JobRuns> createState() => _JobRunsState();
}

class _JobRunsState extends State<_JobRuns> {
  int _v = 0;
  bool _running = false;

  Future<void> _runJob(String job) async {
    setState(() => _running = true);
    try {
      final r = JobRunItem.fromJson(await SessionScope.of(context).api.post('/api/v1/automation/jobs/$job/run'));
      if (mounted) showSnack(context, '$job finished: ${r.stats}');
    } on ApiFailure catch (e) {
      if (mounted) showSnack(context, e.userMessage, error: true);
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _v++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = SessionScope.of(context).api;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final j in ['aging-scan', 'outbox-dispatch', 'daily-summary'])
            OutlinedButton.icon(onPressed: _running ? null : () => _runJob(j), icon: const Icon(Icons.play_arrow), label: Text('Run $j')),
        ]),
      ),
      Expanded(
        child: AsyncBody<List<JobRunItem>>(
          key: ValueKey(_v),
          load: () async => [for (final r in await api.get('/api/v1/automation/runs') as List) JobRunItem.fromJson(r)],
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No job runs recorded yet.',
          builder: (context, runs, _) => ListView.builder(
            itemCount: runs.length,
            itemBuilder: (context, i) {
              final r = runs[i];
              return ListTile(
                dense: true,
                leading: Icon(r.status == 'ok' ? Icons.check_circle_outline : Icons.error_outline,
                    color: r.status == 'ok' ? null : Theme.of(context).colorScheme.error),
                title: Text('${r.job} · ${r.trigger} · ${r.durationMs ?? '-'} ms'),
                subtitle: Text('${fmtTime(r.startedAt)} · ${r.stats.entries.map((e) => '${e.key}: ${e.value}').join(', ')}'),
              );
            },
          ),
        ),
      ),
    ]);
  }
}

class _Agents extends StatefulWidget {
  const _Agents();
  @override
  State<_Agents> createState() => _AgentsState();
}

class _AgentsState extends State<_Agents> {
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    final api = SessionScope.of(context).api;
    return AsyncBody<List<UserInfo>>(
      key: ValueKey(_v),
      load: () async => [for (final a in await api.get('/api/v1/agents') as List) UserInfo.fromJson(a)],
      builder: (context, agents, _) => ListView(padding: const EdgeInsets.all(12), children: [
        Text('Tickets of an unavailable agent are moved to a teammate on the next aging scan.', style: Theme.of(context).textTheme.bodySmall),
        for (final a in agents)
          SwitchListTile(
            title: Text(a.displayName),
            subtitle: Text('${a.team} team · ${a.openTickets ?? 0} open'),
            value: a.available,
            onChanged: (v) async {
              try {
                await api.patch('/api/v1/agents/${a.id}/availability', {'available': v});
                setState(() => _v++);
              } on ApiFailure catch (e) {
                if (context.mounted) showSnack(context, e.userMessage, error: true);
              }
            },
          ),
      ]),
    );
  }
}
