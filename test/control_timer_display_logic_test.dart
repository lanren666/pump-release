import 'package:flutter_test/flutter_test.dart';
import 'package:pump/pages/control_timer_display_logic.dart';

void main() {
  group('ControlTimerDisplayLogic', () {
    group('useBothUnifiedRules', () {
      test('true when Both selected and not in individual mode', () {
        expect(
          ControlTimerDisplayLogic.useBothUnifiedRules(
            isBothSelected: true,
            isIndividualMode: false,
          ),
          isTrue,
        );
      });

      test('false when in individual mode', () {
        expect(
          ControlTimerDisplayLogic.useBothUnifiedRules(
            isBothSelected: true,
            isIndividualMode: true,
          ),
          isFalse,
        );
      });

      test('false when Left or Right selected', () {
        expect(
          ControlTimerDisplayLogic.useBothUnifiedRules(
            isBothSelected: false,
            isIndividualMode: false,
          ),
          isFalse,
        );
      });
    });

    group('bothRunningTogether', () {
      test('requires both sides started', () {
        expect(
          ControlTimerDisplayLogic.bothRunningTogether(
            leftHasStarted: true,
            rightHasStarted: true,
          ),
          isTrue,
        );
        expect(
          ControlTimerDisplayLogic.bothRunningTogether(
            leftHasStarted: true,
            rightHasStarted: false,
          ),
          isFalse,
        );
        expect(
          ControlTimerDisplayLogic.bothRunningTogether(
            leftHasStarted: false,
            rightHasStarted: true,
          ),
          isFalse,
        );
      });
    });

    group('timerDisplayHasStarted', () {
      test('Both unified + both started → show timer', () {
        expect(
          ControlTimerDisplayLogic.timerDisplayHasStarted(
            useBothUnifiedRules: true,
            leftHasStarted: true,
            rightHasStarted: true,
            singleSideHasStarted: true,
          ),
          isTrue,
        );
      });

      test('sequential Both start with only left up → hide timer', () {
        expect(
          ControlTimerDisplayLogic.timerDisplayHasStarted(
            useBothUnifiedRules: true,
            leftHasStarted: true,
            rightHasStarted: false,
            singleSideHasStarted: true,
            bothStartInProgress: true,
          ),
          isFalse,
        );
      });

      test('mid-session one side dropped → keep showing timer', () {
        expect(
          ControlTimerDisplayLogic.timerDisplayHasStarted(
            useBothUnifiedRules: true,
            leftHasStarted: true,
            rightHasStarted: false,
            singleSideHasStarted: true,
            bothStartInProgress: false,
          ),
          isTrue,
        );
        expect(
          ControlTimerDisplayLogic.timerDisplayHasStarted(
            useBothUnifiedRules: true,
            leftHasStarted: false,
            rightHasStarted: true,
            singleSideHasStarted: true,
          ),
          isTrue,
        );
      });

      test('Both idle (neither started) → hide timer', () {
        expect(
          ControlTimerDisplayLogic.timerDisplayHasStarted(
            useBothUnifiedRules: true,
            leftHasStarted: false,
            rightHasStarted: false,
            singleSideHasStarted: false,
          ),
          isFalse,
        );
      });

      test('single-side mode uses singleSideHasStarted', () {
        expect(
          ControlTimerDisplayLogic.timerDisplayHasStarted(
            useBothUnifiedRules: false,
            leftHasStarted: false,
            rightHasStarted: false,
            singleSideHasStarted: true,
          ),
          isTrue,
        );
      });
    });

    group('useLeftTimeForBothDisplay', () {
      test('both started → prefer left', () {
        expect(
          ControlTimerDisplayLogic.useLeftTimeForBothDisplay(
            leftHasStarted: true,
            rightHasStarted: true,
          ),
          isTrue,
        );
      });

      test('only right started → use right so elapsed time stays visible', () {
        expect(
          ControlTimerDisplayLogic.useLeftTimeForBothDisplay(
            leftHasStarted: false,
            rightHasStarted: true,
          ),
          isFalse,
        );
      });

      test('only left started → use left', () {
        expect(
          ControlTimerDisplayLogic.useLeftTimeForBothDisplay(
            leftHasStarted: true,
            rightHasStarted: false,
          ),
          isTrue,
        );
      });

      test('neither started → default to left (idle Both card)', () {
        expect(
          ControlTimerDisplayLogic.useLeftTimeForBothDisplay(
            leftHasStarted: false,
            rightHasStarted: false,
          ),
          isTrue,
        );
      });
    });

    group('timerInitialStateUsesLeftDevice', () {
      test('Both and Left use left device initial state', () {
        expect(
          ControlTimerDisplayLogic.timerInitialStateUsesLeftDevice(
            isLeftSelected: true,
            isBothSelected: false,
          ),
          isTrue,
        );
        expect(
          ControlTimerDisplayLogic.timerInitialStateUsesLeftDevice(
            isLeftSelected: false,
            isBothSelected: true,
          ),
          isTrue,
        );
      });

      test('Right uses right device initial state', () {
        expect(
          ControlTimerDisplayLogic.timerInitialStateUsesLeftDevice(
            isLeftSelected: false,
            isBothSelected: false,
          ),
          isFalse,
        );
      });
    });
  });
}
