import 'package:flutter_test/flutter_test.dart';
import 'package:pump/pages/control_db_refresh_kick_logic.dart';
import 'package:pump/pages/control_device_max_duration_logic.dart';
import 'package:pump/pages/control_navigation_resume_logic.dart';
import 'package:pump/pages/control_session_settings_sync_logic.dart';
import 'package:pump/pages/control_timer_display_logic.dart';
import 'package:pump/pages/control_types.dart';
import 'package:pump/services/tuya/both_sync_diagnostics.dart';

/// End-to-end chaining of the pure helpers that used to produce the
/// 2026-09-02 Both-disconnect bug:
///   custom 2→3 + max 15 → BLE drop → UI jumped to default 2→5 / max 20,
///   one device ended at 15 min and the other at 20.
void main() {
  group('Both disconnect: settings + timer + tab (user bug)', () {
    test('individual-mode switch keeps custom + 15 on left and right', () {
      const userMode = SessionMode.custom;
      const userMax = 15;

      for (final target in [PumpSelection.left, PumpSelection.right]) {
        final restored = ControlSessionSettingsSyncLogic.syncThenRestore(
          currentSessionMode: userMode,
          currentMaxDuration: userMax,
          target: target,
        );
        expect(restored.sessionMode, SessionMode.custom, reason: '$target');
        expect(restored.maxDuration, 15, reason: '$target');
      }
    });

    test('timer card does not go blank when the right side drops', () {
      expect(
        ControlTimerDisplayLogic.timerDisplayHasStarted(
          useBothUnifiedRules: true,
          leftHasStarted: true,
          rightHasStarted: false,
          singleSideHasStarted: true,
        ),
        isTrue,
      );
      expect(
        ControlTimerDisplayLogic.useLeftTimeForBothDisplay(
          leftHasStarted: true,
          rightHasStarted: false,
        ),
        isTrue,
      );
    });

    test('timer card keeps the remaining right-side time when left drops', () {
      expect(
        ControlTimerDisplayLogic.timerDisplayHasStarted(
          useBothUnifiedRules: true,
          leftHasStarted: false,
          rightHasStarted: true,
          singleSideHasStarted: true,
        ),
        isTrue,
      );
      expect(
        ControlTimerDisplayLogic.useLeftTimeForBothDisplay(
          leftHasStarted: false,
          rightHasStarted: true,
        ),
        isFalse,
      );
    });

    test('per-side firmware maxTime: dropdown 15 vs timer 20 no longer mixed', () {
      var firmware = (left: null as int?, right: null as int?);
      firmware = ControlDeviceMaxDurationLogic.applyReportedMaxTime(
        isLeftDevice: true,
        maxTime: 15,
        left: firmware.left,
        right: firmware.right,
      );
      firmware = ControlDeviceMaxDurationLogic.applyReportedMaxTime(
        isLeftDevice: false,
        maxTime: 20,
        left: firmware.left,
        right: firmware.right,
      );

      expect(
        ControlDeviceMaxDurationLogic.displayDeviceMaxDuration(
          selected: PumpSelection.left,
          left: firmware.left,
          right: firmware.right,
        ),
        15,
      );
      expect(
        ControlDeviceMaxDurationLogic.displayDeviceMaxDuration(
          selected: PumpSelection.right,
          left: firmware.left,
          right: firmware.right,
        ),
        20,
      );
      expect(
        ControlDeviceMaxDurationLogic.displayDeviceMaxDuration(
          selected: PumpSelection.both,
          left: firmware.left,
          right: firmware.right,
        ),
        isNull,
        reason: 'Both card falls back to UI max instead of mixing 15 and 20',
      );
    });

    test('left natural end at 15 is not kicked just because right reports 20', () {
      var firmware = ControlDeviceMaxDurationLogic.applyReportedMaxTime(
        isLeftDevice: true,
        maxTime: 15,
        left: null,
        right: null,
      );
      firmware = ControlDeviceMaxDurationLogic.applyReportedMaxTime(
        isLeftDevice: false,
        maxTime: 20,
        left: firmware.left,
        right: firmware.right,
      );

      final leftMax = ControlDeviceMaxDurationLogic.sideDeviceMaxDuration(
        isLeft: true,
        left: firmware.left,
        right: firmware.right,
      );
      expect(
        ControlDbRefreshKickLogic.shouldKickOnDbOffline(
          elapsedSeconds: 15 * 60,
          deviceMaxDuration: leftMax,
          uiMaxDuration: 15,
        ),
        isFalse,
      );
    });

    test('single-side BLE drop with frozen time must not count as Both desync', () {
      expect(
        BothSyncDiagnostics.failReason(
          leftAlive: true,
          rightAlive: false,
          leftLinked: true,
          rightLinked: false,
          leftMode: 'expression',
          rightMode: 'expression',
          leftPhase: 2,
          rightPhase: 2,
          leftTotalSec: 8 * 60 + 32,
          rightTotalSec: 6 * 60 + 27,
          leftPhaseSec: 200,
          rightPhaseSec: 267,
          thresholdSec: 30,
        ),
        isNull,
        reason: '08:32 vs frozen 06:27 during a right-side drop is not individual-mode',
      );
    });

    test('Both session BLE flicker does not steal the tab to left', () {
      expect(
        ControlNavigationResumeLogic.shouldSafeUpdateBothMode(
          selectedPump: PumpSelection.both,
          bothStartInProgress: false,
          leftHasStarted: false,
          rightHasStarted: false,
          sessionStartedAsBoth: true,
        ),
        isTrue,
      );
    });

    test('true single-side hardware start on an idle Both page still switches', () {
      expect(
        ControlNavigationResumeLogic.shouldSafeUpdateBothMode(
          selectedPump: PumpSelection.both,
          bothStartInProgress: false,
          leftHasStarted: false,
          rightHasStarted: false,
          sessionStartedAsBoth: false,
        ),
        isFalse,
      );
    });

    test('sequential Both start still hides the timer until both sides are up', () {
      expect(
        ControlTimerDisplayLogic.timerDisplayHasStarted(
          useBothUnifiedRules: true,
          leftHasStarted: true,
          rightHasStarted: false,
          singleSideHasStarted: true,
          bothStartInProgress: true,
        ),
        isFalse,
      );
    });
  });
}
