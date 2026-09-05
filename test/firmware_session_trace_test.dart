import 'package:flutter_test/flutter_test.dart';
import 'package:pump/services/tuya/firmware_session_trace.dart';

void main() {
  setUp(FirmwareSessionTrace.clear);

  FirmwareDp105Snapshot snap({
    int isRunning = 1,
    int timePast = 100,
    int timePastInPhase = 40,
    int sessionPhase = 2,
    String sessionModeName = 'expression',
    int totalTimeInPhase = 3,
    int maxTime = 15,
    bool isCustom = true,
  }) {
    return FirmwareDp105Snapshot(
      isRunning: isRunning,
      timePast: timePast,
      timePastInPhase: timePastInPhase,
      sessionPhase: sessionPhase,
      sessionModeName: sessionModeName,
      totalTimeInPhase: totalTimeInPhase,
      maxTime: maxTime,
      isCustom: isCustom,
    );
  }

  group('FirmwareSessionTrace.shouldLogDp105Info', () {
    test('first report is always logged', () {
      expect(
        FirmwareSessionTrace.shouldLogDp105Info(
          deviceId: 'dev-r',
          gapSec: null,
          snapshot: snap(),
        ),
        isTrue,
      );
    });

    test('routine 1s tick with the same session fields is not logged', () {
      FirmwareSessionTrace.remember('dev-r', snap());
      expect(
        FirmwareSessionTrace.shouldLogDp105Info(
          deviceId: 'dev-r',
          gapSec: 1,
          snapshot: snap(timePast: 101),
        ),
        isFalse,
      );
    });

    test('gap after BLE drop is logged', () {
      FirmwareSessionTrace.remember('dev-r', snap());
      expect(
        FirmwareSessionTrace.shouldLogDp105Info(
          deviceId: 'dev-r',
          gapSec: 40,
          snapshot: snap(timePast: 549),
        ),
        isTrue,
      );
    });

    test('maxTime / custom / phase length change is logged', () {
      FirmwareSessionTrace.remember('dev-r', snap());
      expect(
        FirmwareSessionTrace.shouldLogDp105Info(
          deviceId: 'dev-r',
          gapSec: 1,
          snapshot: snap(maxTime: 20, isCustom: false, totalTimeInPhase: 5),
        ),
        isTrue,
      );
    });

    test('empty deviceId is not logged', () {
      expect(
        FirmwareSessionTrace.shouldLogDp105Info(
          deviceId: '',
          gapSec: null,
          snapshot: snap(),
        ),
        isFalse,
      );
    });
  });

  group('FirmwareDp105Snapshot', () {
    test('fromParsed maps DP105 fields', () {
      final parsed = FirmwareDp105Snapshot.fromParsed({
        'isRunning': 1,
        'timePast': 549,
        'timePastInPhase': 9,
        'sessionPhase': 2,
        'sessionModeName': 'expression',
        'totalTimeInPhase': 5,
        'maxTime': 20,
        'isCustom': false,
      });
      expect(parsed.timePast, 549);
      expect(parsed.looksLikeDefaultFlow, isTrue);
    });

    test('custom 2→3 / max 15 is not the default flow', () {
      expect(snap().looksLikeDefaultFlow, isFalse);
    });
  });

  group('FirmwareSessionTrace formatters', () {
    test('DP105 line includes gap and default-flow hint', () {
      final line = FirmwareSessionTrace.formatDp105(
        deviceId: 'abcdef1234567890',
        position: 'right',
        snapshot: snap(
          timePast: 549,
          maxTime: 20,
          isCustom: false,
          totalTimeInPhase: 5,
        ),
        gapSec: 40,
      );
      expect(line, contains('DP105 side=R'));
      expect(line, contains('t=549s'));
      expect(line, contains('maxMin=20'));
      expect(line, contains('custom=false'));
      expect(line, contains('gap=40s'));
      expect(line, contains('hint=default_2plus5'));
    });

    test('hybrid lines distinguish DP107 and DP109', () {
      expect(
        FirmwareSessionTrace.formatHybrid(
          dpId: '107',
          deviceId: 'dev-r',
          position: 'right',
          value: false,
        ),
        'DP107 hybrid_stim side=R id=dev-r on=false',
      );
      expect(
        FirmwareSessionTrace.formatHybrid(
          dpId: '109',
          deviceId: 'dev-l',
          position: 'left',
          value: true,
        ),
        'DP109 hybrid_expr side=L id=dev-l on=true',
      );
    });

    test('maxTime split warning only when both sides reported different values', () {
      expect(
        FirmwareSessionTrace.maxTimeSplitWarning(leftMax: 15, rightMax: 20),
        'maxTime split L=15min R=20min',
      );
      expect(
        FirmwareSessionTrace.maxTimeSplitWarning(leftMax: 15, rightMax: 15),
        isNull,
      );
      expect(
        FirmwareSessionTrace.maxTimeSplitWarning(leftMax: 15, rightMax: null),
        isNull,
      );
    });
  });
}
