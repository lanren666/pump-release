/// Periodic reconnect decisions for remembered devices.
class DeviceReconnectPolicy {
  const DeviceReconnectPolicy._();

  /// DB says running but live BLE probe is offline — stale state after power-off.
  static bool isStaleRunningState({
    required bool isRunning,
    required bool isOnline,
  }) =>
      isRunning && !isOnline;

  /// Device is connected; only (re)register the native DP listener.
  static bool shouldRegisterListenerOnly({
    required bool isRunning,
    required bool isOnline,
  }) =>
      isRunning && isOnline;
}
