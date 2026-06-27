import 'package:flutter_test/flutter_test.dart';
import 'package:pump/pages/control_both_session_end_logic.dart';

// Helper: maxTime values the firmware supports.
const _maxTimes = [15, 20, 25, 30]; // minutes

void main() {
  group('ControlBothSessionEndLogic', () {
    // -----------------------------------------------------------------------
    // completedNaturally
    // -----------------------------------------------------------------------
    group('completedNaturally', () {
      // --- Normal session end (should return true) ---

      test('timePast equals maxTime in seconds → natural end', () {
        for (final maxMin in _maxTimes) {
          final maxSec = maxMin * 60;
          expect(
            ControlBothSessionEndLogic.completedNaturally(
              timePast: maxSec,
              maxTimeMinutes: maxMin,
            ),
            isTrue,
            reason: 'maxTime=$maxMin min, timePast=$maxSec s',
          );
        }
      });

      test('timePast 1 s before max → natural end (firmware reporting lag)', () {
        for (final maxMin in _maxTimes) {
          final maxSec = maxMin * 60;
          expect(
            ControlBothSessionEndLogic.completedNaturally(
              timePast: maxSec - 1,
              maxTimeMinutes: maxMin,
            ),
            isTrue,
            reason: 'maxTime=$maxMin min, timePast=${maxSec - 1} s',
          );
        }
      });

      test('timePast 30 s before max → natural end (within default 60 s tolerance)', () {
        for (final maxMin in _maxTimes) {
          final maxSec = maxMin * 60;
          expect(
            ControlBothSessionEndLogic.completedNaturally(
              timePast: maxSec - 30,
              maxTimeMinutes: maxMin,
            ),
            isTrue,
            reason: 'maxTime=$maxMin min, timePast=${maxSec - 30} s',
          );
        }
      });

      test('timePast exactly at tolerance boundary → natural end', () {
        const tolerance =
            ControlBothSessionEndLogic.defaultNaturalEndToleranceSeconds;
        for (final maxMin in _maxTimes) {
          final maxSec = maxMin * 60;
          expect(
            ControlBothSessionEndLogic.completedNaturally(
              timePast: maxSec - tolerance,
              maxTimeMinutes: maxMin,
            ),
            isTrue,
            reason: 'maxTime=$maxMin min, timePast=${maxSec - tolerance} s '
                '(boundary = exactly -${tolerance}s)',
          );
        }
      });

      test('timePast exceeds max (clock drift) → natural end', () {
        for (final maxMin in _maxTimes) {
          final maxSec = maxMin * 60;
          expect(
            ControlBothSessionEndLogic.completedNaturally(
              timePast: maxSec + 10,
              maxTimeMinutes: maxMin,
            ),
            isTrue,
            reason: 'maxTime=$maxMin min, timePast=${maxSec + 10} s',
          );
        }
      });

      // --- Mid-session crash (should return false) ---

      test('timePast is 0 → not natural end (device crashed immediately)', () {
        for (final maxMin in _maxTimes) {
          expect(
            ControlBothSessionEndLogic.completedNaturally(
              timePast: 0,
              maxTimeMinutes: maxMin,
            ),
            isFalse,
            reason: 'maxTime=$maxMin min, timePast=0 s',
          );
        }
      });

      test('timePast at 5 min of 20-min session → not natural end', () {
        expect(
          ControlBothSessionEndLogic.completedNaturally(
            timePast: 300,
            maxTimeMinutes: 20,
          ),
          isFalse,
        );
      });

      test('timePast at 10 min of 20-min session → not natural end', () {
        expect(
          ControlBothSessionEndLogic.completedNaturally(
            timePast: 600,
            maxTimeMinutes: 20,
          ),
          isFalse,
        );
      });

      test('timePast 1 s outside tolerance → not natural end', () {
        const tolerance =
            ControlBothSessionEndLogic.defaultNaturalEndToleranceSeconds;
        for (final maxMin in _maxTimes) {
          final maxSec = maxMin * 60;
          final timePast = maxSec - tolerance - 1;
          expect(
            ControlBothSessionEndLogic.completedNaturally(
              timePast: timePast,
              maxTimeMinutes: maxMin,
            ),
            isFalse,
            reason: 'maxTime=$maxMin min, timePast=$timePast s '
                '(1 s outside tolerance)',
          );
        }
      });

      // --- Edge cases ---

      test('maxTimeMinutes = 0 → false (unknown config, default to safe)', () {
        expect(
          ControlBothSessionEndLogic.completedNaturally(
            timePast: 9999,
            maxTimeMinutes: 0,
          ),
          isFalse,
        );
      });

      test('custom toleranceSeconds respected', () {
        // With tolerance=30, timePast at -45s is NOT natural; at -29s IS.
        expect(
          ControlBothSessionEndLogic.completedNaturally(
            timePast: 20 * 60 - 45, // 45 s before max
            maxTimeMinutes: 20,
            toleranceSeconds: 30,
          ),
          isFalse,
          reason: '45 s before max with tolerance=30 → not natural',
        );
        expect(
          ControlBothSessionEndLogic.completedNaturally(
            timePast: 20 * 60 - 29, // 29 s before max
            maxTimeMinutes: 20,
            toleranceSeconds: 30,
          ),
          isTrue,
          reason: '29 s before max with tolerance=30 → natural',
        );
      });
    });

    // -----------------------------------------------------------------------
    // shouldKickOnBothStop
    // -----------------------------------------------------------------------
    group('shouldKickOnBothStop', () {
      // --- Other side not running → never kick ---

      test('otherSideRunning=false → no kick regardless of timePast', () {
        for (final maxMin in _maxTimes) {
          // Natural end scenario
          expect(
            ControlBothSessionEndLogic.shouldKickOnBothStop(
              otherSideRunning: false,
              timePast: maxMin * 60,
              maxTimeMinutes: maxMin,
            ),
            isFalse,
            reason: 'natural end, other not running',
          );
          // Mid-session scenario
          expect(
            ControlBothSessionEndLogic.shouldKickOnBothStop(
              otherSideRunning: false,
              timePast: 60,
              maxTimeMinutes: maxMin,
            ),
            isFalse,
            reason: 'mid-session crash, but other not running',
          );
        }
      });

      // --- Natural session end → no kick ---

      test('natural end with other running → no kick', () {
        for (final maxMin in _maxTimes) {
          final maxSec = maxMin * 60;
          expect(
            ControlBothSessionEndLogic.shouldKickOnBothStop(
              otherSideRunning: true,
              timePast: maxSec,
              maxTimeMinutes: maxMin,
            ),
            isFalse,
            reason: 'maxTime=$maxMin min, timePast=$maxSec s (exact end)',
          );
          expect(
            ControlBothSessionEndLogic.shouldKickOnBothStop(
              otherSideRunning: true,
              timePast: maxSec - 30,
              maxTimeMinutes: maxMin,
            ),
            isFalse,
            reason:
                'maxTime=$maxMin min, timePast=${maxSec - 30} s (30 s before end)',
          );
        }
      });

      // --- Mid-session crash with other running → kick ---

      test('crash at session start with other running → kick', () {
        expect(
          ControlBothSessionEndLogic.shouldKickOnBothStop(
            otherSideRunning: true,
            timePast: 0,
            maxTimeMinutes: 20,
          ),
          isTrue,
        );
      });

      test('crash at 5 min of 20-min session → kick', () {
        expect(
          ControlBothSessionEndLogic.shouldKickOnBothStop(
            otherSideRunning: true,
            timePast: 300,
            maxTimeMinutes: 20,
          ),
          isTrue,
        );
      });

      test('crash at 10 min of 20-min session → kick', () {
        expect(
          ControlBothSessionEndLogic.shouldKickOnBothStop(
            otherSideRunning: true,
            timePast: 600,
            maxTimeMinutes: 20,
          ),
          isTrue,
        );
      });

      test('crash 1 s outside tolerance with other running → kick', () {
        const tolerance =
            ControlBothSessionEndLogic.defaultNaturalEndToleranceSeconds;
        for (final maxMin in _maxTimes) {
          final timePast = maxMin * 60 - tolerance - 1;
          expect(
            ControlBothSessionEndLogic.shouldKickOnBothStop(
              otherSideRunning: true,
              timePast: timePast,
              maxTimeMinutes: maxMin,
            ),
            isTrue,
            reason: 'maxTime=$maxMin min, timePast=$timePast s',
          );
        }
      });

      // --- Boundary: tolerance edge ---

      test('timePast exactly at tolerance boundary → no kick (treated as natural end)', () {
        const tolerance =
            ControlBothSessionEndLogic.defaultNaturalEndToleranceSeconds;
        for (final maxMin in _maxTimes) {
          final timePast = maxMin * 60 - tolerance;
          expect(
            ControlBothSessionEndLogic.shouldKickOnBothStop(
              otherSideRunning: true,
              timePast: timePast,
              maxTimeMinutes: maxMin,
            ),
            isFalse,
            reason: 'maxTime=$maxMin min, timePast=$timePast s (boundary)',
          );
        }
      });

      // --- Safety edge cases ---

      test('maxTimeMinutes=0 → kick (unknown config, keep recovery path)', () {
        expect(
          ControlBothSessionEndLogic.shouldKickOnBothStop(
            otherSideRunning: true,
            timePast: 9999,
            maxTimeMinutes: 0,
          ),
          isTrue,
          reason: 'maxTime=0 is invalid; default to kick for safety',
        );
      });
    });

    // -----------------------------------------------------------------------
    // effectiveTimePast
    // -----------------------------------------------------------------------
    group('effectiveTimePast', () {
      // Core scenario: firmware resets timePast to 0 in the final
      // isRunning=0 packet after a natural session end.
      test('rawTimePast=0, lastRunning>0 → uses lastRunning (firmware reset)', () {
        expect(
          ControlBothSessionEndLogic.effectiveTimePast(
            rawTimePast: 0,
            lastRunningTimePast: 899,
          ),
          899,
        );
      });

      test('rawTimePast=0, lastRunning=0 → 0 (session never saw running packet)', () {
        expect(
          ControlBothSessionEndLogic.effectiveTimePast(
            rawTimePast: 0,
            lastRunningTimePast: 0,
          ),
          0,
        );
      });

      test('rawTimePast>0, lastRunning>0 → uses rawTimePast (normal packet)', () {
        expect(
          ControlBothSessionEndLogic.effectiveTimePast(
            rawTimePast: 500,
            lastRunningTimePast: 499,
          ),
          500,
        );
      });

      test('rawTimePast>0, lastRunning=0 → uses rawTimePast', () {
        expect(
          ControlBothSessionEndLogic.effectiveTimePast(
            rawTimePast: 300,
            lastRunningTimePast: 0,
          ),
          300,
        );
      });
    });

    // -----------------------------------------------------------------------
    // effectiveTimePast + shouldKickOnBothStop: end-to-end fix scenarios
    // -----------------------------------------------------------------------
    group('effectiveTimePast → shouldKickOnBothStop end-to-end', () {
      // The bug: firmware sends timePast=0 in final isRunning=0 packet.
      // Without the fix, shouldKickOnBothStop(timePast=0) wrongly kicks.
      // With the fix, effectiveTimePast restores the last known running value.
      test('firmware resets timePast=0 at natural end of 15-min session → no kick', () {
        // Last DP-105 with isRunning=1 reported timePast=899 (within 60 s of 900).
        final effective = ControlBothSessionEndLogic.effectiveTimePast(
          rawTimePast: 0,
          lastRunningTimePast: 899,
        );
        expect(
          ControlBothSessionEndLogic.shouldKickOnBothStop(
            otherSideRunning: true,
            timePast: effective,
            maxTimeMinutes: 15,
          ),
          isFalse,
          reason: 'effectiveTimePast=899 → natural end of 15-min session',
        );
      });

      test('firmware resets timePast=0 at natural end of 20-min session → no kick', () {
        final effective = ControlBothSessionEndLogic.effectiveTimePast(
          rawTimePast: 0,
          lastRunningTimePast: 1185, // 15 s before 1200
        );
        expect(
          ControlBothSessionEndLogic.shouldKickOnBothStop(
            otherSideRunning: true,
            timePast: effective,
            maxTimeMinutes: 20,
          ),
          isFalse,
        );
      });

      test('firmware resets timePast=0 at natural end for all maxTime values → no kick', () {
        final lastRunningByMaxTime = {15: 899, 20: 1199, 25: 1499, 30: 1799};
        for (final maxMin in _maxTimes) {
          final lastRunning = lastRunningByMaxTime[maxMin]!;
          final effective = ControlBothSessionEndLogic.effectiveTimePast(
            rawTimePast: 0,
            lastRunningTimePast: lastRunning,
          );
          expect(
            ControlBothSessionEndLogic.shouldKickOnBothStop(
              otherSideRunning: true,
              timePast: effective,
              maxTimeMinutes: maxMin,
            ),
            isFalse,
            reason: 'maxTime=$maxMin min, lastRunning=$lastRunning → natural end',
          );
        }
      });

      test('genuine mid-session crash: rawTimePast=0, no lastRunning → kick', () {
        // Device crashed at session start; no running packet ever received.
        final effective = ControlBothSessionEndLogic.effectiveTimePast(
          rawTimePast: 0,
          lastRunningTimePast: 0,
        );
        expect(
          ControlBothSessionEndLogic.shouldKickOnBothStop(
            otherSideRunning: true,
            timePast: effective,
            maxTimeMinutes: 20,
          ),
          isTrue,
          reason: 'effectiveTimePast=0, no history → kick',
        );
      });

      test('genuine mid-session crash at 5 min: lastRunning=300 is mid-session → kick', () {
        final effective = ControlBothSessionEndLogic.effectiveTimePast(
          rawTimePast: 0,
          lastRunningTimePast: 300,
        );
        expect(
          ControlBothSessionEndLogic.shouldKickOnBothStop(
            otherSideRunning: true,
            timePast: effective,
            maxTimeMinutes: 20,
          ),
          isTrue,
          reason: 'effectiveTimePast=300 → mid-session, kick',
        );
      });

      // After BOTH_KICK, _lastRunningTimePast is reset to 0 (Bug #2 fix).
      // If the restarted device crashes before sending isRunning=1, lastRunning=0.
      test('post-BOTH_KICK crash with no new isRunning=1 packets: lastRunning=0 → kick', () {
        // The kicked device never sent a running packet; lastRunning was reset.
        final effective = ControlBothSessionEndLogic.effectiveTimePast(
          rawTimePast: 0,
          lastRunningTimePast: 0, // reset by _kickBothSideSessionIfNeeded
        );
        expect(
          ControlBothSessionEndLogic.shouldKickOnBothStop(
            otherSideRunning: true,
            timePast: effective,
            maxTimeMinutes: 20,
          ),
          isTrue,
          reason: 'lastRunning reset by kick → crash detected correctly',
        );
      });

      // Both devices end nearly simultaneously (< 60 s apart).
      // Neither should restart the other.
      test('simultaneous natural end: both stopped within tolerance → no kick', () {
        for (final maxMin in _maxTimes) {
          final maxSec = maxMin * 60;
          // First device stops with timePast near maxTime; other side is still
          // running but will stop within seconds. Neither should be kicked.
          final effectiveFirst = ControlBothSessionEndLogic.effectiveTimePast(
            rawTimePast: 0,
            lastRunningTimePast: maxSec - 5, // 5 s before max
          );
          expect(
            ControlBothSessionEndLogic.shouldKickOnBothStop(
              otherSideRunning: true,
              timePast: effectiveFirst,
              maxTimeMinutes: maxMin,
            ),
            isFalse,
            reason: 'maxTime=$maxMin min: first side natural end → no kick',
          );
        }
      });

      // Mid-session crash (not natural end) regardless of lastRunning value.
      test('rawTimePast=600 (normal packet, mid 20-min session) → kick', () {
        final effective = ControlBothSessionEndLogic.effectiveTimePast(
          rawTimePast: 600,
          lastRunningTimePast: 599,
        );
        expect(
          ControlBothSessionEndLogic.shouldKickOnBothStop(
            otherSideRunning: true,
            timePast: effective,
            maxTimeMinutes: 20,
          ),
          isTrue,
        );
      });
    });
  });
}
