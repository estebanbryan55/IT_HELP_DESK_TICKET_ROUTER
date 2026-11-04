import 'dart:convert';
import 'dart:io';

/// Structured JSON-lines logger. Sensitive field names are redacted before writing.
class Log {
  static const _sensitive = {
    'password', 'token', 'authorization', 'apikey', 'api_key', 'secret',
    'email', 'address', 'to', 'title', 'description', 'message', 'body',
  };

  final IOSink? _file;
  final bool echo;
  final DateTime Function() now;

  /// Last records kept in memory so tests can assert on log output.
  final List<Map<String, Object?>> recent = [];

  Log({String? filePath, this.echo = true, DateTime Function()? now})
      : now = now ?? (() => DateTime.now().toUtc()),
        _file = filePath == null ? null : _open(filePath);

  static IOSink _open(String path) {
    final f = File(path);
    f.parent.createSync(recursive: true);
    return f.openWrite(mode: FileMode.append);
  }

  void info(String event, [Map<String, Object?> fields = const {}]) => _write('INFO', event, fields);
  void warn(String event, [Map<String, Object?> fields = const {}]) => _write('WARN', event, fields);
  void error(String event, [Map<String, Object?> fields = const {}]) => _write('ERROR', event, fields);

  void _write(String level, String event, Map<String, Object?> fields) {
    final record = <String, Object?>{
      'ts': now().toIso8601String(),
      'level': level,
      'event': event,
      for (final e in fields.entries) e.key: _sensitive.contains(e.key.toLowerCase()) ? '[REDACTED]' : e.value,
    };
    recent.add(record);
    if (recent.length > 500) recent.removeAt(0);
    final line = jsonEncode(record);
    if (echo) stdout.writeln(line);
    _file?.writeln(line);
  }

  Future<void> close() async {
    await _file?.flush();
    await _file?.close();
  }
}
