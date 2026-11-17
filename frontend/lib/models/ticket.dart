class UserInfo {
  UserInfo({required this.id, required this.name, required this.role});

  factory UserInfo.fromJson(Map<String, dynamic> j) =>
      UserInfo(id: j['id'] as int, name: j['name'] as String, role: j['role'] as String);

  final int id;
  final String name;
  final String role;

  bool get isRequester => role == 'requester';
  bool get isAgent => role == 'agent';
  bool get isSupervisor => role == 'supervisor';
}

class TicketEvent {
  TicketEvent({required this.action, this.fromStatus, this.toStatus, this.note, this.createdAt});

  factory TicketEvent.fromJson(Map<String, dynamic> j) => TicketEvent(
        action: j['action'] as String,
        fromStatus: j['from_status'] as String?,
        toStatus: j['to_status'] as String?,
        note: j['note'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal(),
      );

  final String action;
  final String? fromStatus;
  final String? toStatus;
  final String? note;
  final DateTime? createdAt;
}

class Ticket {
  Ticket({
    required this.id,
    required this.reference,
    required this.category,
    required this.priority,
    required this.status,
    required this.subject,
    required this.isOverdue,
    this.description,
    this.assetTag,
    this.contactNumber,
    this.accessNote,
    this.resolutionNote,
    this.requesterName,
    this.agentId,
    this.agentName,
    this.slaDueAt,
    this.createdAt,
    this.events = const [],
  });

  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
        id: j['id'] as int,
        reference: j['reference'] as String,
        category: j['category'] as String,
        priority: j['priority'] as String,
        status: j['status'] as String,
        subject: j['subject'] as String,
        isOverdue: j['is_overdue'] as bool? ?? false,
        description: j['description'] as String?,
        assetTag: j['asset_tag'] as String?,
        contactNumber: j['contact_number'] as String?,
        accessNote: j['access_note'] as String?,
        resolutionNote: j['resolution_note'] as String?,
        requesterName: (j['requester'] as Map<String, dynamic>?)?['name'] as String?,
        agentId: (j['agent'] as Map<String, dynamic>?)?['id'] as int?,
        agentName: (j['agent'] as Map<String, dynamic>?)?['name'] as String?,
        slaDueAt: DateTime.tryParse(j['sla_due_at'] as String? ?? '')?.toLocal(),
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal(),
        events: ((j['events'] as List?) ?? [])
            .map((e) => TicketEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final int id;
  final String reference;
  final String category;
  final String priority;
  final String status;
  final String subject;
  final bool isOverdue;
  final String? description;
  final String? assetTag;
  final String? contactNumber;
  final String? accessNote;
  final String? resolutionNote;
  final String? requesterName;
  final int? agentId;
  final String? agentName;
  final DateTime? slaDueAt;
  final DateTime? createdAt;
  final List<TicketEvent> events;
}

const ticketCategories = ['hardware', 'software', 'network', 'account', 'other'];
const ticketPriorities = ['low', 'normal', 'high', 'urgent'];

String labelOf(String value) =>
    value.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
