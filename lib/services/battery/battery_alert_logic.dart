import '../../config/app_config.dart';

/// Pure helpers for low-battery alert decisions.
class BatteryAlertLogic {
  BatteryAlertLogic._();

  /// DP 104 level 1 = device red LED / critically low.
  static bool isLowBatteryLevel(int battery) => battery == 1;

  /// Bat_Volt below threshold → less than a full session (~20 min placeholder).
  static bool isBatVoltInsufficientForFullSession(int? batVolt) {
    if (batVolt == null) return false;
    return batVolt < AppConfig.batVoltLowSessionThreshold;
  }

  /// Session ended: was running, now stopped (not paused).
  ///
  /// [expectedIsRunning] from pending user action: 0=stop, 1=run, 2=pause.
  static bool isSessionEndedTransition({
    required bool wasRunning,
    required int newIsRunning,
    required bool hadStarted,
    required int? expectedIsRunning,
  }) {
    if (!hadStarted || !wasRunning) return false;
    if (newIsRunning != 0) return false;
    if (expectedIsRunning == 2) return false;
    return true;
  }
}
