import 'package:flutter_test/flutter_test.dart';
import 'package:pump/pages/control_start_reset_logic.dart';

void main() {
  group('ControlStartResetLogic', () {
    group('shouldResetElapsedTimeOnStart', () {
      // -----------------------------------------------------------------------
      // 正常场景 Normal scenarios
      // -----------------------------------------------------------------------

      test('停止后重新启动 → 需要清零 (false, false) → true', () {
        expect(
          ControlStartResetLogic.shouldResetElapsedTimeOnStart(
            currentHasStarted: false,
            currentIsRunning: false,
          ),
          isTrue,
          reason: '用户按了停止(hasStarted=false, isRunning=false)后按启动，'
              '计时应从0开始，不应显示上次的残留时间',
        );
      });

      test('暂停后恢复 → 不应清零 (true, false) → false', () {
        expect(
          ControlStartResetLogic.shouldResetElapsedTimeOnStart(
            currentHasStarted: true,
            currentIsRunning: false,
          ),
          isFalse,
          reason: '用户按了暂停(hasStarted=true, isRunning=false)后按继续，'
              '计时必须从暂停位置继续，不能清零',
        );
      });

      // -----------------------------------------------------------------------
      // 异常 / 边界场景 Edge / abnormal scenarios
      // -----------------------------------------------------------------------

      test('运行中状态 → 不应清零 (true, true) → false', () {
        // 运行中时Start按钮显示暂停逻辑，此分支不应被进入；
        // 传入此组合时防御性返回false，确保不意外清零。
        expect(
          ControlStartResetLogic.shouldResetElapsedTimeOnStart(
            currentHasStarted: true,
            currentIsRunning: true,
          ),
          isFalse,
          reason: '设备运行中时不应触发清零',
        );
      });

      test('异常状态 hasStarted=false 但 isRunning=true → 不应清零 (false, true) → false', () {
        // 理论上不应出现：未标记已启动但设备报告运行中。
        // 防御性返回false，避免在此未知状态下意外清零计时。
        expect(
          ControlStartResetLogic.shouldResetElapsedTimeOnStart(
            currentHasStarted: false,
            currentIsRunning: true,
          ),
          isFalse,
          reason: '未知/异常状态下保守处理，不清零',
        );
      });

      // -----------------------------------------------------------------------
      // 反向验证：只有 (false, false) 才返回 true
      // -----------------------------------------------------------------------

      test('只有 (false, false) 返回 true，其余三种组合均返回 false', () {
        final cases = [
          (hasStarted: false, isRunning: false, expected: true),
          (hasStarted: true, isRunning: false, expected: false),
          (hasStarted: true, isRunning: true, expected: false),
          (hasStarted: false, isRunning: true, expected: false),
        ];

        for (final c in cases) {
          expect(
            ControlStartResetLogic.shouldResetElapsedTimeOnStart(
              currentHasStarted: c.hasStarted,
              currentIsRunning: c.isRunning,
            ),
            c.expected,
            reason:
                'hasStarted=${c.hasStarted}, isRunning=${c.isRunning} → expected ${c.expected}',
          );
        }
      });
    });
  });
}
