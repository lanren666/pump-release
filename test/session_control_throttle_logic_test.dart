import 'package:flutter_test/flutter_test.dart';
import 'package:pump/pages/session_control_throttle_logic.dart';

void main() {
  group('SessionControlThrottleLogic.shouldDispatch', () {
    const threshold = SessionControlThrottleLogic.defaultThresholdMs; // 1500

    // -----------------------------------------------------------------------
    // 首次调用（无历史记录）
    // -----------------------------------------------------------------------
    test('null lastDispatch always allows dispatch', () {
      expect(
        SessionControlThrottleLogic.shouldDispatch(
          lastDispatch: null,
          now: DateTime(2024, 1, 1, 12, 0, 0),
        ),
        isTrue,
      );
    });

    // -----------------------------------------------------------------------
    // 节流窗口内 → 丢弃
    // -----------------------------------------------------------------------
    test('0 ms since last dispatch → blocked', () {
      final t = DateTime(2024, 1, 1, 12, 0, 0);
      expect(
        SessionControlThrottleLogic.shouldDispatch(
          lastDispatch: t,
          now: t,
        ),
        isFalse,
      );
    });

    test('1 ms since last dispatch → blocked', () {
      final last = DateTime(2024, 1, 1, 12, 0, 0);
      final now = last.add(const Duration(milliseconds: 1));
      expect(
        SessionControlThrottleLogic.shouldDispatch(
          lastDispatch: last,
          now: now,
        ),
        isFalse,
      );
    });

    test('1499 ms since last dispatch → blocked', () {
      final last = DateTime(2024, 1, 1, 12, 0, 0);
      final now = last.add(const Duration(milliseconds: threshold - 1));
      expect(
        SessionControlThrottleLogic.shouldDispatch(
          lastDispatch: last,
          now: now,
        ),
        isFalse,
      );
    });

    // -----------------------------------------------------------------------
    // 节流窗口边界及之后 → 允许
    // -----------------------------------------------------------------------
    test('exactly 1500 ms since last dispatch → allowed', () {
      final last = DateTime(2024, 1, 1, 12, 0, 0);
      final now = last.add(Duration(milliseconds: threshold));
      expect(
        SessionControlThrottleLogic.shouldDispatch(
          lastDispatch: last,
          now: now,
        ),
        isTrue,
      );
    });

    test('1501 ms since last dispatch → allowed', () {
      final last = DateTime(2024, 1, 1, 12, 0, 0);
      final now = last.add(const Duration(milliseconds: threshold + 1));
      expect(
        SessionControlThrottleLogic.shouldDispatch(
          lastDispatch: last,
          now: now,
        ),
        isTrue,
      );
    });

    test('large gap (10 seconds) → allowed', () {
      final last = DateTime(2024, 1, 1, 12, 0, 0);
      final now = last.add(const Duration(seconds: 10));
      expect(
        SessionControlThrottleLogic.shouldDispatch(
          lastDispatch: last,
          now: now,
        ),
        isTrue,
      );
    });

    // -----------------------------------------------------------------------
    // 自定义阈值
    // -----------------------------------------------------------------------
    test('custom threshold: 500 ms, 499 ms elapsed → blocked', () {
      final last = DateTime(2024, 1, 1, 12, 0, 0);
      final now = last.add(const Duration(milliseconds: 499));
      expect(
        SessionControlThrottleLogic.shouldDispatch(
          lastDispatch: last,
          now: now,
          thresholdMs: 500,
        ),
        isFalse,
      );
    });

    test('custom threshold: 500 ms, 500 ms elapsed → allowed', () {
      final last = DateTime(2024, 1, 1, 12, 0, 0);
      final now = last.add(const Duration(milliseconds: 500));
      expect(
        SessionControlThrottleLogic.shouldDispatch(
          lastDispatch: last,
          now: now,
          thresholdMs: 500,
        ),
        isTrue,
      );
    });

    // -----------------------------------------------------------------------
    // 连续点击场景模拟
    // -----------------------------------------------------------------------
    test('rapid-tap scenario: only first and post-threshold taps allowed', () {
      final base = DateTime(2024, 1, 1, 12, 0, 0);
      DateTime? last;

      // 第1次点击 — 允许
      expect(
        SessionControlThrottleLogic.shouldDispatch(
            lastDispatch: last, now: base),
        isTrue,
      );
      last = base;

      // 第2次点击（300ms后）— 节流
      final tap2 = base.add(const Duration(milliseconds: 300));
      expect(
        SessionControlThrottleLogic.shouldDispatch(
            lastDispatch: last, now: tap2),
        isFalse,
      );

      // 第3次点击（800ms后）— 节流
      final tap3 = base.add(const Duration(milliseconds: 800));
      expect(
        SessionControlThrottleLogic.shouldDispatch(
            lastDispatch: last, now: tap3),
        isFalse,
      );

      // 第4次点击（1600ms后）— 允许
      final tap4 = base.add(const Duration(milliseconds: 1600));
      expect(
        SessionControlThrottleLogic.shouldDispatch(
            lastDispatch: last, now: tap4),
        isTrue,
      );
      last = tap4;

      // 第5次点击（1700ms后 = 距上次100ms）— 节流
      final tap5 = base.add(const Duration(milliseconds: 1700));
      expect(
        SessionControlThrottleLogic.shouldDispatch(
            lastDispatch: last, now: tap5),
        isFalse,
      );
    });
  });
}
