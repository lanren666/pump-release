import 'package:flutter_test/flutter_test.dart';
import 'package:pump/pages/control_db_refresh_kick_logic.dart';
import 'package:pump/pages/control_both_session_end_logic.dart';

// Helper: firmware-valid maxTime values (minutes).
const _maxTimes = [15, 20, 25, 30];

void main() {
  group('ControlDbRefreshKickLogic', () {
    // -----------------------------------------------------------------------
    // effectiveMaxMinutes
    // -----------------------------------------------------------------------
    group('effectiveMaxMinutes', () {
      test('deviceMaxDuration present → uses device value, ignores UI', () {
        expect(
          ControlDbRefreshKickLogic.effectiveMaxMinutes(
            deviceMaxDuration: 20,
            uiMaxDuration: 15,
          ),
          20,
        );
      });

      test('deviceMaxDuration null → falls back to UI value', () {
        expect(
          ControlDbRefreshKickLogic.effectiveMaxMinutes(
            deviceMaxDuration: null,
            uiMaxDuration: 15,
          ),
          15,
        );
      });

      test('all firmware-valid maxTime values pass through unchanged', () {
        for (final maxMin in _maxTimes) {
          expect(
            ControlDbRefreshKickLogic.effectiveMaxMinutes(
              deviceMaxDuration: maxMin,
              uiMaxDuration: 99, // irrelevant when device value present
            ),
            maxMin,
          );
        }
      });

      test('both values equal → returns that value', () {
        expect(
          ControlDbRefreshKickLogic.effectiveMaxMinutes(
            deviceMaxDuration: 20,
            uiMaxDuration: 20,
          ),
          20,
        );
      });

      test('deviceMaxDuration null, all valid UI values', () {
        for (final maxMin in _maxTimes) {
          expect(
            ControlDbRefreshKickLogic.effectiveMaxMinutes(
              deviceMaxDuration: null,
              uiMaxDuration: maxMin,
            ),
            maxMin,
          );
        }
      });
    });

    // -----------------------------------------------------------------------
    // shouldKickOnDbOffline — natural end (should NOT kick)
    // -----------------------------------------------------------------------
    group('shouldKickOnDbOffline: natural end → no kick', () {
      test('device ran exact maxTime → no kick', () {
        for (final maxMin in _maxTimes) {
          final maxSec = maxMin * 60;
          expect(
            ControlDbRefreshKickLogic.shouldKickOnDbOffline(
              elapsedSeconds: maxSec,
              deviceMaxDuration: maxMin,
              uiMaxDuration: maxMin,
            ),
            isFalse,
            reason: 'maxTime=$maxMin min, elapsed=$maxSec s (exact)',
          );
        }
      });

      test('elapsed within 60 s tolerance → no kick', () {
        const tolerance =
            ControlBothSessionEndLogic.defaultNaturalEndToleranceSeconds;
        for (final maxMin in _maxTimes) {
          final boundary = maxMin * 60 - tolerance;
          expect(
            ControlDbRefreshKickLogic.shouldKickOnDbOffline(
              elapsedSeconds: boundary,
              deviceMaxDuration: maxMin,
              uiMaxDuration: maxMin,
            ),
            isFalse,
            reason: 'maxTime=$maxMin min, elapsed=$boundary s (boundary)',
          );
          expect(
            ControlDbRefreshKickLogic.shouldKickOnDbOffline(
              elapsedSeconds: boundary + 10,
              deviceMaxDuration: maxMin,
              uiMaxDuration: maxMin,
            ),
            isFalse,
            reason:
                'maxTime=$maxMin min, elapsed=${boundary + 10} s (inside tolerance)',
          );
        }
      });

      test('elapsed exceeds maxTime (clock drift) → no kick', () {
        for (final maxMin in _maxTimes) {
          final overrun = maxMin * 60 + 10;
          expect(
            ControlDbRefreshKickLogic.shouldKickOnDbOffline(
              elapsedSeconds: overrun,
              deviceMaxDuration: maxMin,
              uiMaxDuration: maxMin,
            ),
            isFalse,
            reason: 'maxTime=$maxMin min, elapsed=$overrun s (overrun)',
          );
        }
      });

      // Scenario: session ends naturally, DP-105 cleared _deviceMaxDuration to
      // null before _refreshDeviceStatus fires → must fall back to UI value.
      test(
          'deviceMaxDuration null (session over), UI fallback detects natural end',
          () {
        // 20-min session, elapsed=1185 (within tolerance of 1200)
        expect(
          ControlDbRefreshKickLogic.shouldKickOnDbOffline(
            elapsedSeconds: 1185,
            deviceMaxDuration: null,
            uiMaxDuration: 20,
          ),
          isFalse,
          reason:
              'deviceMaxDuration cleared, UI=20 min, elapsed=1185 → natural end',
        );
      });

      // Scenario: user changed UI duration to 15 mid-session, but device ran
      // 20 min because _deviceMaxDuration carries the authoritative value.
      test(
          'UI changed to 15 mid-session but device ran 20 min: deviceMaxDuration wins',
          () {
        // Device ran full 20 min (elapsed=1185, within 60 s tolerance).
        // UI had been changed to 15. deviceMaxDuration=20 is authoritative.
        expect(
          ControlDbRefreshKickLogic.shouldKickOnDbOffline(
            elapsedSeconds: 1185,
            deviceMaxDuration: 20,
            uiMaxDuration: 15,
          ),
          isFalse,
          reason:
              'deviceMaxDuration=20 wins over UI=15; elapsed=1185 → natural end',
        );
      });

      // Scenario: user changed UI to 15 min AND session did end at 15 min.
      // deviceMaxDuration=15 (from device), elapsed=840 (= 15*60 - 60 = boundary).
      test('15-min session ends at tolerance boundary → no kick', () {
        expect(
          ControlDbRefreshKickLogic.shouldKickOnDbOffline(
            elapsedSeconds: 840, // 15*60 - 60
            deviceMaxDuration: 15,
            uiMaxDuration: 15,
          ),
          isFalse,
        );
      });

      // Scenario: deviceMaxDuration already null (cleared after DP-105 end),
      // user had changed UI to 15 min mid-session. Falls back to UI=15.
      test(
          'deviceMaxDuration null, UI=15 (user changed mid-session): UI fallback detects 15-min natural end',
          () {
        // 15-min session fully completed (elapsed=900), deviceMaxDuration already
        // cleared when refresh fires.
        expect(
          ControlDbRefreshKickLogic.shouldKickOnDbOffline(
            elapsedSeconds: 900,
            deviceMaxDuration: null,
            uiMaxDuration: 15,
          ),
          isFalse,
          reason: 'UI=15, elapsed=900 s → natural end',
        );
      });
    });

    // -----------------------------------------------------------------------
    // shouldKickOnDbOffline — mid-session crash (should kick)
    // -----------------------------------------------------------------------
    group('shouldKickOnDbOffline: mid-session crash → kick', () {
      test('elapsed=0 (crash at session start) → kick', () {
        expect(
          ControlDbRefreshKickLogic.shouldKickOnDbOffline(
            elapsedSeconds: 0,
            deviceMaxDuration: 20,
            uiMaxDuration: 20,
          ),
          isTrue,
        );
      });

      test('elapsed=300 (5 min of 20-min session) → kick', () {
        expect(
          ControlDbRefreshKickLogic.shouldKickOnDbOffline(
            elapsedSeconds: 300,
            deviceMaxDuration: 20,
            uiMaxDuration: 20,
          ),
          isTrue,
        );
      });

      test('elapsed=600 (10 min of 20-min session) → kick', () {
        expect(
          ControlDbRefreshKickLogic.shouldKickOnDbOffline(
            elapsedSeconds: 600,
            deviceMaxDuration: 20,
            uiMaxDuration: 20,
          ),
          isTrue,
        );
      });

      test('1 s outside tolerance → kick', () {
        const tolerance =
            ControlBothSessionEndLogic.defaultNaturalEndToleranceSeconds;
        for (final maxMin in _maxTimes) {
          final timePast = maxMin * 60 - tolerance - 1;
          expect(
            ControlDbRefreshKickLogic.shouldKickOnDbOffline(
              elapsedSeconds: timePast,
              deviceMaxDuration: maxMin,
              uiMaxDuration: maxMin,
            ),
            isTrue,
            reason:
                'maxTime=$maxMin min, elapsed=$timePast s (1 s outside tolerance)',
          );
        }
      });

      // Scenario: natural end happened but _deviceMaxDuration was already
      // cleared; UI value is at default 20. Session was actually 20 min but
      // the disconnect appeared when elapsed was only 300 s (early disconnect).
      test(
          'deviceMaxDuration null, UI=20, elapsed=300 (early crash) → kick',
          () {
        expect(
          ControlDbRefreshKickLogic.shouldKickOnDbOffline(
            elapsedSeconds: 300,
            deviceMaxDuration: null,
            uiMaxDuration: 20,
          ),
          isTrue,
        );
      });

      test(
          'mid-session crash at all maxTime values → all kick', () {
        for (final maxMin in _maxTimes) {
          expect(
            ControlDbRefreshKickLogic.shouldKickOnDbOffline(
              elapsedSeconds: 60, // 1 min into session
              deviceMaxDuration: maxMin,
              uiMaxDuration: maxMin,
            ),
            isTrue,
            reason: 'maxTime=$maxMin min, elapsed=60 s → kick',
          );
        }
      });
    });

    // -----------------------------------------------------------------------
    // shouldKickOnDbOffline — edge cases
    // -----------------------------------------------------------------------
    group('shouldKickOnDbOffline: edge cases', () {
      // maxTimeMinutes=0 cannot happen in normal firmware flow (decoder throws
      // FormatException for invalid values), but guard the path anyway.
      test('deviceMaxDuration=0 (invalid config) → kick (safe fallback)', () {
        expect(
          ControlDbRefreshKickLogic.shouldKickOnDbOffline(
            elapsedSeconds: 9999,
            deviceMaxDuration: 0,
            uiMaxDuration: 20,
          ),
          isTrue,
          reason: 'maxMins=0 is invalid; completedNaturally returns false',
        );
      });

      test('deviceMaxDuration=null AND uiMaxDuration=0 → kick (safe fallback)',
          () {
        expect(
          ControlDbRefreshKickLogic.shouldKickOnDbOffline(
            elapsedSeconds: 9999,
            deviceMaxDuration: null,
            uiMaxDuration: 0,
          ),
          isTrue,
        );
      });

      test('both paths agree: DP-105 and DB-refresh produce same kick decision',
          () {
        // For a mid-session crash at 600 s of a 20-min session:
        // DP-105 path uses shouldKickOnBothStop(otherSideRunning=true, ...)
        // DB-refresh path uses shouldKickOnDbOffline(...)
        // Both should return true.
        const elapsed = 600;
        const maxMin = 20;

        final dp105Decision = ControlBothSessionEndLogic.shouldKickOnBothStop(
          otherSideRunning: true,
          timePast: elapsed,
          maxTimeMinutes: maxMin,
        );
        final dbRefreshDecision =
            ControlDbRefreshKickLogic.shouldKickOnDbOffline(
          elapsedSeconds: elapsed,
          deviceMaxDuration: maxMin,
          uiMaxDuration: maxMin,
        );

        expect(dp105Decision, isTrue);
        expect(dbRefreshDecision, isTrue);
        expect(dp105Decision, dbRefreshDecision,
            reason: 'Both paths should agree for mid-session crash');
      });

      test('both paths agree: natural end scenario', () {
        const elapsed = 1185; // within 60 s tolerance of 1200
        const maxMin = 20;

        final dp105Decision = ControlBothSessionEndLogic.shouldKickOnBothStop(
          otherSideRunning: true,
          timePast: elapsed,
          maxTimeMinutes: maxMin,
        );
        final dbRefreshDecision =
            ControlDbRefreshKickLogic.shouldKickOnDbOffline(
          elapsedSeconds: elapsed,
          deviceMaxDuration: maxMin,
          uiMaxDuration: maxMin,
        );

        expect(dp105Decision, isFalse);
        expect(dbRefreshDecision, isFalse);
        expect(dp105Decision, dbRefreshDecision,
            reason: 'Both paths should agree for natural end');
      });
    });
  });
}
