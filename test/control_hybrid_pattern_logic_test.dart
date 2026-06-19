import 'package:flutter_test/flutter_test.dart';
import 'package:pump/pages/control_hybrid_pattern_logic.dart';
import 'package:pump/pages/control_types.dart';

void main() {
  group('ControlHybridPatternLogic', () {
    group('stateAfterChange', () {
      test('Both selection syncs left and right to the new value', () {
        expect(
          ControlHybridPatternLogic.stateAfterChange(
            selectedPump: PumpSelection.both,
            leftEnabled: false,
            rightEnabled: true,
            value: true,
          ),
          (left: true, right: true),
        );
        expect(
          ControlHybridPatternLogic.stateAfterChange(
            selectedPump: PumpSelection.both,
            leftEnabled: true,
            rightEnabled: true,
            value: false,
          ),
          (left: false, right: false),
        );
      });

      test('Left selection only updates left flag', () {
        expect(
          ControlHybridPatternLogic.stateAfterChange(
            selectedPump: PumpSelection.left,
            leftEnabled: false,
            rightEnabled: true,
            value: true,
          ),
          (left: true, right: true),
        );
      });

      test('Right selection only updates right flag', () {
        expect(
          ControlHybridPatternLogic.stateAfterChange(
            selectedPump: PumpSelection.right,
            leftEnabled: true,
            rightEnabled: false,
            value: true,
          ),
          (left: true, right: true),
        );
      });
    });

    group('persistPlan', () {
      test('Both persists both keys', () {
        final plan = ControlHybridPatternLogic.persistPlan(PumpSelection.both);
        expect(plan.persistLeft, isTrue);
        expect(plan.persistRight, isTrue);
      });

      test('Left persists only left key', () {
        final plan = ControlHybridPatternLogic.persistPlan(PumpSelection.left);
        expect(plan.persistLeft, isTrue);
        expect(plan.persistRight, isFalse);
      });

      test('Right persists only right key', () {
        final plan = ControlHybridPatternLogic.persistPlan(PumpSelection.right);
        expect(plan.persistLeft, isFalse);
        expect(plan.persistRight, isTrue);
      });
    });

    group('publishPlan', () {
      test('does not publish before session starts', () {
        final plan = ControlHybridPatternLogic.publishPlan(
          selectedPump: PumpSelection.both,
          sessionHasStarted: false,
        );
        expect(plan.publishLeft, isFalse);
        expect(plan.publishRight, isFalse);
      });

      test('Both publishes to both sides when session started', () {
        final plan = ControlHybridPatternLogic.publishPlan(
          selectedPump: PumpSelection.both,
          sessionHasStarted: true,
        );
        expect(plan.publishLeft, isTrue);
        expect(plan.publishRight, isTrue);
      });

      test('Left publishes only left when session started', () {
        final plan = ControlHybridPatternLogic.publishPlan(
          selectedPump: PumpSelection.left,
          sessionHasStarted: true,
        );
        expect(plan.publishLeft, isTrue);
        expect(plan.publishRight, isFalse);
      });

      test('Right publishes only right when session started', () {
        final plan = ControlHybridPatternLogic.publishPlan(
          selectedPump: PumpSelection.right,
          sessionHasStarted: true,
        );
        expect(plan.publishLeft, isFalse);
        expect(plan.publishRight, isTrue);
      });
    });

    group('displayValueForBoth', () {
      test('uses left flag for unified bilateral display', () {
        expect(
          ControlHybridPatternLogic.displayValueForBoth(
            leftEnabled: true,
            rightEnabled: false,
          ),
          isTrue,
        );
        expect(
          ControlHybridPatternLogic.displayValueForBoth(
            leftEnabled: false,
            rightEnabled: true,
          ),
          isFalse,
        );
      });
    });
  });
}
