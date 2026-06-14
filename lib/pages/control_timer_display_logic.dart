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
  }) {
    if (useBothUnifiedRules) {
      return bothRunningTogether(
        leftHasStarted: leftHasStarted,
        rightHasStarted: rightHasStarted,
      );
    }
    return singleSideHasStarted;
  }

  static bool timerInitialStateUsesLeftDevice({
    required bool isLeftSelected,
    required bool isBothSelected,
  }) {
    return isLeftSelected || isBothSelected;
  }
}
