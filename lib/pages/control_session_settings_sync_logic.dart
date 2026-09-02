import 'control_types.dart';

/// Shared session-settings write/restore rules used by ControlPage.
///
/// Session mode and max duration are **global UI settings**, not per-pump
/// values.  They are stored in per-[PumpSelection] maps only because
/// [_syncDisplayVariables] swaps the active selection.  Writing just the
/// current selection used to leave left/right at factory defaults, so a
/// Both → individual-mode switch restored `defaultMode` / 20 min.
class ControlSessionSettingsSyncLogic {
  const ControlSessionSettingsSyncLogic._();

  static const int defaultMaxDuration = 20;

  /// Writes [value] to left, right, and both so a later selection swap
  /// cannot restore a stale default.
  static Map<PumpSelection, T> snapshotToAll<T>(T value) {
    return {
      PumpSelection.left: value,
      PumpSelection.right: value,
      PumpSelection.both: value,
    };
  }

  /// Reads the stored value for [target], falling back to [fallback]
  /// when the key is missing (defensive; maps are always fully populated).
  static T restore<T>(
    Map<PumpSelection, T> map,
    PumpSelection target,
    T fallback,
  ) {
    return map[target] ?? fallback;
  }

  /// Models [_syncDisplayVariables]: persist the in-memory UI settings to
  /// every selection, then restore the target selection.
  static ({SessionMode sessionMode, int maxDuration}) syncThenRestore({
    required SessionMode currentSessionMode,
    required int currentMaxDuration,
    required PumpSelection target,
  }) {
    final modes = snapshotToAll(currentSessionMode);
    final durations = snapshotToAll(currentMaxDuration);
    return (
      sessionMode: restore(modes, target, SessionMode.defaultMode),
      maxDuration: restore(durations, target, defaultMaxDuration),
    );
  }
}
