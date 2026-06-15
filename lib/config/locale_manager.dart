import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

/// 全局语言管理器
/// 用于在运行时动态更新应用语言
class LocaleManager {
  static final LocaleManager _instance = LocaleManager._internal();

  factory LocaleManager() => _instance;

  LocaleManager._internal();

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en', 'US'),
    Locale('zh', 'CN'),
  ];

  final ValueNotifier<Locale?> localeNotifier = ValueNotifier<Locale?>(null);

  /// 将任意 [locale] 映射为应用支持的语言代码（`en` 或 `zh`）。
  static String languageCodeFor(Locale locale) {
    if (locale.languageCode.toLowerCase() == 'zh') {
      return 'zh';
    }
    return 'en';
  }

  /// 当前系统语言对应的应用语言代码。
  static String get systemLanguageCode =>
      languageCodeFor(PlatformDispatcher.instance.locale);

  /// 将应用语言代码转为 [Locale]。
  static Locale localeForLanguageCode(String languageCode) {
    if (languageCode == 'zh') {
      return const Locale('zh', 'CN');
    }
    return const Locale('en', 'US');
  }

  /// Match [preferred] against [supportedLocales] by language code.
  static Locale? _matchPreferredLocale(
    Iterable<Locale> preferred,
    Iterable<Locale> supported,
  ) {
    for (final candidate in preferred) {
      for (final supportedLocale in supported) {
        if (supportedLocale.languageCode == candidate.languageCode) {
          return supportedLocale;
        }
      }
    }
    return null;
  }

  /// Resolve from the platform preferred-locale list (system language order).
  static Locale resolveSystemLocale() {
    final platform = PlatformDispatcher.instance;
    final Locale? matched = _matchPreferredLocale(
      platform.locales,
      supportedLocales,
    );
    if (matched != null) {
      return matched;
    }
    return resolveLocale(platform.locale);
  }

  /// Resolve from an explicit preferred-locale list (e.g. [didChangeLocales]).
  static Locale resolveLocaleFromPreferredList(List<Locale>? preferredLocales) {
    if (preferredLocales != null && preferredLocales.isNotEmpty) {
      final Locale? matched = _matchPreferredLocale(
        preferredLocales,
        supportedLocales,
      );
      if (matched != null) {
        return matched;
      }
    }
    return resolveSystemLocale();
  }

  /// 根据设备/指定 [locale] 解析为 [supportedLocales] 中的一项。
  /// [locale] 为 `null` 时使用系统语言列表。
  static Locale resolveLocale(Locale? locale) {
    if (locale == null) {
      return resolveSystemLocale();
    }
    final Locale? matched = _matchPreferredLocale(
      <Locale>[locale],
      supportedLocales,
    );
    return matched ?? supportedLocales.first;
  }

  /// 更新语言（用户已在设置中明确选择并保存）
  void updateLocale(String languageCode) {
    localeNotifier.value = localeForLanguageCode(languageCode);
  }
}
