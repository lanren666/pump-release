import 'package:flutter_test/flutter_test.dart';
import 'package:pump/pages/control_navigation_resume_logic.dart';
import 'package:pump/pages/control_types.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // restoreHasStarted
  // ─────────────────────────────────────────────────────────────────────────
  group('restoreHasStarted', () {
    // ── 正常场景 ──────────────────────────────────────────────────────────

    test('双侧都在运行 → 两侧 hasStarted 均置为 true（修复 Both 模式导航返回后切单侧的 bug）', () {
      final result = ControlNavigationResumeLogic.restoreHasStarted(
        leftRunning: true,
        rightRunning: true,
        leftHasStarted: false,
        rightHasStarted: false,
      );
      expect(result.left, isTrue);
      expect(result.right, isTrue);
    });

    test('双侧都在运行且 hasStarted 已经为 true → 保持 true（幂等）', () {
      final result = ControlNavigationResumeLogic.restoreHasStarted(
        leftRunning: true,
        rightRunning: true,
        leftHasStarted: true,
        rightHasStarted: true,
      );
      expect(result.left, isTrue);
      expect(result.right, isTrue);
    });

    test('双侧都未运行 → hasStarted 均不变（维持 false）', () {
      final result = ControlNavigationResumeLogic.restoreHasStarted(
        leftRunning: false,
        rightRunning: false,
        leftHasStarted: false,
        rightHasStarted: false,
      );
      expect(result.left, isFalse);
      expect(result.right, isFalse);
    });

    // ── 关键边界：单侧运行时不触发恢复，保留原自动切换行为 ──────────────

    test('只有左侧在运行 → hasStarted 均保持原值（允许 DP 自动切到单侧左）', () {
      final result = ControlNavigationResumeLogic.restoreHasStarted(
        leftRunning: true,
        rightRunning: false,
        leftHasStarted: false,
        rightHasStarted: false,
      );
      expect(result.left, isFalse);
      expect(result.right, isFalse);
    });

    test('只有右侧在运行 → hasStarted 均保持原值（允许 DP 自动切到单侧右）', () {
      final result = ControlNavigationResumeLogic.restoreHasStarted(
        leftRunning: false,
        rightRunning: true,
        leftHasStarted: false,
        rightHasStarted: false,
      );
      expect(result.left, isFalse);
      expect(result.right, isFalse);
    });

    // ── 异常场景：DB 数据与已有内存状态混合 ─────────────────────────────

    test('双侧运行、左侧 hasStarted 已为 true → 右侧也被置为 true，左侧不变', () {
      final result = ControlNavigationResumeLogic.restoreHasStarted(
        leftRunning: true,
        rightRunning: true,
        leftHasStarted: true,
        rightHasStarted: false,
      );
      expect(result.left, isTrue);
      expect(result.right, isTrue);
    });

    test('单侧运行但 hasStarted 已为 true（旧会话残留）→ 不改变', () {
      final result = ControlNavigationResumeLogic.restoreHasStarted(
        leftRunning: true,
        rightRunning: false,
        leftHasStarted: true,
        rightHasStarted: false,
      );
      expect(result.left, isTrue);
      expect(result.right, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // getCurrentHasStarted
  // ─────────────────────────────────────────────────────────────────────────
  group('getCurrentHasStarted', () {
    test('left 模式：只看 leftHasStarted', () {
      expect(
        ControlNavigationResumeLogic.getCurrentHasStarted(
          selectedPump: PumpSelection.left,
          leftHasStarted: true,
          rightHasStarted: false,
        ),
        isTrue,
      );
      expect(
        ControlNavigationResumeLogic.getCurrentHasStarted(
          selectedPump: PumpSelection.left,
          leftHasStarted: false,
          rightHasStarted: true,
        ),
        isFalse,
      );
    });

    test('right 模式：只看 rightHasStarted', () {
      expect(
        ControlNavigationResumeLogic.getCurrentHasStarted(
          selectedPump: PumpSelection.right,
          leftHasStarted: false,
          rightHasStarted: true,
        ),
        isTrue,
      );
      expect(
        ControlNavigationResumeLogic.getCurrentHasStarted(
          selectedPump: PumpSelection.right,
          leftHasStarted: true,
          rightHasStarted: false,
        ),
        isFalse,
      );
    });

    test('both 模式：任意一侧为 true 即返回 true', () {
      expect(
        ControlNavigationResumeLogic.getCurrentHasStarted(
          selectedPump: PumpSelection.both,
          leftHasStarted: true,
          rightHasStarted: false,
        ),
        isTrue,
      );
      expect(
        ControlNavigationResumeLogic.getCurrentHasStarted(
          selectedPump: PumpSelection.both,
          leftHasStarted: false,
          rightHasStarted: true,
        ),
        isTrue,
      );
      expect(
        ControlNavigationResumeLogic.getCurrentHasStarted(
          selectedPump: PumpSelection.both,
          leftHasStarted: true,
          rightHasStarted: true,
        ),
        isTrue,
      );
      expect(
        ControlNavigationResumeLogic.getCurrentHasStarted(
          selectedPump: PumpSelection.both,
          leftHasStarted: false,
          rightHasStarted: false,
        ),
        isFalse,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // shouldUpdateOnDp105
  // ─────────────────────────────────────────────────────────────────────────
  group('shouldUpdateOnDp105', () {
    test('appIsRunning=true → shouldUpdate=true', () {
      expect(
        ControlNavigationResumeLogic.shouldUpdateOnDp105(
          appIsRunning: true,
          isIndividualMode: false,
        ),
        isTrue,
      );
    });

    test('独立模式=true → shouldUpdate=true（即使 appIsRunning=false）', () {
      expect(
        ControlNavigationResumeLogic.shouldUpdateOnDp105(
          appIsRunning: false,
          isIndividualMode: true,
        ),
        isTrue,
      );
    });

    test('两者均为 false → shouldUpdate=false（触发自动切换路径）', () {
      expect(
        ControlNavigationResumeLogic.shouldUpdateOnDp105(
          appIsRunning: false,
          isIndividualMode: false,
        ),
        isFalse,
      );
    });

    test('两者均为 true → shouldUpdate=true', () {
      expect(
        ControlNavigationResumeLogic.shouldUpdateOnDp105(
          appIsRunning: true,
          isIndividualMode: true,
        ),
        isTrue,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // shouldSafeUpdateBothMode
  // ─────────────────────────────────────────────────────────────────────────
  group('shouldSafeUpdateBothMode', () {
    test('selectedPump=both + bothStartInProgress → safe update（不切 tab）', () {
      expect(
        ControlNavigationResumeLogic.shouldSafeUpdateBothMode(
          selectedPump: PumpSelection.both,
          bothStartInProgress: true,
          leftHasStarted: false,
          rightHasStarted: false,
        ),
        isTrue,
      );
    });

    test('selectedPump=both + leftHasStarted=true → safe update', () {
      expect(
        ControlNavigationResumeLogic.shouldSafeUpdateBothMode(
          selectedPump: PumpSelection.both,
          bothStartInProgress: false,
          leftHasStarted: true,
          rightHasStarted: false,
        ),
        isTrue,
      );
    });

    test('selectedPump=both + rightHasStarted=true → safe update', () {
      expect(
        ControlNavigationResumeLogic.shouldSafeUpdateBothMode(
          selectedPump: PumpSelection.both,
          bothStartInProgress: false,
          leftHasStarted: false,
          rightHasStarted: true,
        ),
        isTrue,
      );
    });

    test('selectedPump=both + 所有标志均 false → 允许自动切换（硬件手动启动）', () {
      expect(
        ControlNavigationResumeLogic.shouldSafeUpdateBothMode(
          selectedPump: PumpSelection.both,
          bothStartInProgress: false,
          leftHasStarted: false,
          rightHasStarted: false,
        ),
        isFalse,
      );
    });

    test('selectedPump=left → 不触发 both safe update', () {
      expect(
        ControlNavigationResumeLogic.shouldSafeUpdateBothMode(
          selectedPump: PumpSelection.left,
          bothStartInProgress: false,
          leftHasStarted: true,
          rightHasStarted: true,
        ),
        isFalse,
      );
    });

    test('selectedPump=right → 不触发 both safe update', () {
      expect(
        ControlNavigationResumeLogic.shouldSafeUpdateBothMode(
          selectedPump: PumpSelection.right,
          bothStartInProgress: true,
          leftHasStarted: true,
          rightHasStarted: true,
        ),
        isFalse,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // shouldClearBatteryAlertFlag
  // ─────────────────────────────────────────────────────────────────────────
  group('shouldClearBatteryAlertFlag', () {
    test('左设备 + 左侧未开始 → 清除 flag（新会话）', () {
      expect(
        ControlNavigationResumeLogic.shouldClearBatteryAlertFlag(
          isLeftDevice: true,
          leftHasStarted: false,
          rightHasStarted: false,
        ),
        isTrue,
      );
    });

    test('左设备 + 左侧已开始 → 不清除 flag（会话进行中，防重叠弹窗）', () {
      expect(
        ControlNavigationResumeLogic.shouldClearBatteryAlertFlag(
          isLeftDevice: true,
          leftHasStarted: true,
          rightHasStarted: false,
        ),
        isFalse,
      );
    });

    test('右设备 + 右侧未开始 → 清除 flag', () {
      expect(
        ControlNavigationResumeLogic.shouldClearBatteryAlertFlag(
          isLeftDevice: false,
          leftHasStarted: false,
          rightHasStarted: false,
        ),
        isTrue,
      );
    });

    test('右设备 + 右侧已开始 → 不清除 flag', () {
      expect(
        ControlNavigationResumeLogic.shouldClearBatteryAlertFlag(
          isLeftDevice: false,
          leftHasStarted: false,
          rightHasStarted: true,
        ),
        isFalse,
      );
    });

    test('左设备 + 右侧已开始（不相关）→ 以左侧 hasStarted 为准，清除 flag', () {
      expect(
        ControlNavigationResumeLogic.shouldClearBatteryAlertFlag(
          isLeftDevice: true,
          leftHasStarted: false,
          rightHasStarted: true,
        ),
        isTrue,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 端到端场景模拟（组合多个 helper 验证完整流程）
  // ─────────────────────────────────────────────────────────────────────────
  group('端到端场景', () {
    /// 模拟 DP105 处理的完整决策链，返回最终 selectedPump（both/left/right）。
    PumpSelection simulateDp105(
      PumpSelection selectedPump, {
      required bool leftHasStartedAfterLoad,
      required bool rightHasStartedAfterLoad,
      required bool isIndividualMode,
      required bool bothStartInProgress,
      required bool isLeftDevice,
    }) {
      // step1: shouldUpdate
      final appIsRunning = ControlNavigationResumeLogic.getCurrentHasStarted(
        selectedPump: selectedPump,
        leftHasStarted: leftHasStartedAfterLoad,
        rightHasStarted: rightHasStartedAfterLoad,
      );
      final shouldUpdate = ControlNavigationResumeLogic.shouldUpdateOnDp105(
        appIsRunning: appIsRunning,
        isIndividualMode: isIndividualMode,
      );

      if (shouldUpdate) return selectedPump; // 正常更新，不切 tab

      // step2: safe-update guard for Both mode
      final safeUpdate = ControlNavigationResumeLogic.shouldSafeUpdateBothMode(
        selectedPump: selectedPump,
        bothStartInProgress: bothStartInProgress,
        leftHasStarted: leftHasStartedAfterLoad,
        rightHasStarted: rightHasStartedAfterLoad,
      );
      if (safeUpdate) return selectedPump; // safe update，不切 tab

      // step3: 硬件手动启动自动切换
      if (selectedPump == PumpSelection.both) {
        return isLeftDevice ? PumpSelection.left : PumpSelection.right;
      }
      return selectedPump;
    }

    test('【核心 bug】Both 模式双侧运行 → 导航返回 → DP 到来 → 保持 Both', () {
      // _loadDevices 恢复 hasStarted
      final loaded = ControlNavigationResumeLogic.restoreHasStarted(
        leftRunning: true,
        rightRunning: true,
        leftHasStarted: false,
        rightHasStarted: false,
      );

      final result = simulateDp105(
        PumpSelection.both,
        leftHasStartedAfterLoad: loaded.left,
        rightHasStartedAfterLoad: loaded.right,
        isIndividualMode: false,
        bothStartInProgress: false,
        isLeftDevice: true,
      );
      expect(result, PumpSelection.both);
    });

    test('Both 模式双侧运行 → 右侧 DP 到来 → 保持 Both', () {
      final loaded = ControlNavigationResumeLogic.restoreHasStarted(
        leftRunning: true,
        rightRunning: true,
        leftHasStarted: false,
        rightHasStarted: false,
      );

      final result = simulateDp105(
        PumpSelection.both,
        leftHasStartedAfterLoad: loaded.left,
        rightHasStartedAfterLoad: loaded.right,
        isIndividualMode: false,
        bothStartInProgress: false,
        isLeftDevice: false,
      );
      expect(result, PumpSelection.both);
    });

    test('单侧左运行 → 导航返回（新页面初始 both）→ DP 到来 → 自动切到 left', () {
      // 只有左侧运行时，restoreHasStarted 不恢复，保留原自动切换行为
      final loaded = ControlNavigationResumeLogic.restoreHasStarted(
        leftRunning: true,
        rightRunning: false,
        leftHasStarted: false,
        rightHasStarted: false,
      );

      final result = simulateDp105(
        PumpSelection.both, // 页面初始值
        leftHasStartedAfterLoad: loaded.left,
        rightHasStartedAfterLoad: loaded.right,
        isIndividualMode: false,
        bothStartInProgress: false,
        isLeftDevice: true,
      );
      expect(result, PumpSelection.left);
    });

    test('单侧右运行 → 导航返回 → DP 到来 → 自动切到 right', () {
      final loaded = ControlNavigationResumeLogic.restoreHasStarted(
        leftRunning: false,
        rightRunning: true,
        leftHasStarted: false,
        rightHasStarted: false,
      );

      final result = simulateDp105(
        PumpSelection.both,
        leftHasStartedAfterLoad: loaded.left,
        rightHasStartedAfterLoad: loaded.right,
        isIndividualMode: false,
        bothStartInProgress: false,
        isLeftDevice: false,
      );
      expect(result, PumpSelection.right);
    });

    test('双侧均未运行 → 导航返回 → 无 DP 到来时 selectedPump 仍为 both', () {
      // 不会有 DP105 isRunning=1 到来，selectedPump 初始值不变
      final loaded = ControlNavigationResumeLogic.restoreHasStarted(
        leftRunning: false,
        rightRunning: false,
        leftHasStarted: false,
        rightHasStarted: false,
      );
      expect(loaded.left, isFalse);
      expect(loaded.right, isFalse);
      // 没有 DP 到来，_selectedPump 保持初始值 PumpSelection.both，这里只验证 load 不污染状态
    });

    test('独立模式下即使 appIsRunning=false 也走正常更新路径', () {
      final result = simulateDp105(
        PumpSelection.left,
        leftHasStartedAfterLoad: false,
        rightHasStartedAfterLoad: false,
        isIndividualMode: true, // 独立模式
        bothStartInProgress: false,
        isLeftDevice: true,
      );
      expect(result, PumpSelection.left); // 不触发自动切换
    });

    test('Both 顺序启动中（bothStartInProgress=true）→ DP 到来 → 不自动切换', () {
      // shouldUpdate=false 但 bothStartInProgress=true → safe update
      final result = simulateDp105(
        PumpSelection.both,
        leftHasStartedAfterLoad: false,
        rightHasStartedAfterLoad: false,
        isIndividualMode: false,
        bothStartInProgress: true, // 正在顺序启动
        isLeftDevice: true,
      );
      expect(result, PumpSelection.both);
    });

    test('DB isRunning=true 但 hasStarted 已被恢复（幂等性）→ 保持 Both', () {
      // _loadDevices 被调用两次，第二次不应改变已恢复的状态
      final loaded1 = ControlNavigationResumeLogic.restoreHasStarted(
        leftRunning: true,
        rightRunning: true,
        leftHasStarted: false,
        rightHasStarted: false,
      );
      final loaded2 = ControlNavigationResumeLogic.restoreHasStarted(
        leftRunning: true,
        rightRunning: true,
        leftHasStarted: loaded1.left,
        rightHasStarted: loaded1.right,
      );
      expect(loaded2.left, isTrue);
      expect(loaded2.right, isTrue);
    });
  });
}
