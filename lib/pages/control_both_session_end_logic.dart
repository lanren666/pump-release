/// Pure helpers for deciding whether a stopped device in Both mode
/// should be restarted ("kicked") or treated as a natural session end.
///
/// The firmware reports DP105 isRunning=0 for two distinct situations:
///   1. Natural end — the device ran to its configured maxTime.
///   2. Unexpected stop — BLE drop, firmware crash, or mid-session power loss.
///
/// Only situation 2 warrants a kick (pushSessionSetting + startN). Kicking on
/// situation 1 would restart a device that just legitimately finished its session.
class ControlBothSessionEndLogic {
  ControlBothSessionEndLogic._();

  /// Seconds before maxTime within which an isRunning=0 report is treated as
  /// a natural session end.  60 s is generous: the two devices start ~800 ms
  /// apart and firmware reporting latency is well under a second.
  static const int defaultNaturalEndToleranceSeconds = 60;

  /// Returns true if [timePast] seconds indicates the device reached (or nearly
  /// reached) its configured [maxTimeMinutes] limit.
  ///
  /// Rationale: firmware may report slightly less than the exact limit due to
  /// polling granularity, so we allow a [toleranceSeconds] window.
  ///
  /// Returns false when [maxTimeMinutes] is 0 (unknown / invalid), so callers
  /// default to the safe "kick" path rather than silently suppressing recovery.
  static bool completedNaturally({
    required int timePast,
    required int maxTimeMinutes,
    int toleranceSeconds = defaultNaturalEndToleranceSeconds,
  }) {
    if (maxTimeMinutes <= 0) return false;
    final maxTimeSeconds = maxTimeMinutes * 60;
    return timePast >= maxTimeSeconds - toleranceSeconds;
  }

  /// Returns true if the stopped device should be kicked (restarted):
  /// the other side is still running AND this stop appears to be mid-session.
  ///
  /// Returns false when:
  /// - [otherSideRunning] is false — nothing to synchronise against.
  /// - the device completed naturally — kicking would restart a finished session.
  static bool shouldKickOnBothStop({
    required bool otherSideRunning,
    required int timePast,
    required int maxTimeMinutes,
    int toleranceSeconds = defaultNaturalEndToleranceSeconds,
  }) {
    if (!otherSideRunning) return false;
    return !completedNaturally(
      timePast: timePast,
      maxTimeMinutes: maxTimeMinutes,
      toleranceSeconds: toleranceSeconds,
    );
  }
}
