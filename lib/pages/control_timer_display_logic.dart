/// Pure helpers for control-page timer display rules (Both unified card).
class ControlTimerDisplayLogic {
  const ControlTimerDisplayLogic._();

  static bool useBothUnifiedRules({
    required bool isBothSelected,
    required bool isIndividualMode,
  }) {
    return isBothSelected && !isIndividualMode;
  }

  static bool bothRunningTogether({
    required bool leftHasStarted,
    required bool rightHasStarted,
  }) {
    return leftHasStarted && rightHasStarted;
  }

  static bool timerDisplayHasStarted({
    required bool useBothUnifiedRules,
    required bool leftHasStarted,
    required bool rightHasStarted,
    required bool singleSideHasStarted,
    bool bothStartInProgress = false,
  }) {
    if (useBothUnifiedRules) {
      // Sequential Both start: wait until both sides are up so the card
      // does not flash the first device's time.
      if (bothStartInProgress) {
        return bothRunningTogether(
          leftHasStarted: leftHasStarted,
          rightHasStarted: rightHasStarted,
        );
      }
      // Mid-session: keep showing time if either side is still in-session
      // (the other may have dropped over BLE).
      return leftHasStarted || rightHasStarted;
    }
    return singleSideHasStarted;
  }

  /// Both unified card prefers left time; falls back to right when left
  /// has dropped so the remaining side's elapsed time stays visible.
  static bool useLeftTimeForBothDisplay({
    required bool leftHasStarted,
    required bool rightHasStarted,
  }) {
    if (leftHasStarted) return true;
    if (rightHasStarted) return false;
    return true;
  }

  static bool timerInitialStateUsesLeftDevice({
    required bool isLeftSelected,
    required bool isBothSelected,
  }) {
    return isLeftSelected || isBothSelected;
  }
}
