class BluetoothDevice {
  final String bluetoothId;
  final String name;
  final int battery;
  final String uuid;
  final String productKey;
  String devId;

  BluetoothDevice({
    required this.bluetoothId,
    required this.name,
    required this.battery,
    required this.uuid,
    required this.productKey,
    this.devId = "",
  });
}
