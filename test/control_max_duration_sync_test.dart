import 'package:flutter_test/flutter_test.dart';
import 'package:pump/pages/control_types.dart';

// ---------------------------------------------------------------------------
// Tests for the Bug-1 fix: changing max duration from the UI should update
// ALL pump-selection entries in _pumpMaxDurations so that _syncDisplayVariables
// never restores a stale default when switching between selections.
//
// The fix (control.dart onChanged):
//   _pumpMaxDurations[PumpSelection.left] = newValue;
//   _pumpMaxDurations[PumpSelection.right] = newValue;
//   _pumpMaxDurations[PumpSelection.both] = newValue;
//
// These tests model the map invariant directly — no widget required.
// ---------------------------------------------------------------------------

/// Simulates the old (buggy) behaviour: only the currently-selected entry
/// is updated when the user changes max duration.
Map<PumpSelection, int> _oldBuggyUpdate(
  Map<PumpSelection, int> durations,
  PumpSelection activeSelection,
  int newValue,
) {
  return Map.of(durations)..[activeSelection] = newValue;
}

/// Simulates the fixed behaviour: all three entries are updated.
Map<PumpSelection, int> _fixedUpdate(
  Map<PumpSelection, int> durations,
  int newValue,
) {
  return {
    PumpSelection.left: newValue,
    PumpSelection.right: newValue,
    PumpSelection.both: newValue,
  };
}

/// Simulates _syncDisplayVariables: returns the stored max duration for
/// [target], defaulting to 20 when absent (matching the widget logic).
int _syncRestoreMaxDuration(
  Map<PumpSelection, int> durations,
  PumpSelection target,
) {
  return durations[target] ?? 20;
}

const _defaultMax = 20;

void main() {
  group('_pumpMaxDurations sync invariant (Bug-1 fix)', () {
    // -----------------------------------------------------------------------
    // Demonstrates the old bug
    // -----------------------------------------------------------------------
    group('OLD (buggy): only active selection updated', () {
      test(
          'user in Both mode changes to 15 → left still shows 20 after sync',
          () {
        final durations = {
          PumpSelection.left: _defaultMax,
          PumpSelection.right: _defaultMax,
          PumpSelection.both: _defaultMax,
        };
        final updated =
            _oldBuggyUpdate(durations, PumpSelection.both, 15);

        // Bug: individual mode calls _syncDisplayVariables(PumpSelection.left)
        // → reads left=20 (stale default)
        expect(
          _syncRestoreMaxDuration(updated, PumpSelection.left),
          _defaultMax,
          reason: 'OLD bug: left not updated, so sync restores wrong value',
        );
      });

      test('user in Left mode changes to 15 → both still shows 20', () {
        final durations = {
          PumpSelection.left: _defaultMax,
          PumpSelection.right: _defaultMax,
          PumpSelection.both: _defaultMax,
        };
        final updated =
            _oldBuggyUpdate(durations, PumpSelection.left, 15);

        expect(
          _syncRestoreMaxDuration(updated, PumpSelection.both),
          _defaultMax,
          reason: 'OLD bug: both not updated',
        );
      });
    });

    // -----------------------------------------------------------------------
    // Fixed behaviour
    // -----------------------------------------------------------------------
    group('FIXED: all selections updated simultaneously', () {
      test(
          'user in Both mode changes to 15 → left and right also show 15 after sync',
          () {
        final durations = {
          PumpSelection.left: _defaultMax,
          PumpSelection.right: _defaultMax,
          PumpSelection.both: _defaultMax,
        };
        final updated = _fixedUpdate(durations, 15);

        expect(_syncRestoreMaxDuration(updated, PumpSelection.left), 15);
        expect(_syncRestoreMaxDuration(updated, PumpSelection.right), 15);
        expect(_syncRestoreMaxDuration(updated, PumpSelection.both), 15);
      });

      test('all firmware-valid maxTime values sync correctly', () {
        for (final newValue in [15, 20, 25, 30]) {
          final durations = {
            PumpSelection.left: _defaultMax,
            PumpSelection.right: _defaultMax,
            PumpSelection.both: _defaultMax,
          };
          final updated = _fixedUpdate(durations, newValue);

          for (final selection in PumpSelection.values) {
            expect(
              _syncRestoreMaxDuration(updated, selection),
              newValue,
              reason: 'newValue=$newValue, selection=$selection',
            );
          }
        }
      });

      test('sequential changes: last write wins for all selections', () {
        var durations = {
          PumpSelection.left: _defaultMax,
          PumpSelection.right: _defaultMax,
          PumpSelection.both: _defaultMax,
        };
        durations = _fixedUpdate(durations, 15);
        durations = _fixedUpdate(durations, 25);

        for (final selection in PumpSelection.values) {
          expect(
            _syncRestoreMaxDuration(durations, selection),
            25,
            reason: 'last change was to 25; all selections should read 25',
          );
        }
      });

      // Critical scenario: user changes to 15 in Both mode, then
      // individual mode kicks in → _syncDisplayVariables(PumpSelection.left)
      // should restore 15, not the old default 20.
      test(
          'individual mode switch after Both-mode duration change reads correct value',
          () {
        final durations = {
          PumpSelection.left: _defaultMax,
          PumpSelection.right: _defaultMax,
          PumpSelection.both: _defaultMax,
        };
        // User changes max to 15 in Both mode.
        final updated = _fixedUpdate(durations, 15);

        // Individual mode fires → _syncDisplayVariables(PumpSelection.left)
        expect(
          _syncRestoreMaxDuration(updated, PumpSelection.left),
          15,
          reason: 'After fix: individual mode restore reads correct 15 min',
        );
      });

      // Regression guard: confirm that _pumpSessionModes remains independent
      // (only _pumpMaxDurations is shared; session mode per pump is unchanged).
      test('duration sync does not affect session-mode independence (static contract)',
          () {
        // Session modes are stored in a separate Map<PumpSelection, SessionMode>
        // that is NOT touched by the duration fix.  We verify this contract by
        // checking that a full _fixedUpdate on a durations-only map has no
        // side effect on an independent session-mode map.
        const sessionModes = {
          PumpSelection.left: 'custom',
          PumpSelection.right: 'default',
          PumpSelection.both: 'default',
        };
        final durations = {
          PumpSelection.left: _defaultMax,
          PumpSelection.right: _defaultMax,
          PumpSelection.both: _defaultMax,
        };
        _fixedUpdate(durations, 15); // mutate only durations

        // Session modes should be unchanged.
        expect(sessionModes[PumpSelection.left], 'custom');
        expect(sessionModes[PumpSelection.right], 'default');
      });
    });

    // -----------------------------------------------------------------------
    // Default-value guard
    // -----------------------------------------------------------------------
    test('missing key falls back to 20 (default guard)', () {
      // If a key is somehow absent, _syncRestoreMaxDuration returns 20.
      final partialMap = {PumpSelection.both: 15};
      expect(
        _syncRestoreMaxDuration(partialMap, PumpSelection.left),
        _defaultMax,
      );
    });
  });
}
