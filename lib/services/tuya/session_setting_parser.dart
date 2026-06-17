import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';

/// Parses firmware session_setting (DP 101) hex payloads.
///
/// Bat_Volt is the last 2 bytes (big-endian), range 0–[AppConfig.batVoltMax].
class SessionSettingParser {
  SessionSettingParser._();

  /// Minimum hex length for Bat_Volt: 2 bytes → 4 hex chars.
  static const int _batVoltHexLength = 4;

  /// App push payload is 11 bytes (22 hex) without Bat_Volt; firmware report adds 2 bytes.
  static const int appPushHexLengthWithoutBatVolt = 22;

  /// Normalize raw DP 101 value to uppercase hex (no spaces).
  static String? normalizeHex(dynamic rawValue) {
    if (rawValue == null) return null;
    if (rawValue is String) {
      final trimmed = rawValue.trim().toUpperCase();
      return trimmed.isEmpty ? null : trimmed;
    }
    return rawValue.toString().trim().toUpperCase();
  }

  /// Extract Bat_Volt from a session_setting hex string.
  /// Returns null when the payload is missing or too short.
  static int? parseBatVolt(String? hex) {
    final normalized = normalizeHex(hex);
    if (normalized == null || normalized.length < _batVoltHexLength) {
      return null;
    }

    final batVoltHex = normalized.substring(normalized.length - _batVoltHexLength);
    if (!_isHex(batVoltHex)) return null;

    final value = int.parse(batVoltHex, radix: 16);
    return value.clamp(0, AppConfig.batVoltMax);
  }

  /// Log full DP 101 hex and parsed Bat_Volt for firmware/App debugging.
  static void logSessionSettingPayload({
    required String source,
    required String deviceId,
    required dynamic rawValue,
  }) {
    final hex = normalizeHex(rawValue);
    final batVolt = parseBatVolt(hex);
    final batVoltHex = hex != null && hex.length >= _batVoltHexLength
        ? hex.substring(hex.length - _batVoltHexLength)
        : null;
    final hasBatVoltField =
        hex != null && hex.length > appPushHexLengthWithoutBatVolt;

    debugPrint(
      '📋 DP101 sessionSetting [$source] deviceId=$deviceId '
      'rawType=${rawValue.runtimeType} '
      'hex=${hex ?? 'null'} '
      'hexLen=${hex?.length ?? 0} '
      'batVoltHex=$batVoltHex batVolt=$batVolt '
      'hasBatVoltField=$hasBatVoltField',
    );
  }

  static bool _isHex(String s) {
    return RegExp(r'^[0-9A-F]+$').hasMatch(s);
  }
}
