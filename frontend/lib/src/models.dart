DateTime? _dt(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

class UserInfo {
  final String id, displayName, role;
  final String? team;
  final bool available;
  final int? openTickets;

  UserInfo({required this.id, required this.displayName, required this.role, this.team, this.available = true, this.openTickets});

  factory UserInfo.fromJson(Map<String, dynamic> j) => UserInfo(
        id: j['id'],
        displayName: j['displayName'],
        role: j['role'],
        team: j['team'],
        available: j['available'] ?? true,
        openTickets: j['openTickets'],
      );

  bool get isRequester => role == 'requester';
  bool get isAgent => role == 'agent';
  bool get isSupervisor => role == 'supervisor';
}

class HistoryEntry {
  final DateTime at;
  final String actor, action;
  final String? from, to, note;

  HistoryEntry(this.at, this.actor, this.action, this.from, this.to, this.note);

  factory HistoryEntry.fromJson(Map<String, dynamic> j) =>
      HistoryEntry(_dt(j['at'])!, j['actor'], j['action'], j['from'], j['to'], j['note']);
}

class ResponseEntry {
  final DateTime at;
  final String authorId, message;
  ResponseEntry(this.at, this.authorId, this.message);
  factory ResponseEntry.fromJson(Map<String, dynamic> j) => ResponseEntry(_dt(j['at'])!, j['authorId'], j['message']);
}

class Ticket {
  final String id, title, description, category, priority, status, requesterId, routingReason;
  final String? assigneeId, assigneeName, requesterName, team;
  final DateTime createdAt, updatedAt, slaDueAt;
  final bool escalated;
  final List<String> alerts;
  final List<HistoryEntry> history;
  final List<ResponseEntry> responses;

  Ticket.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        title = j['title'],
        description = j['description'],
        category = j['category'],
        priority = j['priority'],
        status = j['status'],
        requesterId = j['requesterId'],
        requesterName = j['requesterName'],
        routingReason = j['routingReason'] ?? '',
        assigneeId = j['assigneeId'],
        assigneeName = j['assigneeName'],
        team = j['team'],
        createdAt = _dt(j['createdAt'])!,
        updatedAt = _dt(j['updatedAt'])!,
        slaDueAt = _dt(j['slaDueAt'])!,
        escalated = j['escalated'] ?? false,
        alerts = List<String>.from(j['alerts'] ?? const []),
        history = [for (final h in j['history'] as List? ?? const []) HistoryEntry.fromJson(h)],
        responses = [for (final r in j['responses'] as List? ?? const []) ResponseEntry.fromJson(r)];

  bool get isOpen => const {'submitted', 'needs_triage', 'assigned', 'in_progress'}.contains(status);
}

class OutboxItem {
  final String id, event, recipientId, recipientAddress, status;
  final String? ticketId, lastErrorCode, deadLetterReason, resolutionNote;
  final int attempts;
  final DateTime createdAt, nextAttemptAt;
  final List<Map<String, dynamic>> attemptLog;

  OutboxItem.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        event = j['event'],
        recipientId = j['recipientId'],
        recipientAddress = j['recipientAddress'],
        status = j['status'],
        ticketId = j['ticketId'],
        lastErrorCode = j['lastErrorCode'],
        deadLetterReason = j['deadLetterReason'],
        resolutionNote = j['resolutionNote'],
        attempts = j['attempts'],
        createdAt = _dt(j['createdAt'])!,
        nextAttemptAt = _dt(j['nextAttemptAt'])!,
        attemptLog = List<Map<String, dynamic>>.from(j['attemptLog'] ?? const []);
}

class JobRunItem {
  final String id, job, trigger, status;
  final DateTime startedAt;
  final int? durationMs;
  final Map<String, dynamic> stats;

  JobRunItem.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        job = j['job'],
        trigger = j['trigger'],
        status = j['status'],
        startedAt = _dt(j['startedAt'])!,
        durationMs = j['durationMs'],
        stats = Map<String, dynamic>.from(j['stats'] ?? const {});
}

const categories = ['auto', 'network', 'account', 'hardware', 'software', 'other'];
const priorities = ['low', 'medium', 'high', 'critical'];
const statuses = ['submitted', 'needs_triage', 'assigned', 'in_progress', 'resolved', 'closed'];

String label(String code) => code.isEmpty ? code : (code[0].toUpperCase() + code.substring(1)).replaceAll('_', ' ');
