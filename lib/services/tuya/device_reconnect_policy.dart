/// Periodic reconnect decisions for remembered devices.
class DeviceReconnectPolicy {
  const DeviceReconnectPolicy._();

  /// DB says running but live BLE probe is offline — stale state after power-off.
  static bool isStaleRunningState({
    required bool isRunning,
    required bool isOnline,
  }) =>
      isRunning && !isOnline;

  /// Device is connected; only (re)register the native DP listener.
  static bool shouldRegisterListenerOnly({
    required bool isRunning,
    required bool isOnline,
  }) =>
      isRunning && isOnline;
}

/// Debounces [isRunning=false] when periodic probes flicker offline briefly.
///
/// Paired with the 3s reconnect poll in [PumpApp]: [confirmThreshold] of 2
/// means ~6s sustained offline before DB is corrected.
class OfflineStreakTracker {
  OfflineStreakTracker._();

  /// Consecutive offline probes required before treating device as offline.
  static const int confirmThreshold = 2;

  static final Map<String, int> _streakByBluetoothId = {};

  /// Records one offline probe; returns the new streak count.
  static int recordOffline(String bluetoothId) {
    if (bluetoothId.isEmpty) return 0;
    final next = (_streakByBluetoothId[bluetoothId] ?? 0) + 1;
    _streakByBluetoothId[bluetoothId] = next;
    return next;
  }

  static void reset(String bluetoothId) {
    if (bluetoothId.isEmpty) return;
    _streakByBluetoothId.remove(bluetoothId);
  }

  static bool isConfirmedOffline(String bluetoothId) {
    if (bluetoothId.isEmpty) return false;
    return (_streakByBluetoothId[bluetoothId] ?? 0) >= confirmThreshold;
  }

  /// Visible for tests only.
  static void clearAll() => _streakByBluetoothId.clear();
}
