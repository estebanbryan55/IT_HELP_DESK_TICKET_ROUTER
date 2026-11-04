/// An error that is safe to return to the client as-is.
class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  final Map<String, String>? details;

  ApiException(this.status, this.code, this.message, [this.details]);

  factory ApiException.validation(Map<String, String> details) =>
      ApiException(422, 'validation_failed', 'One or more fields are invalid.', details);
  factory ApiException.unauthenticated() =>
      ApiException(401, 'unauthenticated', 'Sign in is required.');
  factory ApiException.forbidden([String message = 'You are not allowed to perform this action.']) =>
      ApiException(403, 'forbidden', message);
  factory ApiException.notFound(String what) => ApiException(404, 'not_found', '$what was not found.');
  factory ApiException.conflict(String message) => ApiException(409, 'invalid_state', message);

  @override
  String toString() => 'ApiException($status $code: $message)';
}
