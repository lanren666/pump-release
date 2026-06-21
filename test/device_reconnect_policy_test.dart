import 'package:flutter_test/flutter_test.dart';
import 'package:pump/services/tuya/device_reconnect_policy.dart';

void main() {
  group('DeviceReconnectPolicy', () {
    test('stale running when DB says running but device is offline', () {
      expect(
        DeviceReconnectPolicy.isStaleRunningState(
          isRunning: true,
          isOnline: false,
        ),
        isTrue,
      );
    });

    test('not stale when running and online', () {
      expect(
        DeviceReconnectPolicy.isStaleRunningState(
          isRunning: true,
          isOnline: true,
        ),
        isFalse,
      );
    });

    test('not stale when already marked not running', () {
      expect(
        DeviceReconnectPolicy.isStaleRunningState(
          isRunning: false,
          isOnline: false,
        ),
        isFalse,
      );
    });

    test('register listener only when running and online', () {
      expect(
        DeviceReconnectPolicy.shouldRegisterListenerOnly(
          isRunning: true,
          isOnline: true,
        ),
        isTrue,
      );
    });

    test('do not register-only when offline or not running', () {
      expect(
        DeviceReconnectPolicy.shouldRegisterListenerOnly(
          isRunning: true,
          isOnline: false,
        ),
        isFalse,
      );
      expect(
        DeviceReconnectPolicy.shouldRegisterListenerOnly(
          isRunning: false,
          isOnline: true,
        ),
        isFalse,
      );
    });
  });

  group('OfflineStreakTracker', () {
    setUp(OfflineStreakTracker.clearAll);

    test('requires two consecutive offline probes (~6s at 3s poll)', () {
      const id = 'ble-1';
      OfflineStreakTracker.completeColdStartPass();
      expect(OfflineStreakTracker.confirmThreshold, 2);
      expect(OfflineStreakTracker.recordOffline(id), 1);
      expect(OfflineStreakTracker.isConfirmedOffline(id), isFalse);
      expect(OfflineStreakTracker.recordOffline(id), 2);
      expect(OfflineStreakTracker.isConfirmedOffline(id), isTrue);
    });

    test('reset clears streak after device comes back online', () {
      const id = 'ble-2';
      OfflineStreakTracker.recordOffline(id);
      OfflineStreakTracker.reset(id);
      expect(OfflineStreakTracker.isConfirmedOffline(id), isFalse);
      expect(OfflineStreakTracker.recordOffline(id), 1);
    });

    test('streak restarts after intermittent offline-online-offline', () {
      const id = 'ble-3';
      OfflineStreakTracker.completeColdStartPass();
      OfflineStreakTracker.recordOffline(id);
      OfflineStreakTracker.reset(id);
      expect(OfflineStreakTracker.recordOffline(id), 1);
      expect(OfflineStreakTracker.isConfirmedOffline(id), isFalse);
    });
  });

  group('NetworkStatusRunningPolicy', () {
    setUp(OfflineStreakTracker.clearAll);

    test('online resets streak and offline does not apply when not running', () {
      const id = 'ble-net-1';
      OfflineStreakTracker.recordOffline(id);
      NetworkStatusRunningPolicy.onOnline(id);
      expect(OfflineStreakTracker.currentStreak(id), 0);
      expect(
        NetworkStatusRunningPolicy.shouldApplyRunningFalse(
          dbIsRunning: false,
          bluetoothId: id,
        ),
        isFalse,
      );
    });

    test('single offline network event does not apply running false', () {
      const id = 'ble-net-2';
      OfflineStreakTracker.completeColdStartPass();
      expect(
        NetworkStatusRunningPolicy.shouldApplyRunningFalse(
          dbIsRunning: true,
          bluetoothId: id,
        ),
        isFalse,
      );
      expect(OfflineStreakTracker.currentStreak(id), 1);
    });

    test('second offline signal confirms running false', () {
      const id = 'ble-net-3';
      OfflineStreakTracker.completeColdStartPass();
      NetworkStatusRunningPolicy.shouldApplyRunningFalse(
        dbIsRunning: true,
        bluetoothId: id,
      );
      expect(
        NetworkStatusRunningPolicy.shouldApplyRunningFalse(
          dbIsRunning: true,
          bluetoothId: id,
        ),
        isTrue,
      );
      expect(OfflineStreakTracker.currentStreak(id), 0);
    });

    test('online between offline signals restarts streak', () {
      const id = 'ble-net-4';
      OfflineStreakTracker.completeColdStartPass();
      NetworkStatusRunningPolicy.shouldApplyRunningFalse(
        dbIsRunning: true,
        bluetoothId: id,
      );
      NetworkStatusRunningPolicy.onOnline(id);
      expect(
        NetworkStatusRunningPolicy.shouldApplyRunningFalse(
          dbIsRunning: true,
          bluetoothId: id,
        ),
        isFalse,
      );
    });

    test('poll and network callbacks share the same streak counter', () {
      const id = 'ble-net-5';
      OfflineStreakTracker.completeColdStartPass();
      OfflineStreakTracker.recordOffline(id);
      expect(
        NetworkStatusRunningPolicy.shouldApplyRunningFalse(
          dbIsRunning: true,
          bluetoothId: id,
        ),
        isTrue,
      );
    });
  });

  group('DpAliveTracker', () {
    setUp(DpAliveTracker.clearAll);

    test('recent DP105 suppresses running false downgrade', () {
      const devId = 'dev-1';
      DpAliveTracker.touch(devId);
      expect(
        DeviceReconnectPolicy.shouldSuppressRunningFalse(
          devId: devId,
          isOnline: false,
        ),
        isTrue,
      );
      expect(
        DeviceReconnectPolicy.shouldHealRunningFromDp(devId: devId),
        isTrue,
      );
    });

    test('suppress does not apply when native probe says online', () {
      const devId = 'dev-2';
      DpAliveTracker.touch(devId);
      expect(
        DeviceReconnectPolicy.shouldSuppressRunningFalse(
          devId: devId,
          isOnline: true,
        ),
        isFalse,
      );
    });

    test('touch marks devId as recently alive', () {
      const devId = 'dev-3';
      expect(DpAliveTracker.isRecentlyAlive(devId), isFalse);
      DpAliveTracker.touch(devId);
      expect(DpAliveTracker.isRecentlyAlive(devId), isTrue);
      expect(
        DeviceReconnectPolicy.shouldHealRunningFromDp(devId: devId),
        isTrue,
      );
    });

    test('unknown devId is not recently alive', () {
      expect(DpAliveTracker.isRecentlyAlive(''), isFalse);
      expect(
        DeviceReconnectPolicy.shouldHealRunningFromDp(devId: 'missing'),
        isFalse,
      );
    });

    test('expires after alive window', () {
      const devId = 'dev-expired';
      DpAliveTracker.setLastAtForTest(
        devId,
        DateTime.now().subtract(const Duration(seconds: 13)),
      );
      expect(DpAliveTracker.isRecentlyAlive(devId), isFalse);
      expect(
        DeviceReconnectPolicy.shouldSuppressRunningFalse(
          devId: devId,
          isOnline: false,
        ),
        isFalse,
      );
    });
  });

  group('DpAliveTracker with NetworkStatusRunningPolicy', () {
    setUp(() {
      OfflineStreakTracker.clearAll();
      DpAliveTracker.clearAll();
    });

    test('network confirms offline but DP alive should not downgrade', () {
      const devId = 'dev-net-dp';
      const bleId = 'ble-net-dp';
      DpAliveTracker.touch(devId);

      expect(
        NetworkStatusRunningPolicy.shouldApplyRunningFalse(
          dbIsRunning: true,
          bluetoothId: bleId,
        ),
        isFalse,
      );
      expect(
        NetworkStatusRunningPolicy.shouldApplyRunningFalse(
          dbIsRunning: true,
          bluetoothId: bleId,
        ),
        isTrue,
      );
      expect(
        DeviceReconnectPolicy.shouldSuppressRunningFalse(
          devId: devId,
          isOnline: false,
        ),
        isTrue,
      );
    });
  });
}
