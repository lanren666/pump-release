import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pump/services/tuya/first_dp_or_timeout.dart';

void main() {
  group('waitFirstDpOrTimeout', () {
    // ── Normal scenarios ──────────────────────────────────────────────────

    test('fires when stream emits the target devId', () async {
      final ctrl = StreamController<String>.broadcast();
      var calls = 0;

      waitFirstDpOrTimeout(
        deviceIdStream: ctrl.stream,
        targetDevId: 'dev-A',
        timeout: const Duration(seconds: 10),
        onReady: () => calls++,
      );

      ctrl.add('dev-A');
      await Future.delayed(Duration.zero);

      expect(calls, 1);
      ctrl.close();
    });

    test('ignores events from other devices', () async {
      final ctrl = StreamController<String>.broadcast();
      var calls = 0;

      waitFirstDpOrTimeout(
        deviceIdStream: ctrl.stream,
        targetDevId: 'dev-A',
        timeout: const Duration(seconds: 10),
        onReady: () => calls++,
      );

      ctrl.add('dev-B');
      ctrl.add('dev-C');
      await Future.delayed(Duration.zero);
      expect(calls, 0); // still waiting

      ctrl.add('dev-A');
      await Future.delayed(Duration.zero);
      expect(calls, 1);

      ctrl.close();
    });

    test('fires only once even if stream emits target multiple times', () async {
      final ctrl = StreamController<String>.broadcast();
      var calls = 0;

      waitFirstDpOrTimeout(
        deviceIdStream: ctrl.stream,
        targetDevId: 'dev-A',
        timeout: const Duration(seconds: 10),
        onReady: () => calls++,
      );

      ctrl.add('dev-A');
      ctrl.add('dev-A');
      ctrl.add('dev-A');
      await Future.delayed(Duration.zero);

      expect(calls, 1);
      ctrl.close();
    });

    // ── Timeout / fallback ────────────────────────────────────────────────

    test('fires via timeout when no stream event arrives', () async {
      final ctrl = StreamController<String>.broadcast();
      var calls = 0;

      waitFirstDpOrTimeout(
        deviceIdStream: ctrl.stream,
        targetDevId: 'dev-A',
        timeout: const Duration(milliseconds: 50),
        onReady: () => calls++,
      );

      await Future.delayed(const Duration(milliseconds: 120));

      expect(calls, 1);
      ctrl.close();
    });

    test('no double-fire after timeout: stream event after timeout is ignored',
        () async {
      final ctrl = StreamController<String>.broadcast();
      var calls = 0;

      waitFirstDpOrTimeout(
        deviceIdStream: ctrl.stream,
        targetDevId: 'dev-A',
        timeout: const Duration(milliseconds: 50),
        onReady: () => calls++,
      );

      await Future.delayed(const Duration(milliseconds: 120)); // timeout fires
      ctrl.add('dev-A'); // too late
      await Future.delayed(Duration.zero);

      expect(calls, 1);
      ctrl.close();
    });

    // ── Race: stream and timer fire in the same batch ─────────────────────

    test('fires exactly once when stream event and timer race', () async {
      final ctrl = StreamController<String>.broadcast();
      var calls = 0;

      waitFirstDpOrTimeout(
        deviceIdStream: ctrl.stream,
        targetDevId: 'dev-A',
        // Very short timeout so it fires together with the stream add below
        timeout: const Duration(milliseconds: 10),
        onReady: () => calls++,
      );

      ctrl.add('dev-A');
      // Give both the stream listener and the timer a chance to fire
      await Future.delayed(const Duration(milliseconds: 30));

      expect(calls, 1, reason: 'onReady must fire exactly once');
      ctrl.close();
    });

    // ── Cancel ───────────────────────────────────────────────────────────

    test('cancel before stream event suppresses callback', () async {
      final ctrl = StreamController<String>.broadcast();
      var calls = 0;

      final cancel = waitFirstDpOrTimeout(
        deviceIdStream: ctrl.stream,
        targetDevId: 'dev-A',
        timeout: const Duration(seconds: 10),
        onReady: () => calls++,
      );

      cancel();
      ctrl.add('dev-A');
      await Future.delayed(Duration.zero);

      expect(calls, 0);
      ctrl.close();
    });

    test('cancel before timeout suppresses callback', () async {
      final ctrl = StreamController<String>.broadcast();
      var calls = 0;

      final cancel = waitFirstDpOrTimeout(
        deviceIdStream: ctrl.stream,
        targetDevId: 'dev-A',
        timeout: const Duration(milliseconds: 50),
        onReady: () => calls++,
      );

      cancel();
      await Future.delayed(const Duration(milliseconds: 120));

      expect(calls, 0);
      ctrl.close();
    });

    test('cancel after fire is a no-op (does not throw)', () async {
      final ctrl = StreamController<String>.broadcast();
      var calls = 0;

      final cancel = waitFirstDpOrTimeout(
        deviceIdStream: ctrl.stream,
        targetDevId: 'dev-A',
        timeout: const Duration(seconds: 10),
        onReady: () => calls++,
      );

      ctrl.add('dev-A');
      await Future.delayed(Duration.zero);
      expect(calls, 1);

      expect(() => cancel(), returnsNormally); // must not throw
      ctrl.close();
    });

    // ── Edge cases ────────────────────────────────────────────────────────

    test('stream error does not call onReady', () async {
      final ctrl = StreamController<String>.broadcast();
      var calls = 0;

      waitFirstDpOrTimeout(
        deviceIdStream: ctrl.stream,
        targetDevId: 'dev-A',
        timeout: const Duration(seconds: 10),
        onReady: () => calls++,
      );

      ctrl.addError(Exception('network error'));
      await Future.delayed(Duration.zero);

      expect(calls, 0);
      ctrl.close();
    });

    test('empty stream (closed immediately) falls back to timeout', () async {
      final ctrl = StreamController<String>.broadcast();
      var calls = 0;

      waitFirstDpOrTimeout(
        deviceIdStream: ctrl.stream,
        targetDevId: 'dev-A',
        timeout: const Duration(milliseconds: 50),
        onReady: () => calls++,
      );

      await ctrl.close(); // close stream immediately

      await Future.delayed(const Duration(milliseconds: 120));
      expect(calls, 1);
    });
  });
}
