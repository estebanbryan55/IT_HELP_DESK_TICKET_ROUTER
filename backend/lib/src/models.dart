// Domain records for the help desk workflow. All persisted as JSON.

DateTime? _dt(Object? v) => v == null ? null : DateTime.parse(v as String);
String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

abstract final class Roles {
  static const requester = 'requester';
  static const agent = 'agent';
  static const supervisor = 'supervisor';
}

abstract final class TicketStatus {
  static const submitted = 'submitted';
  static const needsTriage = 'needs_triage';
  static const assigned = 'assigned';
  static const inProgress = 'in_progress';
  static const resolved = 'resolved';
  static const closed = 'closed';

  static const all = [submitted, needsTriage, assigned, inProgress, resolved, closed];

  /// Statuses whose SLA clock is running.
  static const open = {submitted, needsTriage, assigned, inProgress};
}

abstract final class Priorities {
  static const all = ['low', 'medium', 'high', 'critical'];
  static int rank(String p) => all.indexOf(p);
}

abstract final class Categories {
  static const all = ['network', 'account', 'hardware', 'software', 'other'];
}

class AppUser {
  final String id;
  final String displayName;
  final String role;
  final String email;
  final String? team;
  bool available;

  AppUser({
    required this.id,
    required this.displayName,
    required this.role,
    required this.email,
    this.team,
    this.available = true,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'],
        displayName: j['displayName'],
        role: j['role'],
        email: j['email'],
        team: j['team'],
        available: j['available'] ?? true,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'displayName': displayName, 'role': role, 'email': email, 'team': team, 'available': available};

  /// What clients may see: the email address stays on the server.
  Map<String, dynamic> toPublicJson() =>
      {'id': id, 'displayName': displayName, 'role': role, 'team': team, 'available': available};
}

class AuditEvent {
  final DateTime at;
  final String actor;
  final String action;
  final String? from;
  final String? to;
  final String? note;
  final String? correlationId;

  AuditEvent({required this.at, required this.actor, required this.action, this.from, this.to, this.note, this.correlationId});

  factory AuditEvent.fromJson(Map<String, dynamic> j) => AuditEvent(
        at: _dt(j['at'])!,
        actor: j['actor'],
        action: j['action'],
        from: j['from'],
        to: j['to'],
        note: j['note'],
        correlationId: j['correlationId'],
      );

  Map<String, dynamic> toJson() => {
        'at': _iso(at),
        'actor': actor,
        'action': action,
        'from': from,
        'to': to,
        'note': note,
        'correlationId': correlationId,
      };
}

class TicketResponse {
  final DateTime at;
  final String authorId;
  final String message;

  TicketResponse({required this.at, required this.authorId, required this.message});

  factory TicketResponse.fromJson(Map<String, dynamic> j) =>
      TicketResponse(at: _dt(j['at'])!, authorId: j['authorId'], message: j['message']);

  Map<String, dynamic> toJson() => {'at': _iso(at), 'authorId': authorId, 'message': message};
}

class Ticket {
  final String id;
  final String title;
  final String description;
  final String requestedCategory;
  final String requestedPriority;
  String category;
  String priority;
  String status;
  final String requesterId;
  String? assigneeId;
  String? team;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime slaDueAt;
  DateTime? resolvedAt;
  DateTime? closedAt;
  String routingReason;
  bool escalated;
  final List<String> alerts;
  final List<AuditEvent> history;
  final List<TicketResponse> responses;

  Ticket({
    required this.id,
    required this.title,
    required this.description,
    required this.requestedCategory,
    required this.requestedPriority,
    required this.category,
    required this.priority,
    required this.status,
    required this.requesterId,
    this.assigneeId,
    this.team,
    required this.createdAt,
    required this.updatedAt,
    required this.slaDueAt,
    this.resolvedAt,
    this.closedAt,
    this.routingReason = '',
    this.escalated = false,
    List<String>? alerts,
    List<AuditEvent>? history,
    List<TicketResponse>? responses,
  })  : alerts = alerts ?? [],
        history = history ?? [],
        responses = responses ?? [];

  bool get isOpen => TicketStatus.open.contains(status);

  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
        id: j['id'],
        title: j['title'],
        description: j['description'],
        requestedCategory: j['requestedCategory'],
        requestedPriority: j['requestedPriority'],
        category: j['category'],
        priority: j['priority'],
        status: j['status'],
        requesterId: j['requesterId'],
        assigneeId: j['assigneeId'],
        team: j['team'],
        createdAt: _dt(j['createdAt'])!,
        updatedAt: _dt(j['updatedAt'])!,
        slaDueAt: _dt(j['slaDueAt'])!,
        resolvedAt: _dt(j['resolvedAt']),
        closedAt: _dt(j['closedAt']),
        routingReason: j['routingReason'] ?? '',
        escalated: j['escalated'] ?? false,
        alerts: List<String>.from(j['alerts'] ?? const []),
        history: [for (final h in (j['history'] as List? ?? const [])) AuditEvent.fromJson(h)],
        responses: [for (final r in (j['responses'] as List? ?? const [])) TicketResponse.fromJson(r)],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'requestedCategory': requestedCategory,
        'requestedPriority': requestedPriority,
        'category': category,
        'priority': priority,
        'status': status,
        'requesterId': requesterId,
        'assigneeId': assigneeId,
        'team': team,
        'createdAt': _iso(createdAt),
        'updatedAt': _iso(updatedAt),
        'slaDueAt': _iso(slaDueAt),
        'resolvedAt': _iso(resolvedAt),
        'closedAt': _iso(closedAt),
        'routingReason': routingReason,
        'escalated': escalated,
        'alerts': alerts,
        'history': [for (final h in history) h.toJson()],
        'responses': [for (final r in responses) r.toJson()],
      };
}

abstract final class OutboxStatus {
  static const pending = 'pending';
  static const sending = 'sending';
  static const retrying = 'retrying';
  static const sent = 'sent';
  static const deadLetter = 'dead_letter';
  static const dismissed = 'dismissed';

  static const due = {pending, retrying};
}

class DeliveryAttempt {
  final DateTime at;
  final String outcome; // sent | transient_failure | permanent_failure
  final int? httpStatus;
  final String? errorCode;
  final int durationMs;

  DeliveryAttempt({required this.at, required this.outcome, this.httpStatus, this.errorCode, required this.durationMs});

  factory DeliveryAttempt.fromJson(Map<String, dynamic> j) => DeliveryAttempt(
        at: _dt(j['at'])!,
        outcome: j['outcome'],
        httpStatus: j['httpStatus'],
        errorCode: j['errorCode'],
        durationMs: j['durationMs'],
      );

  Map<String, dynamic> toJson() =>
      {'at': _iso(at), 'outcome': outcome, 'httpStatus': httpStatus, 'errorCode': errorCode, 'durationMs': durationMs};
}

/// A notification waiting in the transactional outbox.
class OutboxMessage {
  final String id;
  final String idempotencyKey;
  final String? ticketId;
  final String event;
  final String recipientId;
  final String recipientAddress;
  final String subject;
  final String body;
  final String correlationId;
  final DateTime createdAt;
  String status;
  int attempts;
  DateTime nextAttemptAt;
  DateTime? sentAt;
  String? lastErrorCode;
  String? deadLetterReason;
  String? resolutionNote;
  final List<DeliveryAttempt> attemptLog;

  OutboxMessage({
    required this.id,
    required this.idempotencyKey,
    required this.ticketId,
    required this.event,
    required this.recipientId,
    required this.recipientAddress,
    required this.subject,
    required this.body,
    required this.correlationId,
    required this.createdAt,
    required this.status,
    required this.attempts,
    required this.nextAttemptAt,
    this.sentAt,
    this.lastErrorCode,
    this.deadLetterReason,
    this.resolutionNote,
    List<DeliveryAttempt>? attemptLog,
  }) : attemptLog = attemptLog ?? [];

  factory OutboxMessage.fromJson(Map<String, dynamic> j) => OutboxMessage(
        id: j['id'],
        idempotencyKey: j['idempotencyKey'],
        ticketId: j['ticketId'],
        event: j['event'],
        recipientId: j['recipientId'],
        recipientAddress: j['recipientAddress'],
        subject: j['subject'],
        body: j['body'],
        correlationId: j['correlationId'],
        createdAt: _dt(j['createdAt'])!,
        status: j['status'],
        attempts: j['attempts'],
        nextAttemptAt: _dt(j['nextAttemptAt'])!,
        sentAt: _dt(j['sentAt']),
        lastErrorCode: j['lastErrorCode'],
        deadLetterReason: j['deadLetterReason'],
        resolutionNote: j['resolutionNote'],
        attemptLog: [for (final a in (j['attemptLog'] as List? ?? const [])) DeliveryAttempt.fromJson(a)],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'idempotencyKey': idempotencyKey,
        'ticketId': ticketId,
        'event': event,
        'recipientId': recipientId,
        'recipientAddress': recipientAddress,
        'subject': subject,
        'body': body,
        'correlationId': correlationId,
        'createdAt': _iso(createdAt),
        'status': status,
        'attempts': attempts,
        'nextAttemptAt': _iso(nextAttemptAt),
        'sentAt': _iso(sentAt),
        'lastErrorCode': lastErrorCode,
        'deadLetterReason': deadLetterReason,
        'resolutionNote': resolutionNote,
        'attemptLog': [for (final a in attemptLog) a.toJson()],
      };

  /// Client view: the recipient address is masked.
  Map<String, dynamic> toPublicJson() {
    final j = toJson();
    j['recipientAddress'] = maskAddress(recipientAddress);
    j.remove('body');
    return j;
  }
}

String maskAddress(String a) {
  final at = a.indexOf('@');
  if (at <= 1) return '***';
  return '${a[0]}***${a.substring(at)}';
}

class JobRun {
  final String id;
  final String job;
  final String trigger;
  final DateTime startedAt;
  DateTime? finishedAt;
  String status; // running | ok | failed | skipped
  Map<String, Object?> stats;
  final String correlationId;

  JobRun({
    required this.id,
    required this.job,
    required this.trigger,
    required this.startedAt,
    required this.status,
    required this.correlationId,
    this.finishedAt,
    Map<String, Object?>? stats,
  }) : stats = stats ?? {};

  int? get durationMs => finishedAt?.difference(startedAt).inMilliseconds;

  factory JobRun.fromJson(Map<String, dynamic> j) => JobRun(
        id: j['id'],
        job: j['job'],
        trigger: j['trigger'],
        startedAt: _dt(j['startedAt'])!,
        finishedAt: _dt(j['finishedAt']),
        status: j['status'],
        correlationId: j['correlationId'],
        stats: Map<String, Object?>.from(j['stats'] ?? const {}),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'job': job,
        'trigger': trigger,
        'startedAt': _iso(startedAt),
        'finishedAt': _iso(finishedAt),
        'durationMs': durationMs,
        'status': status,
        'stats': stats,
        'correlationId': correlationId,
      };
}

class SupportSummary {
  final String id;
  final String date; // local date yyyy-MM-dd
  final DateTime generatedAt;
  final String trigger;
  final Map<String, Object?> data;

  SupportSummary({required this.id, required this.date, required this.generatedAt, required this.trigger, required this.data});

  factory SupportSummary.fromJson(Map<String, dynamic> j) => SupportSummary(
        id: j['id'],
        date: j['date'],
        generatedAt: _dt(j['generatedAt'])!,
        trigger: j['trigger'],
        data: Map<String, Object?>.from(j['data']),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'date': date, 'generatedAt': _iso(generatedAt), 'trigger': trigger, 'data': data};
}
