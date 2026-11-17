/// Build-time configuration. Nothing secret belongs here: everything compiled
/// into a Flutter Web app can be read by anyone who loads the page.
///
///   flutter run -d chrome --web-port 5000 \
///     --dart-define=API_BASE_URL=https://helpdesk-api.example.test/api/v1
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8010/api/v1',
  );

  static const requestTimeout = Duration(seconds: 15);

  /// Warn in the UI when a non-local API is reached over plain HTTP.
  static bool get isInsecureRemote {
    final uri = Uri.parse(apiBaseUrl);
    final local = uri.host == 'localhost' || uri.host == '127.0.0.1';
    return uri.scheme != 'https' && !local;
  }
}
