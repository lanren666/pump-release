import 'package:flutter_test/flutter_test.dart';
import 'package:pump/pages/control_session_settings_sync_logic.dart';
import 'package:pump/pages/control_types.dart';

void main() {
  group('ControlSessionSettingsSyncLogic.snapshotToAll', () {
    test('writes the same SessionMode to left, right, and both', () {
      final map = ControlSessionSettingsSyncLogic.snapshotToAll(
        SessionMode.custom,
      );

      expect(map[PumpSelection.left], SessionMode.custom);
      expect(map[PumpSelection.right], SessionMode.custom);
      expect(map[PumpSelection.both], SessionMode.custom);
    });

    test('writes the same max duration to every selection', () {
      for (final value in [15, 20, 25, 30]) {
        final map = ControlSessionSettingsSyncLogic.snapshotToAll(value);
        for (final selection in PumpSelection.values) {
          expect(map[selection], value, reason: 'value=$value $selection');
        }
      }
    });
  });

  group('ControlSessionSettingsSyncLogic.restore', () {
    test('returns the stored value for the target selection', () {
      final map = ControlSessionSettingsSyncLogic.snapshotToAll(
        SessionMode.custom,
      );
      expect(
        ControlSessionSettingsSyncLogic.restore(
          map,
          PumpSelection.left,
          SessionMode.defaultMode,
        ),
        SessionMode.custom,
      );
    });

    test('falls back when the key is missing', () {
      final map = <PumpSelection, SessionMode>{
        PumpSelection.both: SessionMode.custom,
      };
      expect(
        ControlSessionSettingsSyncLogic.restore(
          map,
          PumpSelection.left,
          SessionMode.defaultMode,
        ),
        SessionMode.defaultMode,
      );
    });

    test('max duration missing key falls back to 20', () {
      final map = <PumpSelection, int>{PumpSelection.both: 15};
      expect(
        ControlSessionSettingsSyncLogic.restore(
          map,
          PumpSelection.right,
          ControlSessionSettingsSyncLogic.defaultMaxDuration,
        ),
        20,
      );
    });
  });

  group('ControlSessionSettingsSyncLogic.syncThenRestore', () {
    // Normal path: user chose custom + 15 in Both, then BLE desync switches
    // to individual (left). Must keep custom + 15, not factory default.
    test('Both custom+15 → individual left keeps custom+15', () {
      final restored = ControlSessionSettingsSyncLogic.syncThenRestore(
        currentSessionMode: SessionMode.custom,
        currentMaxDuration: 15,
        target: PumpSelection.left,
      );
      expect(restored.sessionMode, SessionMode.custom);
      expect(restored.maxDuration, 15);
    });

    test('Both custom+15 → individual right keeps custom+15', () {
      final restored = ControlSessionSettingsSyncLogic.syncThenRestore(
        currentSessionMode: SessionMode.custom,
        currentMaxDuration: 15,
        target: PumpSelection.right,
      );
      expect(restored.sessionMode, SessionMode.custom);
      expect(restored.maxDuration, 15);
    });

    test('user later switches left → right still sees the same settings', () {
      final afterLeft = ControlSessionSettingsSyncLogic.syncThenRestore(
        currentSessionMode: SessionMode.custom,
        currentMaxDuration: 15,
        target: PumpSelection.left,
      );
      final afterRight = ControlSessionSettingsSyncLogic.syncThenRestore(
        currentSessionMode: afterLeft.sessionMode,
        currentMaxDuration: afterLeft.maxDuration,
        target: PumpSelection.right,
      );
      expect(afterRight.sessionMode, SessionMode.custom);
      expect(afterRight.maxDuration, 15);
    });

    test('default mode + 20 survives a Both → left swap (no false upgrade)', () {
      final restored = ControlSessionSettingsSyncLogic.syncThenRestore(
        currentSessionMode: SessionMode.defaultMode,
        currentMaxDuration: 20,
        target: PumpSelection.left,
      );
      expect(restored.sessionMode, SessionMode.defaultMode);
      expect(restored.maxDuration, 20);
    });

    test('beginner / boostMilk / custom all survive a selection swap', () {
      for (final mode in SessionMode.values) {
        final restored = ControlSessionSettingsSyncLogic.syncThenRestore(
          currentSessionMode: mode,
          currentMaxDuration: 25,
          target: PumpSelection.right,
        );
        expect(restored.sessionMode, mode, reason: '$mode');
        expect(restored.maxDuration, 25);
      }
    });

    // Abnormal: stale per-pump map used to keep left=default while both=custom.
    // snapshot-then-restore overwrites that stale left entry.
    test('stale left default is overwritten by current custom before restore', () {
      final stale = {
        PumpSelection.left: SessionMode.defaultMode,
        PumpSelection.right: SessionMode.defaultMode,
        PumpSelection.both: SessionMode.custom,
      };
      final synced = ControlSessionSettingsSyncLogic.snapshotToAll(
        SessionMode.custom,
      );
      expect(synced[PumpSelection.left], isNot(stale[PumpSelection.left]));
      expect(
        ControlSessionSettingsSyncLogic.restore(
          synced,
          PumpSelection.left,
          SessionMode.defaultMode,
        ),
        SessionMode.custom,
      );
    });
  });
}
