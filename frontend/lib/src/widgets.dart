import 'package:flutter/material.dart';

import 'api_client.dart';
import 'models.dart';

/// Loads data once and renders loading, error (with retry), empty and data states consistently.
class AsyncBody<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final bool Function(T data)? isEmpty;
  final String emptyMessage;
  final IconData emptyIcon;

  const AsyncBody({
    super.key,
    required this.load,
    required this.builder,
    this.isEmpty,
    this.emptyMessage = 'Nothing here yet.',
    this.emptyIcon = Icons.inbox_outlined,
  });

  @override
  State<AsyncBody<T>> createState() => _AsyncBodyState<T>();
}

class _AsyncBodyState<T> extends State<AsyncBody<T>> {
  T? _data;
  ApiFailure? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (mounted) setState(() => _data = d);
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator(semanticsLabel: 'Loading'));
    }
    if (_error != null) {
      return MessageView(
        icon: _error!.kind == FailureKind.network ? Icons.wifi_off : Icons.error_outline,
        message: _error!.userMessage,
        action: FilledButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Try again')),
      );
    }
    final data = _data as T;
    if (widget.isEmpty?.call(data) ?? false) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(children: [
          const SizedBox(height: 48),
          MessageView(icon: widget.emptyIcon, message: widget.emptyMessage),
        ]),
      );
    }
    return Stack(children: [
      RefreshIndicator(onRefresh: _reload, child: widget.builder(context, data, _reload)),
      if (_loading) const LinearProgressIndicator(),
    ]);
  }
}

class MessageView extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;
  const MessageView({super.key, required this.icon, required this.message, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      'needs_triage' || 'dead_letter' => (cs.errorContainer, cs.onErrorContainer),
      'assigned' || 'pending' || 'retrying' => (cs.secondaryContainer, cs.onSecondaryContainer),
      'in_progress' || 'sending' => (cs.primaryContainer, cs.onPrimaryContainer),
      'resolved' || 'sent' => (cs.tertiaryContainer, cs.onTertiaryContainer),
      _ => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return Semantics(
      label: 'Status ${label(status)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(label(status), style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// SLA state comes from server alerts (authoritative), not from the browser clock.
class SlaBadge extends StatelessWidget {
  final Ticket ticket;
  const SlaBadge(this.ticket, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!ticket.isOpen) return const SizedBox.shrink();
    final (text, color, icon) = ticket.alerts.contains('breach')
        ? ('SLA breached', cs.error, Icons.warning_amber)
        : ticket.alerts.contains('warning')
            ? ('SLA at risk', Colors.orange.shade800, Icons.schedule)
            : ('On track', cs.primary, Icons.check_circle_outline);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}

String fmtTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
}
