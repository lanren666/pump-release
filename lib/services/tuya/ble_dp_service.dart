import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pump/config/app_config.dart';
import 'ble_types.dart';
import 'dp_constants.dart';
import '../../services/database_service.dart';

// BLE DP 相关操作
class BleDpService {
  static const MethodChannel _methodChannel = MethodChannel(
    'com.sporramom/ble_dp',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.sporramom/ble_dp_events',
  );

  static StreamSubscription<dynamic>? _dpSubscription;
  static final StreamController<DpReportData> _dpReportController =
      StreamController<DpReportData>.broadcast();
  static final DatabaseService _dbService = DatabaseService();

  // 下发 DP 数据点
  static Future<bool> publishDps(
    String deviceId,
    List<DpData> dps, {
    int timeout = 10,
  }) async {
    if (!AppConfig.tuyaEnabled) {
      debugPrint(
        '⚠️ 涂鸦功能已禁用，跳过下发DP $deviceId, dps: ${dps.map((dp) => dp.toJson()).toList()}',
      );
      return true;
    }

    try {
      // 其实deviceId 给的是蓝牙id
      // 但是这里需要转换成devId
      final device = await _dbService.getDeviceByBluetoothId(deviceId);
      if (device == null) {
        debugPrint('⚠️ 设备未找到 $deviceId');
        throw Exception('Device not found');
      }

      final result = await _methodChannel.invokeMethod('publishDps', {
        'deviceId': device.devId,
        'dps': dps.map((dp) => dp.toJson()).toList(),
        'timeout': timeout,
      });
      return result == true;
    } on PlatformException catch (e) {
      // 从details中提取错误码和详细信息
      final details = e.details as Map<dynamic, dynamic>?;
      final errorCode = details?['code'] as String?;
      final errorMessage = e.message ?? 'Unknown error';

      debugPrint(
        "Error publishing DPs: code=$errorCode, message=$errorMessage",
      );

      // 如果已经有详细的错误信息（来自Android端的处理），直接使用
      if (errorMessage.isNotEmpty && errorMessage != 'Unknown error') {
        debugPrint(
          '⚠️ 下发DP失败 $deviceId, dps: ${dps.map((dp) => dp.toJson()).toList()}, error: $errorMessage',
        );
        return false;
      }

      // 否则构造通用错误信息
      final fullError = errorCode != null
          ? "下发DP失败 (错误码: $errorCode): $errorMessage"
          : "下发DP失败: $errorMessage";
      debugPrint(
        '⚠️ 下发DP失败 $deviceId, dps: ${dps.map((dp) => dp.toJson()).toList()}, error: $fullError',
      );
      return false;
    }
  }

  // 下发单个 DP 数据点
  static Future<bool> publishDp(
    String deviceId,
    String dpId,
    dynamic value, {
    int timeout = 10,
  }) async {
    return publishDps(deviceId, [
      DpData(dpId: dpId, value: value),
    ], timeout: timeout);
  }

  // 获取单个 DP 数据点的值
  static Future<Map<String, dynamic>> getDp(
    String deviceId,
    String dpId,
  ) async {
    if (!AppConfig.tuyaEnabled) {
      debugPrint('⚠️ 涂鸦功能已禁用，跳过获取DP $deviceId, dpId: $dpId');
      throw Exception('Tuya feature is disabled');
    }

    try {
      // 将蓝牙ID转换为devId
      final device = await _dbService.getDeviceByBluetoothId(deviceId);
      if (device == null) {
        debugPrint('⚠️ 设备未找到 $deviceId');
        throw Exception('Device not found');
      }

      final result = await _methodChannel.invokeMethod('getDp', {
        'deviceId': device.devId,
        'dpId': dpId,
      });

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      } else {
        throw Exception('Invalid response format: $result');
      }
    } on PlatformException catch (e) {
      final details = e.details as Map<dynamic, dynamic>?;
      final errorCode = details?['code'] as String?;
      final errorMessage = e.message ?? 'Unknown error';

      debugPrint("Error getting DP: code=$errorCode, message=$errorMessage");

      throw Exception(
        errorCode != null
            ? "获取DP失败 (错误码: $errorCode): $errorMessage"
            : "获取DP失败: $errorMessage",
      );
    }
  }

  // 获取 DP 上报流
  static Stream<DpReportData> get dpReportStream {
    _initDpSubscription();
    return _dpReportController.stream;
  }

  // 初始化 DP 事件订阅
  static void _initDpSubscription() {
    if (_dpSubscription != null) return;

    _dpSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is String) {
          try {
            final Map<String, dynamic> eventData = jsonDecode(event);
            final type = eventData['type'] as String? ?? '';

            if (type == 'report') {
              // DP上报事件
              try {
                final reportData = DpReportData.fromJson(
                  eventData['data'] as Map<String, dynamic>,
                );
                _dpReportController.add(reportData);
              } catch (e) {
                debugPrint("Error parsing DP report data: $e");
              }
            }
          } catch (e) {
            debugPrint("Error parsing DP event: $e");
          }
        }
      },
      onError: (error) {
        debugPrint("DP event stream error: $error");
      },
    );
  }

  // 推送疗程设置（透传型 DP）
  static Future<bool> pushSessionSetting(
    String deviceId,
    int maxTime,
    bool isCustom,
    int totalPhase,
    int stimulationSucLvl,
    int expressionSucLvl,
    bool stimulationHybrid,
    bool expressionHybrid,
    List<Map<String, int>> modeDurations, {
    int timeout = 10,
  }) async {
    // 转换业务值为协议字节值
    List<int> bytes = [];

    // 添加基本参数
    bytes.add(valueReflect('max_time', maxTime));
    bytes.add(valueReflect('is_custom', isCustom));
    bytes.add(valueReflect('total_phase', totalPhase));
    bytes.add(valueReflect('stimulation_suc_lvl', stimulationSucLvl));
    bytes.add(valueReflect('expression_suc_lvl', expressionSucLvl));
    bytes.add(valueReflect('stimulation_hybrid', stimulationHybrid));
    bytes.add(valueReflect('expression_hybrid', expressionHybrid));

    if (isCustom) {
      // 添加模式时长数据
      for (var mode in modeDurations) {
        mode.forEach((key, value) {
          bytes.add(valueReflect('mode', key));
          bytes.add(valueReflect('duration', value));
        });
      }
    }

    // 转成 16 进制字符串（透传型 DP 需要）
    String hexData = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();

    // 确保是偶数位
    if (hexData.length % 2 != 0) {
      hexData = '0$hexData';
    }

    debugPrint("hexData: $hexData");

    return publishDps(deviceId, [
      DpData(dpId: DpConstants.sessionSetting, value: hexData),
    ], timeout: timeout);
  }

  // 值映射：业务值转协议字节值
  static int valueReflect(String key, dynamic value) {
    switch (key) {
      case 'max_time':
        // 15->0x00, 20->0x01, 25->0x02, 30->0x03
        if (value is int) {
          switch (value) {
            case 15:
              return 0x00;
            case 20:
              return 0x01;
            case 25:
              return 0x02;
            case 30:
              return 0x03;
            default:
              return 0x03; // 默认 30 分钟
          }
        }
        return 0x03;

      case 'is_custom':
        // true->0x01, false->0x00
        return (value == true || value == 1) ? 0x01 : 0x00;

      case 'total_phase':
        // 2->0x02, 3->0x03, 其他->0x04
        if (value is int) {
          switch (value) {
            case 2:
              return 0x02;
            case 3:
              return 0x03;
            default:
              return 0x04; // 默认 4 个阶段
          }
        }
        return 0x04;

      case 'stimulation_suc_lvl':
      case 'expression_suc_lvl':
        // 1-9 直接映射到 0x01-0x09
        if (value is int) {
          final intValue = value.clamp(1, 9);
          return intValue;
        }
        return 0x01;

      case 'stimulation_hybrid':
      case 'expression_hybrid':
        // true->0x01, false->0x00
        return (value == true || value == 1) ? 0x01 : 0x00;

      case 'mode':
        // stimulation->0x01, expression->0x02
        return (value == 'stimulation') ? 0x01 : 0x02;

      case 'duration':
        // 1-30 直接映射到 0x01-0x1E
        if (value is int) {
          return value.clamp(1, 30);
        }
        return 0x01; // 默认 1 分钟

      default:
        return 0x00;
    }
  }
}
