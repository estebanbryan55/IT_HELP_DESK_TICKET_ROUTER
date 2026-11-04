import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../session.dart';
import '../widgets.dart';

class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = SessionScope.of(context).api;
    return AsyncBody<Map<String, dynamic>?>(
      load: () async {
        try {
          return await api.get('/api/v1/summaries/latest') as Map<String, dynamic>;
        } on ApiFailure catch (e) {
          if (e.kind == FailureKind.notFound) return null; // no summary yet is an empty state, not an error
          rethrow;
        }
      },
      isEmpty: (s) => s == null,
      emptyIcon: Icons.insights_outlined,
      emptyMessage: 'No summary yet. It is generated daily at the configured hour, or a supervisor can run it from Automation.',
      builder: (context, s, _) {
        final data = s!['data'] as Map<String, dynamic>;
        final totals = data['totals'] as Map<String, dynamic>;
        final notes = data['notifications'] as Map<String, dynamic>;
        Widget tile(String name, Object? value, {bool alert = false}) => SizedBox(
              width: 170,
              child: Card(
                color: alert && (value is int && value > 0) ? Theme.of(context).colorScheme.errorContainer : null,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${value ?? '—'}', style: Theme.of(context).textTheme.headlineMedium),
                    Text(name, style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ),
            );
        Widget breakdown(String title, Map<String, dynamic> m, {bool rawKeys = false}) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  if (m.isEmpty) const Text('—'),
                  for (final e in m.entries) Text('${rawKeys ? e.key : label(e.key)}: ${e.value}'),
                ]),
              ),
            );
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Summary for ${s['date']} · generated ${fmtTime(DateTime.parse(s['generatedAt']).toLocal())} (${s['trigger']})',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            tile('Open tickets', totals['open']),
            tile('Submitted today', totals['submittedToday']),
            tile('Closed today', totals['closedToday']),
            tile('Breached SLA (open)', totals['breachedOpen'], alert: true),
            tile('Awaiting triage', totals['awaitingTriage'], alert: true),
            tile('Avg resolution (min)', data['avgResolutionMinutes']),
            tile('Notifications sent', notes['sent']),
            tile('Sent after retry', notes['sentAfterRetry']),
            tile('Failed (manual review)', notes['deadLetter'], alert: true),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(width: 260, child: breakdown('By status', Map<String, dynamic>.from(data['byStatus']))),
            SizedBox(width: 260, child: breakdown('Open by category', Map<String, dynamic>.from(data['openByCategory']))),
            SizedBox(width: 260, child: breakdown('Open by agent', Map<String, dynamic>.from(data['openByAgent']), rawKeys: true)),
          ]),
        ]);
      },
    );
  }
}
