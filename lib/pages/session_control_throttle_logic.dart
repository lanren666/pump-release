/// Pure logic for throttling session control commands (start / pause / switch).
///
/// The firmware drops commands that arrive too quickly in succession.
/// A command is allowed only when [thresholdMs] has elapsed since the
/// previous dispatch.  Pass null for [lastDispatch] on the very first call.
class SessionControlThrottleLogic {
  SessionControlThrottleLogic._();

  static const int defaultThresholdMs = 1500;

  /// Returns true if the command should be dispatched.
  static bool shouldDispatch({
    required DateTime? lastDispatch,
    required DateTime now,
    int thresholdMs = defaultThresholdMs,
  }) {
    if (lastDispatch == null) return true;
    return now.difference(lastDispatch).inMilliseconds >= thresholdMs;
  }
}
