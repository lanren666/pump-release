import 'control_types.dart';

/// Per-side firmware maxTime (DP-105) tracking for the control page.
///
/// A single shared `_deviceMaxDuration` was overwritten by whichever side
/// last reported, so the timer card could show 20 while the dropdown still
/// showed 15, and kick/natural-end used the wrong limit for the dropped side.
class ControlDeviceMaxDurationLogic {
  const ControlDeviceMaxDurationLogic._();

  /// Applies the reporting side's firmware [maxTime] without touching the other.
  static ({int? left, int? right}) applyReportedMaxTime({
    required bool isLeftDevice,
    required int maxTime,
    required int? left,
    required int? right,
  }) {
    if (isLeftDevice) {
      return (left: maxTime, right: right);
    }
    return (left: left, right: maxTime);
  }

  /// Clears firmware maxTime for a side that stopped.  When the other side
  /// is also idle, both values are cleared so the next session reads UI max.
  static ({int? left, int? right}) clearOnStop({
    required bool isLeftDevice,
    required bool otherSideRunning,
    required int? left,
    required int? right,
  }) {
    if (!otherSideRunning) {
      return (left: null, right: null);
    }
    if (isLeftDevice) {
      return (left: null, right: right);
    }
    return (left: left, right: null);
  }

  /// Firmware maxTime shown on the timer card for the current selection.
  /// Both mode prefers left (same as the unified time display) and falls
  /// back to right when left has not reported.
  static int? displayDeviceMaxDuration({
    required PumpSelection selected,
    required int? left,
    required int? right,
  }) {
    switch (selected) {
      case PumpSelection.left:
        return left;
      case PumpSelection.right:
        return right;
      case PumpSelection.both:
        return left ?? right;
    }
  }

  /// Firmware maxTime used for kick / natural-end on one side.
  static int? sideDeviceMaxDuration({
    required bool isLeft,
    required int? left,
    required int? right,
  }) {
    return isLeft ? left : right;
  }
}
