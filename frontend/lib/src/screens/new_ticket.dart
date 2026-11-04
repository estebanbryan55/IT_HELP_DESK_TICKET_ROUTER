import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../session.dart';
import '../widgets.dart';

/// Client-side checks mirror the server rules for fast feedback; the server stays authoritative.
String? validateTitle(String? v) {
  final t = v?.trim() ?? '';
  if (t.isEmpty) return 'Title is required.';
  if (t.length < 5 || t.length > 120) return 'Title must be 5-120 characters.';
  return null;
}

String? validateDescription(String? v) {
  final t = v?.trim() ?? '';
  if (t.isEmpty) return 'Description is required.';
  if (t.length < 10 || t.length > 2000) return 'Description must be 10-2000 characters.';
  return null;
}

class NewTicketScreen extends StatefulWidget {
  final VoidCallback onCreated;
  const NewTicketScreen({super.key, required this.onCreated});

  @override
  State<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<NewTicketScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _category = 'auto';
  String? _priority;
  bool _submitting = false;
  bool _triedSubmit = false; // after the first attempt, errors update as the user types
  Map<String, String> _serverErrors = {};
  String _idempotencyKey = newIdempotencyKey();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _serverErrors = {};
      _triedSubmit = true;
    });
    if (!_form.currentState!.validate()) return;
    setState(() => _submitting = true);
    final api = SessionScope.of(context).api;
    try {
      final json = await api.post(
        '/api/v1/tickets',
        {'title': _title.text.trim(), 'description': _description.text.trim(), 'category': _category, 'priority': _priority},
        {'Idempotency-Key': _idempotencyKey},
      );
      final t = Ticket.fromJson(json);
      if (!mounted) return;
      showSnack(
        context,
        t.status == 'needs_triage'
            ? '${t.id} submitted. A supervisor will route it shortly.'
            : '${t.id} submitted and assigned to ${t.assigneeName}.',
      );
      _triedSubmit = false;
      _form.currentState!.reset();
      _title.clear();
      _description.clear();
      _idempotencyKey = newIdempotencyKey();
      widget.onCreated();
    } on ApiFailure catch (e) {
      if (!mounted) return;
      if (e.kind == FailureKind.validation) {
        setState(() => _serverErrors = e.fieldErrors);
        _form.currentState!.validate();
      }
      showSnack(context, e.userMessage, error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _form,
            autovalidateMode: _triedSubmit ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Describe the problem. Tickets are routed to a support team automatically.',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('title'),
                controller: _title,
                maxLength: 120,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Title *', hintText: 'e.g. Wifi keeps dropping in Room 204', border: OutlineInputBorder()),
                validator: (v) => validateTitle(v) ?? _serverErrors['title'],
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('description'),
                controller: _description,
                minLines: 4,
                maxLines: 8,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  hintText: 'What happened, where, and since when? Do not include passwords.',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (v) => validateDescription(v) ?? _serverErrors['description'],
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    key: const Key('category'),
                    isExpanded: true,
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                    items: [
                      for (final c in categories)
                        DropdownMenuItem(
                          value: c,
                          child: Text(c == 'auto' ? 'Not sure (auto-detect)' : label(c), overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _category = v!),
                    validator: (_) => _serverErrors['category'],
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    key: const Key('priority'),
                    isExpanded: true,
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Priority *', border: OutlineInputBorder()),
                    items: [for (final p in priorities) DropdownMenuItem(value: p, child: Text(label(p)))],
                    onChanged: (v) => setState(() => _priority = v),
                    validator: (v) => v == null ? 'Choose a priority.' : _serverErrors['priority'],
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('submit'),
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: Text(_submitting ? 'Submitting…' : 'Submit ticket'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
