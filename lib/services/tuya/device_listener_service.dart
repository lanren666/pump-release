import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';
import '../../config/ble_channels.dart';
import '../../models/connected_device.dart';
import 'native_ble_device_id.dart';

/// Ensures native DP delegates are registered so SessionStatus (DP 105) reaches Flutter.
class DeviceListenerService {
  const DeviceListenerService._();

  /// On iOS, [registerDeviceListener] expects bluetoothId (uuid), not Tuya devId.
  static Future<bool> registerIfRunning(
    ConnectedDevice device, {
    bool bypassOnlineCheck = false,
  }) async {
    if (!AppConfig.tuyaEnabled) return false;
    if (!device.isRunning) return false;
    if (device.bluetoothId.isEmpty) return false;

    try {
      if (!bypassOnlineCheck) {
        final isOnline =
            await connectionChannel.invokeMethod('isDeviceOnline', {
                  'deviceId': device.nativeBleId,
                })
                as bool? ??
            false;
        if (!isOnline) return false;
      }

      await connectionChannel.invokeMethod('registerDeviceListener', {
        'deviceId': device.nativeBleId,
      });
      debugPrint('✅ 设备监听器注册成功: ${device.nativeBleId}');
      return true;
    } catch (e) {
      debugPrint('注册设备监听器失败 (${device.bluetoothId}): $e');
      return false;
    }
  }

  static Future<void> registerAllRunning(Iterable<ConnectedDevice> devices) async {
    for (final device in devices) {
      await registerIfRunning(device);
    }
  }
}
