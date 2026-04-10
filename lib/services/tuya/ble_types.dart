// DP 数据点
class DpData {
  final String dpId; // 数据点ID
  final dynamic value; // 数据点值
  final int? timestamp; // 时间戳（可选）

  DpData({required this.dpId, required this.value, this.timestamp});

  Map<String, dynamic> toJson() {
    return {'dpId': dpId, 'value': value, 'timestamp': timestamp};
  }

  factory DpData.fromJson(Map<String, dynamic> json) {
    return DpData(
      dpId: json['dpId'] ?? '',
      value: json['value'],
      timestamp: json['timestamp'] as int?,
    );
  }
}

// DP 上报数据（设备上报给 App）
class DpReportData {
  final String deviceId; // 设备ID
  final List<DpData> dps; // 数据点列表
  final int timestamp; // 上报时间戳

  DpReportData({
    required this.deviceId,
    required this.dps,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'dps': dps.map((dp) => dp.toJson()).toList(),
      'timestamp': timestamp,
    };
  }

  factory DpReportData.fromJson(Map<String, dynamic> json) {
    return DpReportData(
      deviceId: json['deviceId'] ?? '',
      dps:
          (json['dps'] as List<dynamic>?)
              ?.map((e) => DpData.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      timestamp: json['timestamp'] ?? 0,
    );
  }
}
