import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pump/l10n/app_localizations.dart';
import 'package:pump/pages/widgets/low_battery_dialog.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('connect warning shows charge and continue actions', (tester) async {
    await tester.pumpWidget(
      _wrap(const LowBatteryDialog(
        variant: LowBatteryDialogVariant.connectWarning,
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('Got it, go charge'), findsOneWidget);
    expect(find.text('Continue without charging'), findsOneWidget);
    expect(find.text('Got it'), findsNothing);
  });

  testWidgets('session complete shows single Got it button', (tester) async {
    await tester.pumpWidget(
      _wrap(const LowBatteryDialog(
        variant: LowBatteryDialogVariant.sessionComplete,
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('Continue without charging'), findsNothing);
  });
}
