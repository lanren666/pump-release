import 'package:flutter_test/flutter_test.dart';
import 'package:pump/pages/control_types.dart';
import 'package:pump/pages/custom_flow_config.dart';
import 'package:pump/pages/timer_display_cache_logic.dart';

void main() {
  // ---------------------------------------------------------------------------
  // totalPhases
  // ---------------------------------------------------------------------------
  group('TimerDisplayCacheLogic.totalPhases', () {
    final threePhaseCache = [
      Phase(mode: PhaseMode.stimulation, duration: 5),
      Phase(mode: PhaseMode.expression, duration: 10),
      Phase(mode: PhaseMode.stimulation, duration: 5),
    ];

    test('non-custom modes always return 2, ignoring cache', () {
      for (final mode in [
        SessionMode.defaultMode,
        SessionMode.beginner,
        SessionMode.boostMilk,
      ]) {
        expect(
          TimerDisplayCacheLogic.totalPhases(
            sessionMode: mode,
            cachedCustomPhases: threePhaseCache,
          ),
          2,
          reason: '$mode should always be 2',
        );
      }
    });

    test('custom mode returns cached phase count', () {
      expect(
        TimerDisplayCacheLogic.totalPhases(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: threePhaseCache,
        ),
        3,
      );
    });

    test('custom mode with 2-phase cache returns 2', () {
      expect(
        TimerDisplayCacheLogic.totalPhases(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: [
            Phase(mode: PhaseMode.stimulation, duration: 2),
            Phase(mode: PhaseMode.expression, duration: 15),
          ],
        ),
        2,
      );
    });

    test('custom mode with 4-phase cache returns 4', () {
      expect(
        TimerDisplayCacheLogic.totalPhases(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: List.generate(
            4,
            (_) => Phase(mode: PhaseMode.stimulation, duration: 5),
          ),
        ),
        4,
      );
    });

    test('custom mode falls back to 2 when cache is empty', () {
      expect(
        TimerDisplayCacheLogic.totalPhases(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: [],
        ),
        2,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // firstPhaseMode
  // ---------------------------------------------------------------------------
  group('TimerDisplayCacheLogic.firstPhaseMode', () {
    test('non-custom modes always return stimulation, ignoring first phase', () {
      final expressionFirstCache = [
        Phase(mode: PhaseMode.expression, duration: 10),
        Phase(mode: PhaseMode.stimulation, duration: 5),
      ];
      for (final mode in [
        SessionMode.defaultMode,
        SessionMode.beginner,
        SessionMode.boostMilk,
      ]) {
        expect(
          TimerDisplayCacheLogic.firstPhaseMode(
            sessionMode: mode,
            cachedCustomPhases: expressionFirstCache,
          ),
          IntensityMode.stimulation,
          reason: '$mode should always return stimulation',
        );
      }
    });

    test('custom mode: stimulation first → stimulation', () {
      expect(
        TimerDisplayCacheLogic.firstPhaseMode(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: [
            Phase(mode: PhaseMode.stimulation, duration: 2),
            Phase(mode: PhaseMode.expression, duration: 15),
          ],
        ),
        IntensityMode.stimulation,
      );
    });

    test('custom mode: expression first → expression', () {
      expect(
        TimerDisplayCacheLogic.firstPhaseMode(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: [
            Phase(mode: PhaseMode.expression, duration: 5),
            Phase(mode: PhaseMode.stimulation, duration: 10),
          ],
        ),
        IntensityMode.expression,
      );
    });

    test('custom mode: empty cache falls back to stimulation', () {
      expect(
        TimerDisplayCacheLogic.firstPhaseMode(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: [],
        ),
        IntensityMode.stimulation,
      );
    });

    test('custom mode: single expression phase', () {
      expect(
        TimerDisplayCacheLogic.firstPhaseMode(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: [Phase(mode: PhaseMode.expression, duration: 20)],
        ),
        IntensityMode.expression,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // initialPhaseDuration
  // ---------------------------------------------------------------------------
  group('TimerDisplayCacheLogic.initialPhaseDuration', () {
    test('non-custom modes always return 2 minutes', () {
      for (final mode in [
        SessionMode.defaultMode,
        SessionMode.beginner,
        SessionMode.boostMilk,
      ]) {
        expect(
          TimerDisplayCacheLogic.initialPhaseDuration(
            sessionMode: mode,
            cachedCustomPhases: [],
          ),
          const Duration(minutes: 2),
          reason: '$mode should return 2 minutes',
        );
      }
    });

    test('custom mode returns first phase duration from cache', () {
      expect(
        TimerDisplayCacheLogic.initialPhaseDuration(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: [
            Phase(mode: PhaseMode.stimulation, duration: 7),
            Phase(mode: PhaseMode.expression, duration: 15),
          ],
        ),
        const Duration(minutes: 7),
      );
    });

    test('custom mode uses first phase duration, not second', () {
      expect(
        TimerDisplayCacheLogic.initialPhaseDuration(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: [
            Phase(mode: PhaseMode.stimulation, duration: 3),
            Phase(mode: PhaseMode.expression, duration: 20),
          ],
        ),
        const Duration(minutes: 3),
      );
    });

    test('custom mode: minimum valid duration (1 minute)', () {
      expect(
        TimerDisplayCacheLogic.initialPhaseDuration(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: [Phase(mode: PhaseMode.stimulation, duration: 1)],
        ),
        const Duration(minutes: 1),
      );
    });

    test('custom mode: maximum valid duration (30 minutes)', () {
      expect(
        TimerDisplayCacheLogic.initialPhaseDuration(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: [Phase(mode: PhaseMode.stimulation, duration: 30)],
        ),
        const Duration(minutes: 30),
      );
    });

    test('custom mode: empty cache falls back to 2 minutes', () {
      expect(
        TimerDisplayCacheLogic.initialPhaseDuration(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: [],
        ),
        const Duration(minutes: 2),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // isCacheReady
  // ---------------------------------------------------------------------------
  group('TimerDisplayCacheLogic.isCacheReady', () {
    final somePhases = [
      Phase(mode: PhaseMode.stimulation, duration: 2),
      Phase(mode: PhaseMode.expression, duration: 15),
    ];

    test('non-custom modes are always ready, even with empty cache', () {
      for (final mode in [
        SessionMode.defaultMode,
        SessionMode.beginner,
        SessionMode.boostMilk,
      ]) {
        expect(
          TimerDisplayCacheLogic.isCacheReady(
            sessionMode: mode,
            cachedCustomPhases: [],
          ),
          isTrue,
          reason: '$mode should be ready without cache',
        );
      }
    });

    test('custom mode with empty cache is NOT ready', () {
      expect(
        TimerDisplayCacheLogic.isCacheReady(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: [],
        ),
        isFalse,
      );
    });

    test('custom mode with loaded cache is ready', () {
      expect(
        TimerDisplayCacheLogic.isCacheReady(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: somePhases,
        ),
        isTrue,
      );
    });

    test('custom mode: single-phase cache is ready', () {
      expect(
        TimerDisplayCacheLogic.isCacheReady(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: [Phase(mode: PhaseMode.stimulation, duration: 5)],
        ),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 一致性：三个函数的返回值对 defaultCustomPhases 一致
  // ---------------------------------------------------------------------------
  group('consistency with CustomFlowConfig.defaultCustomPhases', () {
    final defaults = CustomFlowConfig.defaultCustomPhases;

    test('totalPhases matches default phase list length', () {
      expect(
        TimerDisplayCacheLogic.totalPhases(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: defaults,
        ),
        defaults.length,
      );
    });

    test('firstPhaseMode matches default first phase', () {
      final expected = defaults.first.mode == PhaseMode.stimulation
          ? IntensityMode.stimulation
          : IntensityMode.expression;
      expect(
        TimerDisplayCacheLogic.firstPhaseMode(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: defaults,
        ),
        expected,
      );
    });

    test('initialPhaseDuration matches default first phase duration', () {
      expect(
        TimerDisplayCacheLogic.initialPhaseDuration(
          sessionMode: SessionMode.custom,
          cachedCustomPhases: defaults,
        ),
        Duration(minutes: defaults.first.duration),
      );
    });
  });
}
