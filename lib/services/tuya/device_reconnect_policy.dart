/// Tracks recent DP105 (session status) reports as proof the BLE data path is alive.
///
/// Used when native `isDeviceOnline` false-negatives while the DP listener still
/// receives packets — see [DeviceReconnectPolicy.shouldSuppressRunningFalse].
class DpAliveTracker {
  DpAliveTracker._();

  /// Slightly longer than the 3s periodic poll × 2 offline streak.
  static const Duration aliveWindow = Duration(seconds: 12);

  static final Map<String, DateTime> _lastAtByDevId = {};

  static void touch(String devId) {
    if (devId.isEmpty) return;
    _lastAtByDevId[devId] = DateTime.now();
  }

  static bool isRecentlyAlive(String devId) {
    if (devId.isEmpty) return false;
    final lastAt = _lastAtByDevId[devId];
    if (lastAt == null) return false;
    return DateTime.now().difference(lastAt) <= aliveWindow;
  }

  /// Visible for tests only.
  static void setLastAtForTest(String devId, DateTime at) {
    if (devId.isEmpty) return;
    _lastAtByDevId[devId] = at;
  }

  /// Visible for tests only.
  static void clearAll() => _lastAtByDevId.clear();
}

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

  /// Native probe says offline but DP105 still flowing — do not write isRunning=false.
  static bool shouldSuppressRunningFalse({
    required String devId,
    required bool isOnline,
  }) =>
      !isOnline && DpAliveTracker.isRecentlyAlive(devId);

  /// DB says disconnected but DP105 proves the device is reachable.
  static bool shouldHealRunningFromDp({required String devId}) =>
      DpAliveTracker.isRecentlyAlive(devId);
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

  static int currentStreak(String bluetoothId) {
    if (bluetoothId.isEmpty) return 0;
    return _streakByBluetoothId[bluetoothId] ?? 0;
  }

  /// Visible for tests only.
  static void clearAll() => _streakByBluetoothId.clear();
}

/// Debounces `isRunning=false` from native network/BLE callbacks (e.g. Android
/// `onNetworkStatusChanged`) using the same [OfflineStreakTracker] as the poll
/// in [PumpApp].
class NetworkStatusRunningPolicy {
  const NetworkStatusRunningPolicy._();

  static void onOnline(String bluetoothId) {
    OfflineStreakTracker.reset(bluetoothId);
  }

  /// Returns whether DB `isRunning` should be set to false for this offline
  /// signal. Online signals should call [onOnline] and apply `true` immediately.
  static bool shouldApplyRunningFalse({
    required bool dbIsRunning,
    required String bluetoothId,
  }) {
    if (!dbIsRunning) {
      OfflineStreakTracker.reset(bluetoothId);
      return false;
    }

    OfflineStreakTracker.recordOffline(bluetoothId);
    if (!OfflineStreakTracker.isConfirmedOffline(bluetoothId)) {
      return false;
    }

    OfflineStreakTracker.reset(bluetoothId);
    return true;
  }
}
