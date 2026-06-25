import 'control_types.dart';

/// Pure decision helpers for DP-105 handling and page-resume state restoration.
///
/// Extracted so the logic can be unit-tested without the widget tree.
class ControlNavigationResumeLogic {
  const ControlNavigationResumeLogic._();

  /// Computes updated hasStarted flags for _loadDevices() after a page rebuild.
  ///
  /// Only restores hasStarted when BOTH devices are running in the DB.
  /// This prevents the DP105 "hardware manual start" auto-switch from
  /// incorrectly switching Both mode to single-side on page rebuild.
  /// When only one device is running, hasStarted stays false so the
  /// existing auto-switch correctly restores the single-side tab.
  static ({bool left, bool right}) restoreHasStarted({
    required bool leftRunning,
    required bool rightRunning,
    required bool leftHasStarted,
    required bool rightHasStarted,
  }) {
    if (leftRunning && rightRunning) {
      return (
        left: leftHasStarted || leftRunning,
        right: rightHasStarted || rightRunning,
      );
    }
    return (left: leftHasStarted, right: rightHasStarted);
  }

  /// Mirrors _getCurrentHasStarted(): true when the currently selected side
  /// has been started (used to compute shouldUpdate in the DP handler).
  static bool getCurrentHasStarted({
    required PumpSelection selectedPump,
    required bool leftHasStarted,
    required bool rightHasStarted,
  }) {
    switch (selectedPump) {
      case PumpSelection.left:
        return leftHasStarted;
      case PumpSelection.right:
        return rightHasStarted;
      case PumpSelection.both:
        return leftHasStarted || rightHasStarted;
    }
  }

  /// DP105 isRunning=1: should the normal update path run (true) or fall
  /// through to the auto-switch / safe-update path (false)?
  static bool shouldUpdateOnDp105({
    required bool appIsRunning,
    required bool isIndividualMode,
  }) {
    return appIsRunning || isIndividualMode;
  }

  /// When shouldUpdate is false and the current selection is Both, determines
  /// whether to safe-update (no tab switch) or let auto-switch proceed.
  ///
  /// Safe-update fires when the Both session is already in progress (either
  /// the app already marked it started, or sequential start is underway).
  static bool shouldSafeUpdateBothMode({
    required PumpSelection selectedPump,
    required bool bothStartInProgress,
    required bool leftHasStarted,
    required bool rightHasStarted,
  }) {
    return selectedPump == PumpSelection.both &&
        (bothStartInProgress || leftHasStarted || rightHasStarted);
  }

  /// Whether the battery-alert flag should be cleared for the reporting device.
  ///
  /// The flag is cleared only at the start of a brand-new session
  /// (hasStarted == false).  Skipping it for resumed sessions avoids
  /// stacking a second dialog on top of an already-showing one when
  /// firmware sends a spurious isRunning=0 → isRunning=1 mid-session.
  static bool shouldClearBatteryAlertFlag({
    required bool isLeftDevice,
    required bool leftHasStarted,
    required bool rightHasStarted,
  }) {
    return isLeftDevice ? !leftHasStarted : !rightHasStarted;
  }
}
