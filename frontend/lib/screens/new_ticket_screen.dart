import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/ticket.dart';
import '../state/session.dart';
import '../widgets/common.dart';

/// Collects only what routing and resolution need. Rules mirror the Laravel
/// StoreTicketRequest; the server remains authoritative and its field errors
/// are shown under the matching inputs.
class NewTicketScreen extends StatefulWidget {
  const NewTicketScreen({super.key, required this.session});

  final Session session;

  @override
  State<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<NewTicketScreen> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _description = TextEditingController();
  final _assetTag = TextEditingController();
  final _contact = TextEditingController();
  final _accessNote = TextEditingController();
  String? _category;
  String _priority = 'normal';
  bool _busy = false;
  Map<String, List<String>> _serverErrors = {};

  @override
  void dispose() {
    for (final c in [_subject, _description, _assetTag, _contact, _accessNote]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _server(String field) => _serverErrors[field]?.first;

  Future<void> _submit() async {
    setState(() => _serverErrors = {});
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final json = await widget.session.api.post('/tickets', {
        'category': _category,
        'priority': _priority,
        'subject': _subject.text.trim(),
        'description': _description.text.trim(),
        if (_assetTag.text.trim().isNotEmpty) 'asset_tag': _assetTag.text.trim().toUpperCase(),
        if (_contact.text.trim().isNotEmpty) 'contact_number': _contact.text.trim(),
        if (_accessNote.text.trim().isNotEmpty) 'access_note': _accessNote.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(Ticket.fromJson(json['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.kind == ApiErrorKind.validation) {
        setState(() => _serverErrors = e.fieldErrors);
        _form.currentState!.validate();
      }
      showResult(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New ticket')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                LayoutBuilder(builder: (context, c) {
                  final category = DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Category *'),
                    items: ticketCategories.map((v) => DropdownMenuItem(value: v, child: Text(labelOf(v)))).toList(),
                    onChanged: (v) => setState(() => _category = v),
                    validator: (v) => v == null ? 'Choose a category' : _server('category'),
                  );
                  final priority = DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: ticketPriorities.map((v) => DropdownMenuItem(value: v, child: Text(labelOf(v)))).toList(),
                    onChanged: (v) => setState(() => _priority = v ?? 'normal'),
                    validator: (_) => _server('priority'),
                  );
                  return c.maxWidth >= 520
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: category),
                          const SizedBox(width: 12),
                          Expanded(child: priority),
                        ])
                      : Column(children: [category, const SizedBox(height: 12), priority]);
                }),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _subject,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Subject *', hintText: 'Short summary of the problem'),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.length < 5) return 'Subject must be at least 5 characters';
                    return _server('subject');
                  },
                ),
                TextFormField(
                  controller: _description,
                  maxLength: 2000,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Description *',
                    hintText: 'What happened, where, and since when? Do not include passwords.',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.length < 10) return 'Description must be at least 10 characters';
                    return _server('description');
                  },
                ),
                TextFormField(
                  controller: _assetTag,
                  decoration: const InputDecoration(labelText: 'Asset tag (optional)', hintText: 'e.g. PRJ-305-01'),
                  validator: (v) {
                    final t = v?.trim().toUpperCase() ?? '';
                    if (t.isNotEmpty && !RegExp(r'^[A-Z0-9\-]{3,30}$').hasMatch(t)) {
                      return 'Use 3-30 letters, digits, or hyphens';
                    }
                    return _server('asset_tag');
                  },
                ),
                const SizedBox(height: 20),
                Text('Protected details', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                const Text(
                  'Stored encrypted and visible only to you, your assigned agent, and supervisors.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _contact,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Contact number (optional)', prefixIcon: Icon(Icons.phone)),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isNotEmpty && !RegExp(r'^\+?[0-9 \-]{7,20}$').hasMatch(t)) {
                      return 'Use 7-20 digits, spaces, or hyphens';
                    }
                    return _server('contact_number');
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _accessNote,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Room access note (optional)',
                    hintText: 'e.g. who holds the room key',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                  validator: (_) => _server('access_note'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: const Text('Submit ticket'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
