import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Serialises async work so only one transaction mutates state at a time.
class Lock {
  Future<void> _tail = Future.value();

  Future<T> synchronized<T>(Future<T> Function() fn) {
    final result = Completer<T>();
    final done = Completer<void>();
    final previous = _tail;
    _tail = done.future;
    previous.whenComplete(() async {
      try {
        result.complete(await fn());
      } catch (e, st) {
        result.completeError(e, st);
      } finally {
        done.complete();
      }
    });
    return result.future;
  }
}

class StoreState {
  final Map<String, AppUser> users;
  final Map<String, Ticket> tickets;
  final Map<String, OutboxMessage> outbox;
  final List<JobRun> jobRuns;
  final List<SupportSummary> summaries;

  /// `userId:Idempotency-Key` -> ticket id, so a resubmitted form does not create a duplicate.
  final Map<String, String> idempotency;
  final Map<String, int> counters;

  StoreState({
    required this.users,
    required this.tickets,
    required this.outbox,
    required this.jobRuns,
    required this.summaries,
    required this.idempotency,
    required this.counters,
  });

  int nextSeq(String name) => counters[name] = (counters[name] ?? 0) + 1;

  factory StoreState.fromJson(Map<String, dynamic> j) => StoreState(
        users: {for (final u in j['users'] as List) u['id'] as String: AppUser.fromJson(u)},
        tickets: {for (final t in j['tickets'] as List) t['id'] as String: Ticket.fromJson(t)},
        outbox: {for (final m in j['outbox'] as List) m['id'] as String: OutboxMessage.fromJson(m)},
        jobRuns: [for (final r in j['jobRuns'] as List) JobRun.fromJson(r)],
        summaries: [for (final s in j['summaries'] as List) SupportSummary.fromJson(s)],
        idempotency: Map<String, String>.from(j['idempotency']),
        counters: Map<String, int>.from(j['counters']),
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'users': [for (final u in users.values) u.toJson()],
        'tickets': [for (final t in tickets.values) t.toJson()],
        'outbox': [for (final m in outbox.values) m.toJson()],
        'jobRuns': [for (final r in jobRuns) r.toJson()],
        'summaries': [for (final s in summaries) s.toJson()],
        'idempotency': idempotency,
        'counters': counters,
      };

  /// Fictional seed users only. Addresses use reserved .test domains.
  factory StoreState.seed() {
    final users = [
      AppUser(id: 'req-ana', displayName: 'Ana Reyes (Student)', role: Roles.requester, email: 'ana.reyes@students.helpdesk.test'),
      AppUser(id: 'req-ben', displayName: 'Ben Santos (Employee)', role: Roles.requester, email: 'ben.santos@staff.helpdesk.test'),
      // Mailbox decommissioned: every notification to this user is rejected by the gateway (permanent failure).
      AppUser(id: 'req-gio', displayName: 'Gio Cruz (Alumni account)', role: Roles.requester, email: 'gio.cruz@invalid.test'),
      AppUser(id: 'agent-carla', displayName: 'Carla Dizon', role: Roles.agent, team: 'network', email: 'carla@support.helpdesk.test'),
      AppUser(id: 'agent-noel', displayName: 'Noel Garcia', role: Roles.agent, team: 'network', email: 'noel@support.helpdesk.test'),
      AppUser(id: 'agent-dan', displayName: 'Dan Lim', role: Roles.agent, team: 'software', email: 'dan@support.helpdesk.test'),
      AppUser(id: 'agent-eli', displayName: 'Eli Ramos', role: Roles.agent, team: 'hardware', email: 'eli@support.helpdesk.test'),
      AppUser(id: 'agent-faith', displayName: 'Faith Torres', role: Roles.agent, team: 'accounts', email: 'faith@support.helpdesk.test'),
      AppUser(id: 'sup-mara', displayName: 'Mara Villanueva (Supervisor)', role: Roles.supervisor, email: 'mara@support.helpdesk.test'),
    ];
    return StoreState(
      users: {for (final u in users) u.id: u},
      tickets: {},
      outbox: {},
      jobRuns: [],
      summaries: [],
      idempotency: {},
      counters: {},
    );
  }
}

/// In-memory state persisted to a JSON file with atomic replace.
/// A failed transaction is rolled back to the snapshot taken before it started.
class JsonStore {
  final String? path;
  StoreState state;
  final _lock = Lock();

  JsonStore._(this.path, this.state);

  static JsonStore memory([StoreState? state]) => JsonStore._(null, state ?? StoreState.seed());

  static Future<JsonStore> open(String path) async {
    final f = File(path);
    if (await f.exists()) {
      return JsonStore._(path, StoreState.fromJson(jsonDecode(await f.readAsString())));
    }
    final store = JsonStore._(path, StoreState.seed());
    await store._persist();
    return store;
  }

  T read<T>(T Function(StoreState s) fn) => fn(state);

  Future<T> transaction<T>(FutureOr<T> Function(StoreState s) fn) => _lock.synchronized(() async {
        final snapshot = jsonEncode(state.toJson());
        try {
          final result = await fn(state);
          await _persist();
          return result;
        } catch (_) {
          state = StoreState.fromJson(jsonDecode(snapshot));
          rethrow;
        }
      });

  Future<void> _persist() async {
    if (path == null) return;
    final target = File(path!);
    await target.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(state.toJson()), flush: true);
    await tmp.rename(target.path);
  }
}
