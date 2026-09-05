import '../../models/connected_device.dart';

/// Resolves the ID passed to native BLE/Tuya SDK calls.
///
/// Prefer [ConnectedDevice.devId] when paired — avoids queryHomeList during
/// reconnect. [bluetoothId] (uuid) is only used before devId is known.
extension NativeBleDeviceId on ConnectedDevice {
  String get nativeBleId =>
      (devId != null && devId!.isNotEmpty) ? devId! : bluetoothId;
}

String nativeBleIdFor({required String bluetoothId, String? devId}) =>
    (devId != null && devId.isNotEmpty) ? devId : bluetoothId;

/// Payload for native connectBleDevices / online checks.
/// iOS reconnect uses bluetoothId + productKey; Android uses resolved devId.
Map<String, dynamic> nativeConnectBleArgs(List<ConnectedDevice> devices) {
  return {
    'deviceIds': devices.map((d) => d.nativeBleId).toList(),
    'bluetoothIds': {
      for (final device in devices) device.nativeBleId: device.bluetoothId,
    },
    'productKeys': {
      for (final device in devices)
        if (device.productKey != null && device.productKey!.isNotEmpty)
          device.nativeBleId: device.productKey,
    },
  };
}
