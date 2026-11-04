import 'config.dart';
import 'errors.dart';
import 'logger.dart';
import 'models.dart';
import 'outbox.dart';
import 'rules.dart';
import 'store.dart';

class TicketService {
  final JsonStore store;
  final RoutingRules rules;
  final Outbox outbox;
  final AppConfig config;
  final Clock clock;
  final Log log;

  TicketService({
    required this.store,
    required this.rules,
    required this.outbox,
    required this.config,
    required this.clock,
    required this.log,
  });

  // ---------------------------------------------------------------- queries

  List<Ticket> listFor(AppUser user, {String? status}) => store.read((s) {
        final list = s.tickets.values.where((t) => canView(user, t)).where((t) => status == null || t.status == status).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  Ticket getFor(AppUser user, String id) => store.read((s) {
        final t = s.tickets[id];
        // Same 404 for "missing" and "not yours" so ticket numbers cannot be probed.
        if (t == null || !canView(user, t)) throw ApiException.notFound('Ticket');
        return t;
      });

  bool canView(AppUser u, Ticket t) => switch (u.role) {
        Roles.supervisor => true,
        Roles.agent => t.assigneeId == u.id || (t.team != null && t.team == u.team),
        _ => t.requesterId == u.id,
      };

  // ---------------------------------------------------------------- commands

  Future<Ticket> create(AppUser actor, Map<String, dynamic> body, {String? idempotencyKey, required String cid}) {
    _requireRole(actor, {Roles.requester});
    final input = validateCreate(body);

    return store.transaction((s) {
      final idemKey = idempotencyKey == null ? null : '${actor.id}:$idempotencyKey';
      if (idemKey != null && s.idempotency.containsKey(idemKey)) {
        log.info('ticket.create_replayed', {'ticketId': s.idempotency[idemKey], 'correlationId': cid});
        return s.tickets[s.idempotency[idemKey]]!;
      }

      final now = clock.now();
      final t = Ticket(
        id: 'TKT-${s.nextSeq('ticket').toString().padLeft(4, '0')}',
        title: input.title,
        description: input.description,
        requestedCategory: input.category,
        requestedPriority: input.priority,
        category: input.category,
        priority: input.priority,
        status: TicketStatus.submitted,
        requesterId: actor.id,
        createdAt: now,
        updatedAt: now,
        slaDueAt: now,
      );
      s.tickets[t.id] = t;
      if (idemKey != null) s.idempotency[idemKey] = t.id;
      _audit(t, actor.id, 'submitted', to: TicketStatus.submitted, cid: cid);
      log.info('ticket.submitted', {'ticketId': t.id, 'requesterId': actor.id, 'correlationId': cid});

      outbox.enqueue(s, event: 'ticket.received', recipient: actor, ticketId: t.id, correlationId: cid);

      // Event-driven trigger: "ticket.created" is handled immediately, inside the same
      // transaction, so a ticket can never be saved without a routing decision.
      _onTicketCreated(s, t, cid);
      return t;
    });
  }

  Future<Ticket> respond(AppUser actor, String id, Map<String, dynamic> body, String cid) {
    final message = _text(body, 'message', min: 2, max: 2000);
    return _mutate(actor, id, cid, (s, t) {
      if (!t.isOpen && t.status != TicketStatus.resolved) throw ApiException.conflict('Ticket is closed.');
      final isStaff = actor.role != Roles.requester;
      if (isStaff && !_isAssigneeOrSupervisor(actor, t)) throw ApiException.forbidden('Only the assigned agent can respond.');
      t.responses.add(TicketResponse(at: clock.now(), authorId: actor.id, message: message));
      if (isStaff) {
        if (t.status == TicketStatus.assigned) _transition(t, actor.id, TicketStatus.inProgress, cid, note: 'first response');
        final requester = s.users[t.requesterId]!;
        outbox.enqueue(s,
            event: 'ticket.response', recipient: requester, ticketId: t.id, correlationId: cid, occurrence: '${t.responses.length}');
      } else {
        _audit(t, actor.id, 'requester_comment', cid: cid);
      }
    });
  }

  Future<Ticket> resolve(AppUser actor, String id, Map<String, dynamic> body, String cid) {
    final note = _text(body, 'resolution', min: 5, max: 1000);
    return _mutate(actor, id, cid, (s, t) {
      if (!_isAssigneeOrSupervisor(actor, t)) throw ApiException.forbidden('Only the assigned agent can resolve.');
      _requireStatus(t, {TicketStatus.assigned, TicketStatus.inProgress});
      t.resolvedAt = clock.now();
      _transition(t, actor.id, TicketStatus.resolved, cid, note: note);
      outbox.enqueue(s,
          event: 'ticket.resolved', recipient: s.users[t.requesterId]!, ticketId: t.id, correlationId: cid, occurrence: '${t.history.length}');
    });
  }

  Future<Ticket> confirm(AppUser actor, String id, String cid) => _mutate(actor, id, cid, (s, t) {
        if (actor.id != t.requesterId) throw ApiException.forbidden('Only the requester can confirm the resolution.');
        _requireStatus(t, {TicketStatus.resolved});
        t.closedAt = clock.now();
        _transition(t, actor.id, TicketStatus.closed, cid, note: 'requester confirmed resolution');
        if (t.assigneeId != null) {
          outbox.enqueue(s, event: 'ticket.closed', recipient: s.users[t.assigneeId]!, ticketId: t.id, correlationId: cid);
        }
      });

  Future<Ticket> reopen(AppUser actor, String id, Map<String, dynamic> body, String cid) {
    final reason = _text(body, 'reason', min: 5, max: 500);
    return _mutate(actor, id, cid, (s, t) {
      if (actor.id != t.requesterId) throw ApiException.forbidden('Only the requester can reopen.');
      _requireStatus(t, {TicketStatus.resolved});
      t.resolvedAt = null;
      _transition(t, actor.id, TicketStatus.inProgress, cid, note: 'reopened: $reason');
      if (t.assigneeId != null) {
        outbox.enqueue(s,
            event: 'ticket.reopened', recipient: s.users[t.assigneeId]!, ticketId: t.id, correlationId: cid, occurrence: '${t.history.length}');
      }
    });
  }

  Future<Ticket> reassign(AppUser actor, String id, Map<String, dynamic> body, String cid) {
    _requireRole(actor, {Roles.supervisor});
    final agentId = _text(body, 'agentId', min: 1, max: 64);
    final reason = _text(body, 'reason', min: 5, max: 500);
    return _mutate(actor, id, cid, (s, t) {
      _requireStatus(t, {TicketStatus.assigned, TicketStatus.inProgress, TicketStatus.needsTriage});
      final agent = s.users[agentId];
      if (agent == null || agent.role != Roles.agent) throw ApiException.validation({'agentId': 'Unknown agent.'});
      if (!agent.available) throw ApiException.validation({'agentId': 'Agent is marked unavailable.'});
      if (agent.id == t.assigneeId) throw ApiException.validation({'agentId': 'Ticket is already assigned to this agent.'});
      assignTo(s, t, agent, actor.id, cid, note: 'manual reassignment: $reason');
    });
  }

  /// Supervisor completes a ticket the rules could not route.
  Future<Ticket> triage(AppUser actor, String id, Map<String, dynamic> body, String cid) {
    _requireRole(actor, {Roles.supervisor});
    final category = body['category'];
    final priority = body['priority'];
    final errors = <String, String>{};
    if (category is! String || rules.teamFor(category) == null) errors['category'] = 'Choose a routable category.';
    if (priority is! String || !Priorities.all.contains(priority)) errors['priority'] = 'Choose a valid priority.';
    if (errors.isNotEmpty) throw ApiException.validation(errors);
    return _mutate(actor, id, cid, (s, t) {
      _requireStatus(t, {TicketStatus.needsTriage});
      t.category = category as String;
      t.priority = priority as String;
      t.team = rules.teamFor(category);
      t.routingReason = 'triaged by ${actor.id}';
      t.slaDueAt = t.createdAt.add(Duration(hours: config.slaHours[t.priority]!));
      final agent = pickAgent(s, t.team!);
      if (agent == null) throw ApiException.conflict('No available agent in team ${t.team}.');
      assignTo(s, t, agent, actor.id, cid, note: 'triaged');
    });
  }

  Future<AppUser> setAvailability(AppUser actor, String agentId, Map<String, dynamic> body, String cid) {
    _requireRole(actor, {Roles.supervisor});
    final available = body['available'];
    if (available is! bool) throw ApiException.validation({'available': 'Must be true or false.'});
    return store.transaction((s) {
      final agent = s.users[agentId];
      if (agent == null || agent.role != Roles.agent) throw ApiException.notFound('Agent');
      agent.available = available;
      log.info('agent.availability_changed', {'agentId': agentId, 'available': available, 'actorId': actor.id, 'correlationId': cid});
      return agent;
    });
  }

  // ---------------------------------------------------------------- routing (shared with automation)

  void _onTicketCreated(StoreState s, Ticket t, String cid) {
    final d = rules.decide(
      title: t.title,
      description: t.description,
      requestedCategory: t.requestedCategory,
      requestedPriority: t.requestedPriority,
    );
    t.category = d.category;
    t.priority = d.priority;
    t.team = d.team;
    t.routingReason = d.reason;
    t.slaDueAt = t.createdAt.add(Duration(hours: config.slaHours[t.priority]!));
    log.info('routing.decided', {
      'ticketId': t.id,
      'category': d.category,
      'priority': d.priority,
      'team': d.team,
      'reason': d.reason,
      'correlationId': cid,
    });

    final agent = d.team == null ? null : pickAgent(s, d.team!);
    if (agent == null) {
      sendToTriage(s, t, 'system:router', cid, d.team == null ? 'no routing rule matched' : 'no available agent in ${d.team}');
      return;
    }
    assignTo(s, t, agent, 'system:router', cid, note: d.reason);
  }

  /// Least-loaded available agent in the team; ties broken by id for repeatable results.
  AppUser? pickAgent(StoreState s, String team, {String? excludeId}) {
    final candidates = s.users.values
        .where((u) => u.role == Roles.agent && u.team == team && u.available && u.id != excludeId)
        .toList();
    if (candidates.isEmpty) return null;
    int load(AppUser u) => s.tickets.values.where((t) => t.assigneeId == u.id && t.isOpen).length;
    candidates.sort((a, b) {
      final byLoad = load(a).compareTo(load(b));
      return byLoad != 0 ? byLoad : a.id.compareTo(b.id);
    });
    return candidates.first;
  }

  void assignTo(StoreState s, Ticket t, AppUser agent, String actorId, String cid, {String? note}) {
    final previous = t.assigneeId;
    t.assigneeId = agent.id;
    t.team = agent.team;
    final event = previous == null ? 'ticket.assigned' : 'ticket.reassigned';
    if (t.status == TicketStatus.inProgress) {
      _audit(t, actorId, previous == null ? 'assigned' : 'reassigned', from: previous, to: agent.id, note: note, cid: cid);
    } else {
      _transition(t, actorId, TicketStatus.assigned, cid, note: note, assignee: agent.id);
    }
    log.info(previous == null ? 'ticket.assigned' : 'ticket.reassigned',
        {'ticketId': t.id, 'from': previous, 'to': agent.id, 'actorId': actorId, 'correlationId': cid});
    outbox.enqueue(s,
        event: event,
        recipient: agent,
        ticketId: t.id,
        correlationId: cid,
        occurrence: '${t.history.length}',
        vars: {'priority': t.priority});
  }

  void sendToTriage(StoreState s, Ticket t, String actorId, String cid, String reason) {
    t.assigneeId = null;
    _transition(t, actorId, TicketStatus.needsTriage, cid, note: reason);
    log.warn('ticket.needs_triage', {'ticketId': t.id, 'reason': reason, 'correlationId': cid});
    for (final sup in s.users.values.where((u) => u.role == Roles.supervisor)) {
      outbox.enqueue(s,
          event: 'ticket.needs_triage', recipient: sup, ticketId: t.id, correlationId: cid, occurrence: '${t.history.length}');
    }
  }

  // ---------------------------------------------------------------- helpers

  Future<Ticket> _mutate(AppUser actor, String id, String cid, void Function(StoreState s, Ticket t) fn) =>
      store.transaction((s) {
        final t = s.tickets[id];
        if (t == null || !canView(actor, t)) throw ApiException.notFound('Ticket');
        fn(s, t);
        t.updatedAt = clock.now();
        return t;
      });

  void _transition(Ticket t, String actorId, String to, String cid, {String? note, String? assignee}) {
    final from = t.status;
    t.status = to;
    _audit(t, actorId, 'status_changed', from: from, to: to, note: assignee == null ? note : '${note ?? ''} -> $assignee'.trim(), cid: cid);
    log.info('ticket.status_changed', {'ticketId': t.id, 'from': from, 'to': to, 'actorId': actorId, 'correlationId': cid});
  }

  void _audit(Ticket t, String actor, String action, {String? from, String? to, String? note, required String cid}) =>
      t.history.add(AuditEvent(at: clock.now(), actor: actor, action: action, from: from, to: to, note: note, correlationId: cid));

  bool _isAssigneeOrSupervisor(AppUser u, Ticket t) => u.role == Roles.supervisor || t.assigneeId == u.id;

  void _requireRole(AppUser u, Set<String> roles) {
    if (!roles.contains(u.role)) throw ApiException.forbidden();
  }

  void _requireStatus(Ticket t, Set<String> allowed) {
    if (!allowed.contains(t.status)) {
      throw ApiException.conflict('Action not allowed while ticket is ${t.status}.');
    }
  }

  String _text(Map<String, dynamic> body, String field, {required int min, required int max}) {
    final v = body[field];
    if (v is! String || v.trim().length < min || v.trim().length > max) {
      throw ApiException.validation({field: 'Must be $min-$max characters.'});
    }
    return v.trim();
  }
}

class CreateTicketInput {
  final String title, description, category, priority;
  CreateTicketInput(this.title, this.description, this.category, this.priority);
}

/// Server-side validation is authoritative; the Flutter form mirrors these rules.
CreateTicketInput validateCreate(Map<String, dynamic> b) {
  final errors = <String, String>{};
  final title = b['title'], description = b['description'];
  final category = b['category'] ?? 'auto', priority = b['priority'];

  if (title is! String || title.trim().length < 5 || title.trim().length > 120) {
    errors['title'] = 'Title must be 5-120 characters.';
  }
  if (description is! String || description.trim().length < 10 || description.trim().length > 2000) {
    errors['description'] = 'Description must be 10-2000 characters.';
  }
  if (category is! String || !(category == 'auto' || Categories.all.contains(category))) {
    errors['category'] = 'Unknown category.';
  }
  if (priority is! String || !Priorities.all.contains(priority)) {
    errors['priority'] = 'Priority must be low, medium, high or critical.';
  }
  final unknown = b.keys.toSet().difference({'title', 'description', 'category', 'priority'});
  if (unknown.isNotEmpty) errors['_'] = 'Unexpected fields: ${unknown.join(', ')}';
  if (errors.isNotEmpty) throw ApiException.validation(errors);

  return CreateTicketInput((title as String).trim(), (description as String).trim(), category as String, priority as String);
}
