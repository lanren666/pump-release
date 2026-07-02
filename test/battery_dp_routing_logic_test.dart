import 'package:flutter_test/flutter_test.dart';
import 'package:pump/services/battery/battery_dp_routing_logic.dart';

void main() {
  group('BatteryDpRoutingLogic.resolveUpdateSide', () {
    // ── 正常场景 ──────────────────────────────────────────────────────────────

    test('left device devId matches → left', () {
      expect(
        BatteryDpRoutingLogic.resolveUpdateSide(
          leftDevId: 'dev-left',
          rightDevId: 'dev-right',
          updateDeviceId: 'dev-left',
          updatePosition: 'left',
        ),
        'left',
      );
    });

    test('right device devId matches → right', () {
      expect(
        BatteryDpRoutingLogic.resolveUpdateSide(
          leftDevId: 'dev-left',
          rightDevId: 'dev-right',
          updateDeviceId: 'dev-right',
          updatePosition: 'right',
        ),
        'right',
      );
    });

    test('only left device paired, left devId matches → left', () {
      expect(
        BatteryDpRoutingLogic.resolveUpdateSide(
          leftDevId: 'dev-left',
          rightDevId: null,
          updateDeviceId: 'dev-left',
          updatePosition: 'left',
        ),
        'left',
      );
    });

    test('only right device paired, right devId matches → right', () {
      expect(
        BatteryDpRoutingLogic.resolveUpdateSide(
          leftDevId: null,
          rightDevId: 'dev-right',
          updateDeviceId: 'dev-right',
          updatePosition: 'right',
        ),
        'right',
      );
    });

    // ── 异常场景 ──────────────────────────────────────────────────────────────

    test('unknown deviceId → null (ignored)', () {
      expect(
        BatteryDpRoutingLogic.resolveUpdateSide(
          leftDevId: 'dev-left',
          rightDevId: 'dev-right',
          updateDeviceId: 'dev-unknown',
          updatePosition: 'left',
        ),
        isNull,
      );
    });

    test('both sides null (no paired devices) → null', () {
      expect(
        BatteryDpRoutingLogic.resolveUpdateSide(
          leftDevId: null,
          rightDevId: null,
          updateDeviceId: 'dev-any',
          updatePosition: 'left',
        ),
        isNull,
      );
    });

    test('left devId null, right devId null, updateDeviceId empty → null', () {
      expect(
        BatteryDpRoutingLogic.resolveUpdateSide(
          leftDevId: null,
          rightDevId: null,
          updateDeviceId: '',
          updatePosition: null,
        ),
        isNull,
      );
    });

    test('devId matches left, position is right → left wins (devId is authoritative)', () {
      // devId and position should always agree in normal operation.
      // When they disagree (data inconsistency), devId takes priority because
      // isLeft = position=='left' || isLeftDevice — if isLeftDevice is true the
      // result is 'left' regardless of position.
      expect(
        BatteryDpRoutingLogic.resolveUpdateSide(
          leftDevId: 'dev-left',
          rightDevId: 'dev-right',
          updateDeviceId: 'dev-left',
          updatePosition: 'right', // inconsistent with devId
        ),
        'left',
      );
    });

    test('devId matches right, position is null → right', () {
      // position can be null if DB record is incomplete; devId still resolves correctly.
      expect(
        BatteryDpRoutingLogic.resolveUpdateSide(
          leftDevId: 'dev-left',
          rightDevId: 'dev-right',
          updateDeviceId: 'dev-right',
          updatePosition: null,
        ),
        'right',
      );
    });
  });

  group('BatteryDpRoutingLogic.parseBatteryValue', () {
    // ── 正常场景 ──────────────────────────────────────────────────────────────

    test('integer 1 (low/red) → 1', () {
      expect(BatteryDpRoutingLogic.parseBatteryValue(1), 1);
    });

    test('integer 2 (mid/orange) → 2', () {
      expect(BatteryDpRoutingLogic.parseBatteryValue(2), 2);
    });

    test('integer 3 (full/green) → 3', () {
      expect(BatteryDpRoutingLogic.parseBatteryValue(3), 3);
    });

    test('string "1" → 1 (SDK may send string-serialised integers)', () {
      expect(BatteryDpRoutingLogic.parseBatteryValue('1'), 1);
    });

    test('string "3" → 3', () {
      expect(BatteryDpRoutingLogic.parseBatteryValue('3'), 3);
    });

    // ── 异常场景 ──────────────────────────────────────────────────────────────

    test('null → null (caller skips update, listener not disrupted)', () {
      expect(BatteryDpRoutingLogic.parseBatteryValue(null), isNull);
    });

    test('non-numeric string → null', () {
      expect(BatteryDpRoutingLogic.parseBatteryValue('abc'), isNull);
    });

    test('float string "1.0" → null (SDK should send int, not float)', () {
      // int.tryParse does not accept "1.0"; returning null avoids crashing.
      expect(BatteryDpRoutingLogic.parseBatteryValue('1.0'), isNull);
    });

    test('empty string → null', () {
      expect(BatteryDpRoutingLogic.parseBatteryValue(''), isNull);
    });
  });
}
