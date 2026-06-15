import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pump/config/locale_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocaleManager.resolveLocale', () {
    test('maps zh language code to zh_CN', () {
      expect(
        LocaleManager.resolveLocale(const Locale('zh', 'CN')),
        const Locale('zh', 'CN'),
      );
    });

    test('maps en language code to en_US', () {
      expect(
        LocaleManager.resolveLocale(const Locale('en', 'GB')),
        const Locale('en', 'US'),
      );
    });

    test('falls back to en_US for unsupported language', () {
      expect(
        LocaleManager.resolveLocale(const Locale('fr')),
        const Locale('en', 'US'),
      );
    });
  });

  group('LocaleManager.resolveLocaleFromPreferredList', () {
    test('prefers first matching locale in preferred list', () {
      expect(
        LocaleManager.resolveLocaleFromPreferredList(const [
          Locale('fr'),
          Locale('zh', 'CN'),
        ]),
        const Locale('zh', 'CN'),
      );
    });
  });
}
