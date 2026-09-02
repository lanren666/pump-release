import 'control_both_session_end_logic.dart';

/// Pure helpers for the DB-refresh kick decision in _refreshDeviceStatus.
///
/// The DB-refresh path (~4 s poll) detects mid-session device drops by
/// watching the connected_devices table.  Unlike the DP-105 path, which
/// receives timePast and maxTime directly from firmware, this path must
/// reconstruct them from widget state:
///
///   - elapsedSeconds   = _leftElapsedTime.inSeconds (last DP-105 value)
///   - deviceMaxDuration / uiMaxDuration = per-side firmware maxTime ?? _maxDuration
///
/// Extracted so the decision can be unit-tested independently of the widget.
class ControlDbRefreshKickLogic {
  const ControlDbRefreshKickLogic._();

  /// Resolves the elapsed seconds to pass to [shouldKickOnDbOffline] when
  /// the widget's elapsed-time counter has not yet advanced (e.g., immediately
  /// after navigation-resume before the first DP-105 arrives).
  ///
  /// Mirrors [ControlBothSessionEndLogic.effectiveTimePast] but for the
  /// DB-refresh path: [elapsedSeconds] comes from `_leftElapsedTime.inSeconds`
  /// and [lastRunningTimePast] from `_leftLastRunningTimePast`.
  static int effectiveElapsedSeconds({
    required int elapsedSeconds,
    required int lastRunningTimePast,
  }) {
    return elapsedSeconds > 0 ? elapsedSeconds : lastRunningTimePast;
  }

  /// Returns the effective max session duration (minutes) to use for
  /// natural-end detection in the DB-refresh path.
  ///
  /// [deviceMaxDuration] comes from DP-105 maxTime and is authoritative when
  /// available.  Falls back to the UI value [uiMaxDuration] when DP-105 has
  /// not yet arrived or has already been cleared after a session ends.
  static int effectiveMaxMinutes({
    required int? deviceMaxDuration,
    required int uiMaxDuration,
  }) {
    return deviceMaxDuration ?? uiMaxDuration;
  }

  /// Returns true when a DB-offline event should trigger a kick (restart),
  /// false when it should be treated as a natural session end and cleaned up
  /// without restarting.
  ///
  /// Delegates to [ControlBothSessionEndLogic.completedNaturally] so both the
  /// DP-105 path and the DB-refresh path share the same tolerance window and
  /// threshold logic.
  static bool shouldKickOnDbOffline({
    required int elapsedSeconds,
    required int? deviceMaxDuration,
    required int uiMaxDuration,
  }) {
    final maxMins = effectiveMaxMinutes(
      deviceMaxDuration: deviceMaxDuration,
      uiMaxDuration: uiMaxDuration,
    );
    return !ControlBothSessionEndLogic.completedNaturally(
      timePast: elapsedSeconds,
      maxTimeMinutes: maxMins,
    );
  }
}
