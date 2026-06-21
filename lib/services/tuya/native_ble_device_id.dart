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
