import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import 'automation.dart';
import 'config.dart';
import 'errors.dart';
import 'gateway.dart';
import 'logger.dart';
import 'models.dart';
import 'outbox.dart';
import 'store.dart';
import 'tickets.dart';

const _uuid = Uuid();
const _maxBodyBytes = 16 * 1024;
final _cidPattern = RegExp(r'^[A-Za-z0-9\-]{8,64}$');

class AppContext {
  final AppConfig config;
  final JsonStore store;
  final Clock clock;
  final Log log;
  final NotificationGateway gateway;
  final Outbox outbox;
  final TicketService tickets;
  final AgingScanner aging;
  final SummaryService summaries;
  final Scheduler scheduler;

  AppContext({
    required this.config,
    required this.store,
    required this.clock,
    required this.log,
    required this.gateway,
    required this.outbox,
    required this.tickets,
    required this.aging,
    required this.summaries,
    required this.scheduler,
  });
}

Response _json(Object? body, {int status = 200}) =>
    Response(status, body: jsonEncode(body), headers: {'Content-Type': 'application/json'});

String cidOf(Request r) => r.context['cid'] as String;

Future<Map<String, dynamic>> _body(Request r) async {
  final text = await r.readAsString();
  if (utf8.encode(text).length > _maxBodyBytes) throw ApiException(413, 'payload_too_large', 'Request body is too large.');
  if (text.trim().isEmpty) return {};
  final decoded = jsonDecode(text); // FormatException -> 400 in error middleware
  if (decoded is! Map<String, dynamic>) throw ApiException(400, 'bad_request', 'Body must be a JSON object.');
  return decoded;
}

Handler buildHandler(AppContext ctx) {
  final r = Router();
  final config = ctx.config;

  /// Week 13 demo identity: the X-Demo-User header names a seeded user.
  /// The role is looked up on the server; the client never asserts its own role.
  /// Replaced by token-based authentication in Week 14.
  AppUser auth(Request req) {
    if (!config.demoAuthEnabled) throw ApiException.unauthenticated();
    final id = req.headers['x-demo-user'];
    final user = id == null ? null : ctx.store.read((s) => s.users[id]);
    if (user == null) throw ApiException.unauthenticated();
    return user;
  }

  void requireRole(AppUser u, Set<String> roles) {
    if (!roles.contains(u.role)) throw ApiException.forbidden();
  }

  Map<String, dynamic> ticketView(Ticket t) {
    final j = t.toJson();
    final names = ctx.store.read((s) => {for (final u in s.users.values) u.id: u.displayName});
    j['requesterName'] = names[t.requesterId];
    j['assigneeName'] = t.assigneeId == null ? null : names[t.assigneeId];
    return j;
  }

  // ------------------------------------------------------------ health

  r.get('/health', (Request req) async {
    final gatewayUp = await ctx.gateway.ping();
    final counts = ctx.store.read((s) => {
          'pending': s.outbox.values.where((m) => OutboxStatus.due.contains(m.status)).length,
          'inFlight': s.outbox.values.where((m) => m.status == OutboxStatus.sending).length,
          'deadLetter': s.outbox.values.where((m) => m.status == OutboxStatus.deadLetter).length,
        });
    return _json({
      'status': gatewayUp ? 'ok' : 'degraded',
      'version': '0.13.0',
      'time': ctx.clock.now().toIso8601String(),
      'checks': {'store': 'ok', 'notificationGateway': gatewayUp ? 'ok' : 'unreachable', 'outbox': counts},
    });
  });

  // ------------------------------------------------------------ identity

  r.get('/api/v1/demo/users', (Request req) {
    if (!config.demoAuthEnabled) throw ApiException.notFound('Resource');
    return _json(ctx.store.read((s) => [for (final u in s.users.values) u.toPublicJson()]));
  });

  r.get('/api/v1/me', (Request req) => _json(auth(req).toPublicJson()));

  r.get('/api/v1/agents', (Request req) {
    requireRole(auth(req), {Roles.supervisor, Roles.agent});
    return _json(ctx.store.read((s) => [
          for (final u in s.users.values.where((u) => u.role == Roles.agent))
            {
              ...u.toPublicJson(),
              'openTickets': s.tickets.values.where((t) => t.assigneeId == u.id && t.isOpen).length,
            }
        ]));
  });

  r.patch('/api/v1/agents/<id>/availability', (Request req, String id) async {
    final agent = await ctx.tickets.setAvailability(auth(req), id, await _body(req), cidOf(req));
    return _json(agent.toPublicJson());
  });

  // ------------------------------------------------------------ tickets

  r.get('/api/v1/tickets', (Request req) {
    final user = auth(req);
    final status = req.url.queryParameters['status'];
    if (status != null && !TicketStatus.all.contains(status)) {
      throw ApiException.validation({'status': 'Unknown status.'});
    }
    return _json([for (final t in ctx.tickets.listFor(user, status: status)) ticketView(t)]);
  });

  r.post('/api/v1/tickets', (Request req) async {
    final user = auth(req);
    final key = req.headers['idempotency-key'];
    if (key != null && !_cidPattern.hasMatch(key)) {
      throw ApiException.validation({'Idempotency-Key': 'Must be 8-64 letters, digits or dashes.'});
    }
    final t = await ctx.tickets.create(user, await _body(req), idempotencyKey: key, cid: cidOf(req));
    return _json(ticketView(t), status: 201);
  });

  r.get('/api/v1/tickets/<id>', (Request req, String id) => _json(ticketView(ctx.tickets.getFor(auth(req), id))));

  r.post('/api/v1/tickets/<id>/responses', (Request req, String id) async =>
      _json(ticketView(await ctx.tickets.respond(auth(req), id, await _body(req), cidOf(req)))));
  r.post('/api/v1/tickets/<id>/resolve', (Request req, String id) async =>
      _json(ticketView(await ctx.tickets.resolve(auth(req), id, await _body(req), cidOf(req)))));
  r.post('/api/v1/tickets/<id>/confirm', (Request req, String id) async =>
      _json(ticketView(await ctx.tickets.confirm(auth(req), id, cidOf(req)))));
  r.post('/api/v1/tickets/<id>/reopen', (Request req, String id) async =>
      _json(ticketView(await ctx.tickets.reopen(auth(req), id, await _body(req), cidOf(req)))));
  r.post('/api/v1/tickets/<id>/reassign', (Request req, String id) async =>
      _json(ticketView(await ctx.tickets.reassign(auth(req), id, await _body(req), cidOf(req)))));
  r.post('/api/v1/tickets/<id>/triage', (Request req, String id) async =>
      _json(ticketView(await ctx.tickets.triage(auth(req), id, await _body(req), cidOf(req)))));

  // ------------------------------------------------------------ automation (supervisor)

  r.get('/api/v1/automation/notifications', (Request req) {
    requireRole(auth(req), {Roles.supervisor});
    final status = req.url.queryParameters['status'];
    final list = ctx.store.read((s) => s.outbox.values.where((m) => status == null || m.status == status).toList())
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _json([for (final m in list.take(200)) m.toPublicJson()]);
  });

  r.post('/api/v1/automation/notifications/<id>/retry', (Request req, String id) async {
    final user = auth(req);
    requireRole(user, {Roles.supervisor});
    return _json((await ctx.outbox.manualRetry(user, id, cidOf(req))).toPublicJson());
  });

  r.post('/api/v1/automation/notifications/<id>/dismiss', (Request req, String id) async {
    final user = auth(req);
    requireRole(user, {Roles.supervisor});
    final note = (await _body(req))['note'];
    return _json((await ctx.outbox.dismiss(user, id, note is String ? note : '', cidOf(req))).toPublicJson());
  });

  r.get('/api/v1/automation/runs', (Request req) {
    requireRole(auth(req), {Roles.supervisor});
    final job = req.url.queryParameters['job'];
    final runs = ctx.store.read((s) => s.jobRuns.where((j) => job == null || j.job == job).toList().reversed.take(100));
    return _json([for (final j in runs) j.toJson()]);
  });

  r.post('/api/v1/automation/jobs/<job>/run', (Request req, String job) async {
    requireRole(auth(req), {Roles.supervisor});
    final JobRun? run = switch (job) {
      'aging-scan' => await ctx.scheduler.runJob(job, 'manual', ctx.aging.run),
      'outbox-dispatch' => await ctx.scheduler.runJob(job, 'manual', (_) async => (await ctx.outbox.dispatchDue()).toJson()),
      'daily-summary' => await ctx.scheduler.runJob(job, 'manual', (cid) async => {'summaryId': (await ctx.summaries.generate('manual', cid)).id}),
      _ => throw ApiException.notFound('Job'),
    };
    if (run == null) throw ApiException.conflict('Job is already running.');
    return _json(run.toJson());
  });

  // ------------------------------------------------------------ summaries

  r.get('/api/v1/summaries/latest', (Request req) {
    requireRole(auth(req), {Roles.supervisor, Roles.agent});
    final latest = ctx.store.read((s) => s.summaries.isEmpty ? null : s.summaries.last);
    if (latest == null) throw ApiException.notFound('Summary');
    return _json(latest.toJson());
  });

  // ------------------------------------------------------------ development only

  r.post('/api/v1/dev/clock/advance', (Request req) async {
    if (!config.isDevelopment) throw ApiException.notFound('Resource');
    final user = auth(req);
    requireRole(user, {Roles.supervisor});
    final minutes = (await _body(req))['minutes'];
    if (minutes is! int || minutes < 1 || minutes > 7 * 24 * 60) {
      throw ApiException.validation({'minutes': 'Must be 1-10080.'});
    }
    ctx.clock.offset += Duration(minutes: minutes);
    ctx.log.warn('dev.clock_advanced', {'minutes': minutes, 'offsetMinutes': ctx.clock.offset.inMinutes, 'actorId': user.id, 'correlationId': cidOf(req)});
    return _json({'now': ctx.clock.now().toIso8601String(), 'offsetMinutes': ctx.clock.offset.inMinutes});
  });

  r.all('/<ignored|.*>', (Request req) => throw ApiException.notFound('Route'));

  return const Pipeline()
      .addMiddleware(_correlation())
      .addMiddleware(_cors(config.allowedOrigins))
      .addMiddleware(_accessLog(ctx.log))
      .addMiddleware(_errors(ctx.log))
      .addHandler(r.call);
}

Middleware _correlation() => (inner) => (req) async {
      final incoming = req.headers['x-correlation-id'];
      final cid = incoming != null && _cidPattern.hasMatch(incoming) ? incoming : _uuid.v4();
      final res = await inner(req.change(context: {'cid': cid}));
      return res.change(headers: {'X-Correlation-Id': cid});
    };

bool originAllowed(String origin, List<String> allowed) => allowed.any((pattern) {
      if (pattern.endsWith(':*')) {
        final prefix = pattern.substring(0, pattern.length - 1);
        return origin.startsWith(prefix) && RegExp(r'^\d+$').hasMatch(origin.substring(prefix.length));
      }
      return origin == pattern;
    });

Middleware _cors(List<String> allowed) => (inner) => (req) async {
      final origin = req.headers['origin'];
      final ok = origin != null && originAllowed(origin, allowed);
      final headers = ok
          ? {
              'Access-Control-Allow-Origin': origin,
              'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS',
              'Access-Control-Allow-Headers': 'Content-Type, X-Demo-User, Idempotency-Key, X-Correlation-Id',
              'Access-Control-Expose-Headers': 'X-Correlation-Id',
              'Vary': 'Origin',
            }
          : <String, String>{};
      if (req.method == 'OPTIONS') return Response(ok ? 204 : 403, headers: headers);
      final res = await inner(req);
      return res.change(headers: headers);
    };

Middleware _accessLog(Log log) => (inner) => (req) async {
      final sw = Stopwatch()..start();
      final res = await inner(req);
      log.info('http.request', {
        'method': req.method,
        'path': '/${req.url.path}',
        'status': res.statusCode,
        'durationMs': sw.elapsedMilliseconds,
        'userId': req.headers['x-demo-user'],
        'correlationId': req.context['cid'],
      });
      return res;
    };

Middleware _errors(Log log) => (inner) => (req) async {
      final cid = req.context['cid'];
      Response fail(int status, String code, String message, [Map<String, String>? details]) => _json({
            'error': {'code': code, 'message': message, 'details': ?details, 'correlationId': cid},
          }, status: status);
      try {
        return await inner(req);
      } on ApiException catch (e) {
        if (e.status >= 500) log.error('api.error', {'code': e.code, 'correlationId': cid});
        return fail(e.status, e.code, e.message, e.details);
      } on FormatException {
        return fail(400, 'bad_request', 'Body is not valid JSON.');
      } catch (e, st) {
        // Full detail stays in the protected log; the client gets a generic message.
        log.error('api.unhandled', {'error': e.toString(), 'stack': st.toString().split('\n').take(5).join(' | '), 'correlationId': cid});
        return fail(500, 'internal_error', 'Unexpected server error. Quote the correlation id when reporting it.');
      }
    };
