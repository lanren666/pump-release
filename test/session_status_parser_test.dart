import 'package:flutter_test/flutter_test.dart';
import 'package:pump/services/tuya/dp_change_handle.dart';

void main() {
  group('parseSessionStatus', () {
    test('parses 26-hex payload with trailing Bat_Volt', () {
      const hex = '00020002000102010101020170';
      final status = DpChangeHandle.parseSessionStatus(hex);

      expect(status['timePast'], 2);
      expect(status['timePastInPhase'], 2);
      expect(status['sessionPhase'], 1);
      expect(status['sessionModeName'], 'stimulation');
      expect(status['totalPhase'], 2);
      expect(status['maxTime'], 20);
      expect(status['isCustom'], isTrue);
      expect(status['isRunning'], 1);
      expect(status['totalTimeInPhase'], 2);
      expect(status['batVolt'], 0x170);
    });

    test('still parses legacy 22-hex payload without Bat_Volt', () {
      const hex = '0019001900010201010102';
      final status = DpChangeHandle.parseSessionStatus(hex);

      expect(status['timePast'], 25);
      expect(status['timePastInPhase'], 25);
      expect(status['isRunning'], 1);
      expect(status.containsKey('batVolt'), isFalse);
    });

    test('rejects unexpected length', () {
      expect(
        () => DpChangeHandle.parseSessionStatus('001122'),
        throwsFormatException,
      );
    });
  });
}
