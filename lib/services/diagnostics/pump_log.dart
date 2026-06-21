import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';

/// Console log levels via `--dart-define=PUMP_LOG_LEVEL=info|debug`.
///
/// Example:
/// ```bash
/// flutter run -d DEVICE --dart-define=INTERNAL_DIAGNOSTICS=true --dart-define=PUMP_LOG_LEVEL=info
/// ```
class PumpLog {
  PumpLog._();

  static bool get isDebugEnabled =>
      AppConfig.pumpLogLevel.toLowerCase() == 'debug' ||
      AppConfig.verbosePumpLogs;

  static void i(String tag, String message) {
    debugPrint('[INFO][$tag] $message');
  }

  static void d(String tag, String message) {
    if (!isDebugEnabled) return;
    debugPrint('[DEBUG][$tag] $message');
  }

  static void w(String tag, String message) {
    debugPrint('[WARN][$tag] $message');
  }

  static void e(String tag, String message) {
    debugPrint('[ERROR][$tag] $message');
  }
}
