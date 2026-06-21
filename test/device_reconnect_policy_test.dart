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
      OfflineStreakTracker.recordOffline(id);
      OfflineStreakTracker.reset(id);
      expect(OfflineStreakTracker.recordOffline(id), 1);
      expect(OfflineStreakTracker.isConfirmedOffline(id), isFalse);
    });
  });
}
