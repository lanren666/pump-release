import 'package:flutter_test/flutter_test.dart';
import 'package:pump/services/tuya/native_connect_result_logic.dart';

void main() {
  group('NativeConnectResultLogic.parse — normal', () {
    test('legacy bool true is an immediate online connect', () {
      final parsed = NativeConnectResultLogic.parse(true);
      expect(parsed.success, isTrue);
      expect(parsed.pending, isFalse);
      expect(parsed.devId, isNull);
      expect(parsed.shouldRemember, isTrue);
      expect(parsed.shouldMarkRunning, isTrue);
      expect(parsed.shouldAnnounceConnected, isTrue);
      expect(parsed.shouldPublishDeviceSymbol, isTrue);
      expect(parsed.shouldRegisterListener, isTrue);
      expect(parsed.shouldCheckLowBattery, isTrue);
    });

    test('iOS-style map success with devId', () {
      final parsed = NativeConnectResultLogic.parse({
        'success': true,
        'devId': 'eb25b2sd0pnt2tcx',
      });
      expect(parsed.success, isTrue);
      expect(parsed.pending, isFalse);
      expect(parsed.devId, 'eb25b2sd0pnt2tcx');
      expect(parsed.canRememberWithDevId(parsed.devId), isTrue);
    });

    test('Android pending keeps the device remembered but not running', () {
      final parsed = NativeConnectResultLogic.parse({
        'success': false,
        'pending': true,
        'devId': 'ebcbe7qwvnnnau1o',
      });
      expect(parsed.shouldRemember, isTrue);
      expect(parsed.shouldMarkRunning, isFalse);
      expect(parsed.shouldAnnounceConnected, isFalse);
      expect(parsed.shouldPublishDeviceSymbol, isFalse);
      expect(parsed.shouldRegisterListener, isFalse);
      expect(parsed.shouldCheckLowBattery, isFalse);
      expect(parsed.canRememberWithDevId(parsed.devId), isTrue);
    });
  });

  group('NativeConnectResultLogic.parse — exception', () {
    test('legacy bool false is a hard failure', () {
      final parsed = NativeConnectResultLogic.parse(false);
      expect(parsed.shouldRemember, isFalse);
      expect(parsed.canRememberWithDevId(null), isFalse);
    });

    test('pending without a Tuya devId must not be remembered', () {
      final parsed = NativeConnectResultLogic.parse({
        'success': false,
        'pending': true,
        'devId': '',
      });
      expect(parsed.pending, isTrue);
      expect(parsed.devId, isNull);
      expect(parsed.canRememberWithDevId(null), isFalse);
      expect(parsed.canRememberWithDevId(''), isFalse);
    });

    test('unknown payload is a hard failure', () {
      final parsed = NativeConnectResultLogic.parse('oops');
      expect(parsed.success, isFalse);
      expect(parsed.pending, isFalse);
      expect(parsed.shouldRemember, isFalse);
    });

    test('success flag that is not a bool is not treated as online', () {
      final parsed = NativeConnectResultLogic.parse({
        'success': 1,
        'pending': 'true',
        'devId': 'eb25b2sd0pnt2tcx',
      });
      expect(parsed.success, isFalse);
      expect(parsed.pending, isFalse);
    });
  });

  group('productKeyFromScan', () {
    test('prefers official productId over providerName', () {
      expect(
        NativeConnectResultLogic.productKeyFromScan(
          productId: 'key-from-productId',
          providerName: 'SingleBleProvider',
        ),
        'key-from-productId',
      );
    });

    test('falls back to providerName when productId is empty', () {
      expect(
        NativeConnectResultLogic.productKeyFromScan(
          productId: '',
          providerName: 'legacy-key',
        ),
        'legacy-key',
      );
    });
  });

  group('native error prompts', () {
    test('offline unbind / missing devId asks user to re-pair', () {
      expect(
        NativeConnectResultLogic.shouldPromptRePair('DEVICE_NOT_IN_HOME'),
        isTrue,
      );
      expect(
        NativeConnectResultLogic.shouldPromptRePair('MISSING_DEV_ID'),
        isTrue,
      );
      expect(
        NativeConnectResultLogic.shouldPromptRePair('ACTIVATION_FAILED'),
        isFalse,
      );
    });

    test('missing Tuya home is a retry, not a re-pair', () {
      expect(
        NativeConnectResultLogic.shouldPromptHomeRetry('HOME_NOT_FOUND'),
        isTrue,
      );
      expect(
        NativeConnectResultLogic.shouldPromptHomeRetry('DEVICE_NOT_IN_HOME'),
        isFalse,
      );
    });
  });
}
