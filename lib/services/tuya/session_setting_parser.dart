import '../../config/app_config.dart';

/// Parses firmware session_setting (DP 101) hex payloads.
///
/// Bat_Volt is the last 2 bytes (big-endian), range 0–[AppConfig.batVoltMax].
class SessionSettingParser {
  SessionSettingParser._();

  /// Minimum hex length for Bat_Volt: 2 bytes → 4 hex chars.
  static const int _batVoltHexLength = 4;

  /// Extract Bat_Volt from a session_setting hex string.
  /// Returns null when the payload is missing or too short.
  static int? parseBatVolt(String? hex) {
    if (hex == null || hex.isEmpty) return null;

    final normalized = hex.trim().toUpperCase();
    if (normalized.length < _batVoltHexLength) return null;

    final batVoltHex = normalized.substring(normalized.length - _batVoltHexLength);
    if (!_isHex(batVoltHex)) return null;

    final value = int.parse(batVoltHex, radix: 16);
    return value.clamp(0, AppConfig.batVoltMax);
  }

  static bool _isHex(String s) {
    return RegExp(r'^[0-9A-F]+$').hasMatch(s);
  }
}
