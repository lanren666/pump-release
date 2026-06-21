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
}
