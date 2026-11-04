import 'dart:math';

/// Bounded exponential backoff with "equal jitter":
/// delay(n) = e/2 + random(0, e/2), where e = min(maxDelay, baseDelay * 2^(n-1)).
/// Jitter spreads retries so many failed messages do not hit the gateway at the same instant.
class RetryPolicy {
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final Random _random;

  RetryPolicy({required this.maxAttempts, required this.baseDelay, required this.maxDelay, Random? random})
      : _random = random ?? Random();

  /// [attempt] is the number of attempts already made (1 after the first failure).
  Duration delayAfter(int attempt) {
    final exp = min(maxDelay.inMilliseconds, baseDelay.inMilliseconds * pow(2, attempt - 1).toInt());
    final half = exp ~/ 2;
    return Duration(milliseconds: half + (half == 0 ? 0 : _random.nextInt(half + 1)));
  }

  bool canRetry(int attemptsMade) => attemptsMade < maxAttempts;
}

enum FailureKind { none, transient, permanent }

/// Classifies a gateway outcome. Only transient failures are retried.
FailureKind classifyHttpStatus(int status) {
  if (status >= 200 && status < 300) return FailureKind.none;
  if (status == 408 || status == 425 || status == 429 || status >= 500) return FailureKind.transient;
  return FailureKind.permanent; // other 4xx: bad recipient, bad request, auth problem
}
