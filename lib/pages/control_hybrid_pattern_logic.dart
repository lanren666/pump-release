import 'control_types.dart';

/// Which hybrid DB keys to persist after a user toggle.
class HybridPatternPersistPlan {
  const HybridPatternPersistPlan({
    required this.persistLeft,
    required this.persistRight,
  });

  final bool persistLeft;
  final bool persistRight;
}

/// Which devices should receive a hybrid DP after a user toggle.
class HybridPatternPublishPlan {
  const HybridPatternPublishPlan({
    required this.publishLeft,
    required this.publishRight,
  });

  final bool publishLeft;
  final bool publishRight;
}

/// Pure helpers for bilateral vs single-side hybrid pattern updates.
class ControlHybridPatternLogic {
  const ControlHybridPatternLogic._();

  /// In-memory hybrid flags after applying [value] for [selectedPump].
  static ({bool left, bool right}) stateAfterChange({
    required PumpSelection selectedPump,
    required bool leftEnabled,
    required bool rightEnabled,
    required bool value,
  }) {
    switch (selectedPump) {
      case PumpSelection.left:
        return (left: value, right: rightEnabled);
      case PumpSelection.right:
        return (left: leftEnabled, right: value);
      case PumpSelection.both:
        return (left: value, right: value);
    }
  }

  static HybridPatternPersistPlan persistPlan(PumpSelection selectedPump) {
    switch (selectedPump) {
      case PumpSelection.left:
        return const HybridPatternPersistPlan(
          persistLeft: true,
          persistRight: false,
        );
      case PumpSelection.right:
        return const HybridPatternPersistPlan(
          persistLeft: false,
          persistRight: true,
        );
      case PumpSelection.both:
        return const HybridPatternPersistPlan(
          persistLeft: true,
          persistRight: true,
        );
    }
  }

  static HybridPatternPublishPlan publishPlan({
    required PumpSelection selectedPump,
    required bool sessionHasStarted,
  }) {
    if (!sessionHasStarted) {
      return const HybridPatternPublishPlan(
        publishLeft: false,
        publishRight: false,
      );
    }
    switch (selectedPump) {
      case PumpSelection.left:
        return const HybridPatternPublishPlan(
          publishLeft: true,
          publishRight: false,
        );
      case PumpSelection.right:
        return const HybridPatternPublishPlan(
          publishLeft: false,
          publishRight: true,
        );
      case PumpSelection.both:
        return const HybridPatternPublishPlan(
          publishLeft: true,
          publishRight: true,
        );
    }
  }

  /// Unified bilateral timer/switch display follows the left flag once synced.
  static bool displayValueForBoth({
    required bool leftEnabled,
    required bool rightEnabled,
  }) {
    return leftEnabled;
  }
}
