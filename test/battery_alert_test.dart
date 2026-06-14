import 'package:flutter_test/flutter_test.dart';
import 'package:pump/config/app_config.dart';
import 'package:pump/services/battery/battery_alert_logic.dart';
import 'package:pump/services/tuya/session_setting_parser.dart';

void main() {
  group('SessionSettingParser.parseBatVolt', () {
    test('reads last two bytes as big-endian', () {
      // payload ... + 0x0078 (120)
      expect(SessionSettingParser.parseBatVolt('0102030078'), 120);
      expect(SessionSettingParser.parseBatVolt('0078'), 120);
    });

    test('clamps to batVoltMax', () {
      expect(SessionSettingParser.parseBatVolt('000500'), AppConfig.batVoltMax);
    });

    test('returns null for short payload', () {
      expect(SessionSettingParser.parseBatVolt('0'), isNull);
      expect(SessionSettingParser.parseBatVolt(null), isNull);
    });
  });

  group('BatteryAlertLogic', () {
    test('session end excludes pause transition', () {
      expect(
        BatteryAlertLogic.isSessionEndedTransition(
          wasRunning: true,
          newIsRunning: 0,
          hadStarted: true,
          expectedIsRunning: 2,
        ),
        isFalse,
      );
    });

    test('session end on stop or natural completion', () {
      expect(
        BatteryAlertLogic.isSessionEndedTransition(
          wasRunning: true,
          newIsRunning: 0,
          hadStarted: true,
          expectedIsRunning: 0,
        ),
        isTrue,
      );
      expect(
        BatteryAlertLogic.isSessionEndedTransition(
          wasRunning: true,
          newIsRunning: 0,
          hadStarted: true,
          expectedIsRunning: null,
        ),
        isTrue,
      );
    });

    test('bat volt threshold', () {
      expect(
        BatteryAlertLogic.isBatVoltInsufficientForFullSession(
          AppConfig.batVoltLowSessionThreshold - 1,
        ),
        isTrue,
      );
      expect(
        BatteryAlertLogic.isBatVoltInsufficientForFullSession(
          AppConfig.batVoltLowSessionThreshold,
        ),
        isFalse,
      );
    });

    test('low battery transition when host red LED starts blinking', () {
      expect(
        BatteryAlertLogic.isLowBatteryTransition(
          previousBattery: 2,
          newBattery: 1,
        ),
        isTrue,
      );
      expect(
        BatteryAlertLogic.isLowBatteryTransition(
          previousBattery: 1,
          newBattery: 1,
        ),
        isFalse,
      );
      expect(
        BatteryAlertLogic.isLowBatteryTransition(
          previousBattery: 3,
          newBattery: 2,
        ),
        isFalse,
      );
    });
  });
}
