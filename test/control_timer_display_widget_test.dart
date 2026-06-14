import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pump/l10n/app_localizations.dart';
import 'package:pump/pages/control_types.dart';
import 'package:pump/pages/widgets/unified_timer_card.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnifiedTimerCard widget', () {
    testWidgets('shows idle timer and stimulation badge before start', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const UnifiedTimerCard(
            displayMode: IntensityMode.stimulation,
            displayMinutes: '00',
            displaySeconds: '00',
            currentPhase: 1,
            effectiveTotalPhases: 2,
            currentHasStarted: false,
            effectivePhaseDuration: Duration(minutes: 2),
            elapsedTimeInPhase: Duration.zero,
            maxDuration: 30,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unified_timer_card')), findsOneWidget);
      expect(find.byKey(const Key('unified_timer_main')), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('Stimulation'), findsOneWidget);
      expect(find.textContaining('Phase 1/2'), findsOneWidget);
      expect(find.textContaining('Max 30min'), findsOneWidget);
      expect(find.text('Left'), findsNothing);
      expect(find.text('Right'), findsNothing);
    });

    testWidgets('shows running elapsed time and phase progress', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const UnifiedTimerCard(
            displayMode: IntensityMode.expression,
            displayMinutes: '05',
            displaySeconds: '07',
            currentPhase: 2,
            effectiveTotalPhases: 2,
            currentHasStarted: true,
            effectivePhaseDuration: Duration(minutes: 15),
            elapsedTimeInPhase: Duration(minutes: 3, seconds: 12),
            maxDuration: 20,
            deviceMaxDuration: 30,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('05:07'), findsOneWidget);
      expect(find.text('Expression'), findsOneWidget);
      expect(find.textContaining('Phase 2/2: 03:12 / 15:00'), findsOneWidget);
      expect(find.textContaining('Max 30min'), findsOneWidget);
    });

    testWidgets('renders exactly one unified card (not dual side-by-side)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Row(
            children: [
              Expanded(
                child: UnifiedTimerCard(
                  displayMode: IntensityMode.stimulation,
                  displayMinutes: '00',
                  displaySeconds: '00',
                  currentPhase: 1,
                  effectiveTotalPhases: 2,
                  currentHasStarted: false,
                  effectivePhaseDuration: const Duration(minutes: 2),
                  elapsedTimeInPhase: Duration.zero,
                  maxDuration: 30,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unified_timer_card')), findsOneWidget);
      expect(find.byKey(const Key('unified_timer_main')), findsOneWidget);
    });
  });
}
