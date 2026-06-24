import 'control_types.dart';
import 'custom_flow_config.dart';

/// Pure helpers for computing timer display values from cached state.
///
/// These functions replace async DB queries in _buildTimerDisplay so the
/// widget tree can be built synchronously on every frame.  The cache is
/// populated once in _loadCustomFlowDescription (called at init and after
/// every CustomFlowPage edit) and is always up-to-date.
class TimerDisplayCacheLogic {
  TimerDisplayCacheLogic._();

  /// Total phase count shown on the timer card.
  /// Non-custom modes are always 2; custom mode reads the cached phases.
  static int totalPhases({
    required SessionMode sessionMode,
    required List<Phase> cachedCustomPhases,
  }) {
    if (sessionMode == SessionMode.custom) {
      return cachedCustomPhases.isNotEmpty ? cachedCustomPhases.length : 2;
    }
    return 2;
  }

  /// Intensity mode of the first phase, shown before a session starts.
  /// Non-custom modes always begin with stimulation.
  static IntensityMode firstPhaseMode({
    required SessionMode sessionMode,
    required List<Phase> cachedCustomPhases,
  }) {
    if (sessionMode == SessionMode.custom && cachedCustomPhases.isNotEmpty) {
      return cachedCustomPhases.first.mode == PhaseMode.stimulation
          ? IntensityMode.stimulation
          : IntensityMode.expression;
    }
    return IntensityMode.stimulation;
  }

  /// Duration of the first phase, shown on the timer card before a session
  /// starts.  Custom mode reads the cached phases; all other modes use the
  /// fixed 2-minute starter phase.
  static Duration initialPhaseDuration({
    required SessionMode sessionMode,
    required List<Phase> cachedCustomPhases,
  }) {
    if (sessionMode == SessionMode.custom && cachedCustomPhases.isNotEmpty) {
      return Duration(minutes: cachedCustomPhases.first.duration);
    }
    return const Duration(minutes: 2);
  }
}
