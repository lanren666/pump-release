/// Pure decision helper for the fresh-start elapsed-time reset.
///
/// Extracted so the invariant can be unit-tested without the widget tree.
class ControlStartResetLogic {
  ControlStartResetLogic._();

  /// Returns true when pressing Start should reset elapsed-time display
  /// variables to zero.
  ///
  /// Only true for a fully-stopped state (hasStarted=false AND isRunning=false),
  /// i.e. after the user pressed Stop.  Returns false for pause→resume
  /// (hasStarted=true) so the elapsed time accumulated so far is preserved.
  static bool shouldResetElapsedTimeOnStart({
    required bool currentHasStarted,
    required bool currentIsRunning,
  }) {
    return !currentHasStarted && !currentIsRunning;
  }
}
