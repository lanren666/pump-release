import 'package:flutter/material.dart';

/// 全局语言管理器
/// 用于在运行时动态更新应用语言
class LocaleManager {
  static final LocaleManager _instance = LocaleManager._internal();

  factory LocaleManager() => _instance;

  LocaleManager._internal();

  final ValueNotifier<Locale?> localeNotifier = ValueNotifier<Locale?>(null);

  /// 更新语言
  void updateLocale(String languageCode) {
    if (languageCode == 'zh') {
      localeNotifier.value = const Locale('zh', 'CN');
    } else {
      localeNotifier.value = const Locale('en', 'US');
    }
  }
}
