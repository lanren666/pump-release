/// Pure helpers for routing DP 104 (batteryLevel) updates to the correct device side.
class BatteryDpRoutingLogic {
  BatteryDpRoutingLogic._();

  /// Returns which side ('left' or 'right') should receive a battery DP update,
  /// or null when [updateDeviceId] matches neither side (event should be ignored).
  ///
  /// [updatePosition] is the position stored in the DB for that device ('left'/'right').
  /// [updateDeviceId] is the Tuya devId reported by native.
  ///
  /// The `position == 'left' || isLeftDevice` guard makes devId and DB position
  /// consistent signals — both should agree in normal operation.
  static String? resolveUpdateSide({
    required String? leftDevId,
    required String? rightDevId,
    required String updateDeviceId,
    required String? updatePosition,
  }) {
    final isLeftDevice = leftDevId == updateDeviceId;
    final isRightDevice = rightDevId == updateDeviceId;
    if (!isLeftDevice && !isRightDevice) return null;
    final isLeft = updatePosition == 'left' || isLeftDevice;
    return isLeft ? 'left' : 'right';
  }

  /// Parses a raw DP 104 value to a battery level integer.
  /// Returns null when the value cannot be parsed; callers should skip the update.
  static int? parseBatteryValue(dynamic dpValue) {
    if (dpValue is int) return dpValue;
    return int.tryParse(dpValue.toString());
  }
}
