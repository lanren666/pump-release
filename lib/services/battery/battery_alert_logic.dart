import '../../config/app_config.dart';

/// Pure helpers for low-battery alert decisions.
class BatteryAlertLogic {
  BatteryAlertLogic._();

  /// DP 104 level 1 = device red LED blink / critically low (<20 min).
  static bool isLowBatteryLevel(int battery) => battery == 1;

  /// Host red LED starts blinking when battery crosses into level 1.
  static bool isLowBatteryTransition({
    required int previousBattery,
    required int newBattery,
  }) {
    return !isLowBatteryLevel(previousBattery) && isLowBatteryLevel(newBattery);
  }

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
