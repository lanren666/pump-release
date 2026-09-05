class ConnectedDevice {
  final int? id;
  final String bluetoothId; // 蓝牙标识：确定唯一设备
  final String? devId; // Tuya设备ID：配网后获取的devId
  final String name; // 名称：自定义名称
  final int battery; // 电量：1，2，3（单位格）
  final String position; // 位置：left/right
  final bool isRunning; // 运行中：是or否
  final bool isRemembered; // 是否已配网
  final String? productKey; // Tuya productId used by iOS connectBLE

  ConnectedDevice({
    this.id,
    required this.bluetoothId,
    this.devId,
    required this.name,
    this.battery = 0,
    this.position = 'left',
    this.isRunning = false,
    this.isRemembered = false,
    this.productKey,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bluetooth_id': bluetoothId,
      'dev_id': devId,
      'name': name,
      'battery': battery,
      'position': position,
      'is_running': isRunning ? 1 : 0,
      'is_remembered': isRemembered ? 1 : 0,
      'product_key': productKey ?? '',
    };
  }

  factory ConnectedDevice.fromMap(Map<String, dynamic> map) {
    final rawKey = map['product_key'] as String?;
    return ConnectedDevice(
      id: map['id'],
      bluetoothId: map['bluetooth_id'],
      devId: map['dev_id'],
      name: map['name'],
      battery: map['battery'],
      position: map['position'],
      isRunning: map['is_running'] == 1,
      isRemembered: map['is_remembered'] == 1,
      productKey: (rawKey != null && rawKey.isNotEmpty) ? rawKey : null,
    );
  }

  ConnectedDevice copyWith({
    int? id,
    String? bluetoothId,
    String? devId,
    String? name,
    int? battery,
    String? position,
    bool? isRunning,
    bool? isRemembered,
    String? productKey,
  }) {
    return ConnectedDevice(
      id: id ?? this.id,
      bluetoothId: bluetoothId ?? this.bluetoothId,
      devId: devId ?? this.devId,
      name: name ?? this.name,
      battery: battery ?? this.battery,
      position: position ?? this.position,
      isRunning: isRunning ?? this.isRunning,
      isRemembered: isRemembered ?? this.isRemembered,
      productKey: productKey ?? this.productKey,
    );
  }
}
