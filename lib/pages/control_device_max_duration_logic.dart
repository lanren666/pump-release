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

  /// Clears firmware maxTime only when both sides are idle so the next
  /// session reads the UI max.  While the other side is still running the
  /// stopped side's last report is kept — otherwise the Both card would
  /// fall through to the remaining side (e.g. show 20 after a 15-min end).
  static ({int? left, int? right}) clearOnStop({
    required bool isLeftDevice,
    required bool otherSideRunning,
    required int? left,
    required int? right,
  }) {
    if (!otherSideRunning) {
      return (left: null, right: null);
    }
    return (left: left, right: right);
  }

  /// Firmware maxTime shown on the timer card for the current selection.
  /// Both prefers left (same as the unified time display) and falls back
  /// to right.  When the two sides disagree, returns null so the card
  /// uses the UI dropdown value instead of mixing 15 and 20.
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
        if (left != null && right != null && left != right) {
          return null;
        }
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
