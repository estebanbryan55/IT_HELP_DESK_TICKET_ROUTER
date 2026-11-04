import 'dart:io';

/// Reads KEY=VALUE lines from an env file. Missing file returns an empty map.
Map<String, String> readEnvFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return {};
  final values = <String, String>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    values[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
  }
  return values;
}

/// Precedence: overrides > process environment > .env file > defaults.
Map<String, String> loadSettings({String envFile = '.env', Map<String, String> overrides = const {}}) =>
    {...readEnvFile(envFile), ...Platform.environment, ...overrides};

class AppConfig {
  final String env;
  final String host;
  final int port;
  final String? dataFile;
  final String? logFile;
  final String rulesFile;
  final List<String> allowedOrigins;
  final bool demoAuthEnabled;

  final Uri gatewayUrl;
  final String gatewayApiKey;
  final Duration gatewayTimeout;

  final int retryMaxAttempts;
  final Duration retryBaseDelay;
  final Duration retryMaxDelay;

  final Duration outboxPollInterval;
  final Duration agingScanInterval;
  final Duration summaryCheckInterval;
  final int summaryHour;
  final int timezoneOffsetHours;

  final Map<String, int> slaHours;
  final double slaWarningRatio;

  AppConfig({
    required this.env,
    required this.host,
    required this.port,
    required this.dataFile,
    required this.logFile,
    required this.rulesFile,
    required this.allowedOrigins,
    required this.demoAuthEnabled,
    required this.gatewayUrl,
    required this.gatewayApiKey,
    required this.gatewayTimeout,
    required this.retryMaxAttempts,
    required this.retryBaseDelay,
    required this.retryMaxDelay,
    required this.outboxPollInterval,
    required this.agingScanInterval,
    required this.summaryCheckInterval,
    required this.summaryHour,
    required this.timezoneOffsetHours,
    required this.slaHours,
    required this.slaWarningRatio,
  });

  bool get isDevelopment => env == 'development';

  factory AppConfig.fromMap(Map<String, String> m) {
    String s(String k, String d) => (m[k] == null || m[k]!.isEmpty) ? d : m[k]!;
    int i(String k, int d) => int.tryParse(m[k] ?? '') ?? d;
    String? path(String k, String d) => s(k, d) == 'none' ? null : s(k, d);

    final apiKey = m['GATEWAY_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      throw StateError('GATEWAY_API_KEY is not set. Copy .env.example to .env and set a local value.');
    }

    return AppConfig(
      env: s('APP_ENV', 'development'),
      host: s('HOST', '127.0.0.1'),
      port: i('PORT', 8080),
      dataFile: path('DATA_FILE', 'data/store.json'),
      logFile: path('LOG_FILE', 'logs/app.log'),
      rulesFile: s('RULES_FILE', 'config/routing_rules.json'),
      allowedOrigins: s('ALLOWED_ORIGINS', 'http://localhost:*').split(',').map((e) => e.trim()).toList(),
      demoAuthEnabled: s('DEMO_AUTH_ENABLED', 'true') == 'true',
      gatewayUrl: Uri.parse(s('GATEWAY_URL', 'http://127.0.0.1:8091')),
      gatewayApiKey: apiKey,
      gatewayTimeout: Duration(milliseconds: i('GATEWAY_TIMEOUT_MS', 3000)),
      retryMaxAttempts: i('RETRY_MAX_ATTEMPTS', 4),
      retryBaseDelay: Duration(milliseconds: i('RETRY_BASE_DELAY_MS', 2000)),
      retryMaxDelay: Duration(milliseconds: i('RETRY_MAX_DELAY_MS', 30000)),
      outboxPollInterval: Duration(seconds: i('OUTBOX_POLL_SECONDS', 5)),
      agingScanInterval: Duration(seconds: i('AGING_SCAN_SECONDS', 60)),
      summaryCheckInterval: Duration(seconds: i('SUMMARY_CHECK_SECONDS', 60)),
      summaryHour: i('SUMMARY_HOUR', 18),
      timezoneOffsetHours: i('TIMEZONE_OFFSET_HOURS', 8),
      slaHours: {
        'critical': i('SLA_HOURS_CRITICAL', 4),
        'high': i('SLA_HOURS_HIGH', 8),
        'medium': i('SLA_HOURS_MEDIUM', 24),
        'low': i('SLA_HOURS_LOW', 72),
      },
      slaWarningRatio: double.tryParse(m['SLA_WARNING_RATIO'] ?? '') ?? 0.75,
    );
  }

  /// Safe description for startup logs: no secrets.
  Map<String, Object?> describe() => {
        'env': env,
        'port': port,
        'gateway': gatewayUrl.toString(),
        'gatewayApiKey': '[set]',
        'retryMaxAttempts': retryMaxAttempts,
        'retryBaseDelayMs': retryBaseDelay.inMilliseconds,
        'outboxPollSeconds': outboxPollInterval.inSeconds,
        'agingScanSeconds': agingScanInterval.inSeconds,
        'demoAuthEnabled': demoAuthEnabled,
      };
}

/// Injectable clock so SLA aging can be tested and demonstrated without waiting hours.
class Clock {
  Duration offset = Duration.zero;
  DateTime now() => DateTime.now().toUtc().add(offset);
}
