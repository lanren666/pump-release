import 'package:flutter/foundation.dart';

import '../../config/ble_channels.dart';

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

  /// Seconds since the last DP105 touch, or null if this device never reported.
  static int? secondsSinceLast(String devId) {
    if (devId.isEmpty) return null;
    final lastAt = _lastAtByDevId[devId];
    if (lastAt == null) return null;
    return DateTime.now().difference(lastAt).inSeconds;
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
  static bool shouldHealRunningFromDp({required String devId}) {
    if (DebugForcedOffline.isHeld(devId: devId)) return false;
    return DpAliveTracker.isRecentlyAlive(devId);
  }

  /// True when we must wait for the deviceActivated callback to write the devId —
  /// i.e. the device has no devId in the DB yet (first-time pairing).
  /// False means it's already paired; DB has the devId and no delay is needed.
  static bool needsActivationDelay({required String? dbDevId}) =>
      (dbDevId ?? '').isEmpty;
}

/// Debounces [isRunning=false] when periodic probes flicker offline briefly.
///
/// Paired with the 3s reconnect poll in [PumpApp]: [confirmThreshold] of 2
/// means ~6s sustained offline before DB is corrected.
class OfflineStreakTracker {
  OfflineStreakTracker._();

  /// Consecutive offline probes required before treating device as offline.
  static const int confirmThreshold = 2;

  /// First app launch pass queues reconnect without waiting for offline debounce.
  /// It does not write `isRunning=false` from a single probe.
  static bool coldStartPassActive = true;

  /// Drives UI rebuild when cold-start BLE verification finishes.
  static final ValueNotifier<bool> coldStartInProgress = ValueNotifier(true);

  static void completeColdStartPass() {
    coldStartPassActive = false;
    if (coldStartInProgress.value) {
      coldStartInProgress.value = false;
    }
  }

  static bool shouldConfirmOfflineImmediately() => coldStartPassActive;

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
    if (coldStartPassActive) return true;
    return (_streakByBluetoothId[bluetoothId] ?? 0) >= confirmThreshold;
  }

  static int currentStreak(String bluetoothId) {
    if (bluetoothId.isEmpty) return 0;
    return _streakByBluetoothId[bluetoothId] ?? 0;
  }

  static void clearAll() {
    _streakByBluetoothId.clear();
    coldStartPassActive = false;
    coldStartInProgress.value = false;
  }
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

/// Debug-only hold armed solely by the control-page "断开" button.
///
/// Release builds never arm this ([kDebugMode] is false and the button is
/// hidden), so production reconnect / offline debounce is unchanged.
class DebugForcedOffline {
  DebugForcedOffline._();

  static const Duration _redropCooldown = Duration(seconds: 2);

  static final Set<String> _heldBluetoothIds = {};
  static final Set<String> _heldDevIds = {};
  static final Map<String, DateTime> _lastRedropAtByBluetoothId = {};

  static bool get isSupported => kDebugMode;

  static void hold({required String bluetoothId, String? devId}) {
    if (!isSupported) return;
    if (bluetoothId.isNotEmpty) _heldBluetoothIds.add(bluetoothId);
    if (devId != null && devId.isNotEmpty) _heldDevIds.add(devId);
  }

  static void release({String? bluetoothId, String? devId}) {
    if (bluetoothId != null && bluetoothId.isNotEmpty) {
      _heldBluetoothIds.remove(bluetoothId);
      _lastRedropAtByBluetoothId.remove(bluetoothId);
    }
    if (devId != null && devId.isNotEmpty) {
      _heldDevIds.remove(devId);
    }
  }

  static bool isHeld({String? bluetoothId, String? devId}) {
    if (!isSupported) return false;
    if (bluetoothId != null &&
        bluetoothId.isNotEmpty &&
        _heldBluetoothIds.contains(bluetoothId)) {
      return true;
    }
    if (devId != null &&
        devId.isNotEmpty &&
        _heldDevIds.contains(devId)) {
      return true;
    }
    return false;
  }

  /// True when auto online / periodic reconnect must leave this device offline.
  static bool shouldBlockAutoOnline({String? bluetoothId, String? devId}) =>
      isHeld(bluetoothId: bluetoothId, devId: devId);

  static Future<void> redropNativeIfHeld({
    required String bluetoothId,
    required String nativeBleId,
    String? devId,
  }) async {
    if (!isHeld(bluetoothId: bluetoothId, devId: devId)) return;
    if (bluetoothId.isEmpty) return;

    final now = DateTime.now();
    final lastAt = _lastRedropAtByBluetoothId[bluetoothId];
    if (lastAt != null && now.difference(lastAt) < _redropCooldown) {
      return;
    }
    _lastRedropAtByBluetoothId[bluetoothId] = now;

    try {
      await connectionChannel.invokeMethod('disconnectBleDevice', {
        'deviceId': nativeBleId,
        'uuid': bluetoothId,
      });
      debugPrint(
        '[INFO][FW_SNAP] debug forced offline re-drop '
        'bluetoothId=$bluetoothId nativeBleId=$nativeBleId',
      );
    } catch (e) {
      debugPrint(
        '[INFO][FW_SNAP] debug forced offline re-drop failed '
        'bluetoothId=$bluetoothId error=$e',
      );
    }
  }

  static void clearAll() {
    _heldBluetoothIds.clear();
    _heldDevIds.clear();
    _lastRedropAtByBluetoothId.clear();
  }
}
