import 'package:flutter_test/flutter_test.dart';
import 'package:pump/pages/control_db_refresh_kick_logic.dart';
import 'package:pump/pages/control_device_max_duration_logic.dart';
import 'package:pump/pages/control_types.dart';

void main() {
  group('applyReportedMaxTime', () {
    test('left report updates only left', () {
      final next = ControlDeviceMaxDurationLogic.applyReportedMaxTime(
        isLeftDevice: true,
        maxTime: 15,
        left: null,
        right: 20,
      );
      expect(next.left, 15);
      expect(next.right, 20);
    });

    test('right report updates only right', () {
      final next = ControlDeviceMaxDurationLogic.applyReportedMaxTime(
        isLeftDevice: false,
        maxTime: 20,
        left: 15,
        right: null,
      );
      expect(next.left, 15);
      expect(next.right, 20);
    });

    test('later report from the other side does not clobber the first', () {
      var state = ControlDeviceMaxDurationLogic.applyReportedMaxTime(
        isLeftDevice: true,
        maxTime: 15,
        left: null,
        right: null,
      );
      state = ControlDeviceMaxDurationLogic.applyReportedMaxTime(
        isLeftDevice: false,
        maxTime: 20,
        left: state.left,
        right: state.right,
      );
      expect(state.left, 15);
      expect(state.right, 20);
    });

    test('same side can update its own value (15 → 20)', () {
      final next = ControlDeviceMaxDurationLogic.applyReportedMaxTime(
        isLeftDevice: true,
        maxTime: 20,
        left: 15,
        right: 15,
      );
      expect(next.left, 20);
      expect(next.right, 15);
    });
  });

  group('clearOnStop', () {
    test('other side still running → keep both last reports', () {
      final next = ControlDeviceMaxDurationLogic.clearOnStop(
        isLeftDevice: true,
        otherSideRunning: true,
        left: 15,
        right: 20,
      );
      expect(next.left, 15);
      expect(next.right, 20);
    });

    test('other side idle → both cleared', () {
      final next = ControlDeviceMaxDurationLogic.clearOnStop(
        isLeftDevice: false,
        otherSideRunning: false,
        left: 15,
        right: 20,
      );
      expect(next.left, isNull);
      expect(next.right, isNull);
    });

    test('right stops while left still running → keep both', () {
      final next = ControlDeviceMaxDurationLogic.clearOnStop(
        isLeftDevice: false,
        otherSideRunning: true,
        left: 15,
        right: 20,
      );
      expect(next.left, 15);
      expect(next.right, 20);
    });
  });

  group('displayDeviceMaxDuration', () {
    test('left / right selections read their own firmware maxTime', () {
      expect(
        ControlDeviceMaxDurationLogic.displayDeviceMaxDuration(
          selected: PumpSelection.left,
          left: 15,
          right: 20,
        ),
        15,
      );
      expect(
        ControlDeviceMaxDurationLogic.displayDeviceMaxDuration(
          selected: PumpSelection.right,
          left: 15,
          right: 20,
        ),
        20,
      );
    });

    test('Both with matching values prefers that value', () {
      expect(
        ControlDeviceMaxDurationLogic.displayDeviceMaxDuration(
          selected: PumpSelection.both,
          left: 15,
          right: 15,
        ),
        15,
      );
    });

    test('Both with disagreed 15 vs 20 falls back to UI (null)', () {
      expect(
        ControlDeviceMaxDurationLogic.displayDeviceMaxDuration(
          selected: PumpSelection.both,
          left: 15,
          right: 20,
        ),
        isNull,
      );
      expect(
        ControlDeviceMaxDurationLogic.displayDeviceMaxDuration(
          selected: PumpSelection.both,
          left: null,
          right: 20,
        ),
        20,
      );
      expect(
        ControlDeviceMaxDurationLogic.displayDeviceMaxDuration(
          selected: PumpSelection.both,
          left: null,
          right: null,
        ),
        isNull,
      );
    });
  });

  group('sideDeviceMaxDuration + kick natural-end', () {
    // User bug: shared maxTime became 20 after the right DP, so a left
    // natural end at 15 min was treated as an unexpected stop and kicked.
    test('left ended at 15 while right still reports 20 → no kick on left', () {
      const leftMax = 15;
      const rightMax = 20;
      final leftDeviceMax = ControlDeviceMaxDurationLogic.sideDeviceMaxDuration(
        isLeft: true,
        left: leftMax,
        right: rightMax,
      );
      expect(
        ControlDbRefreshKickLogic.shouldKickOnDbOffline(
          elapsedSeconds: 15 * 60,
          deviceMaxDuration: leftDeviceMax,
          uiMaxDuration: 15,
        ),
        isFalse,
        reason: 'left reached its own 15 min limit',
      );
    });

    test('right still mid-session at 15 min with max 20 → kick if it drops', () {
      final rightDeviceMax = ControlDeviceMaxDurationLogic.sideDeviceMaxDuration(
        isLeft: false,
        left: 15,
        right: 20,
      );
      expect(
        ControlDbRefreshKickLogic.shouldKickOnDbOffline(
          elapsedSeconds: 15 * 60,
          deviceMaxDuration: rightDeviceMax,
          uiMaxDuration: 15,
        ),
        isTrue,
        reason: 'right has 5 min left; a drop is unexpected',
      );
    });

    test('OLD shared value would have kicked the naturally-ended left side', () {
      // Shared overwrite: last report was right=20.
      expect(
        ControlDbRefreshKickLogic.shouldKickOnDbOffline(
          elapsedSeconds: 15 * 60,
          deviceMaxDuration: 20,
          uiMaxDuration: 15,
        ),
        isTrue,
        reason: 'documents the old shared-maxTime bug',
      );
    });

    test('null per-side value falls back to UI max (15) so no false kick at 15', () {
      expect(
        ControlDbRefreshKickLogic.shouldKickOnDbOffline(
          elapsedSeconds: 15 * 60,
          deviceMaxDuration: null,
          uiMaxDuration: 15,
        ),
        isFalse,
      );
    });
  });
}
