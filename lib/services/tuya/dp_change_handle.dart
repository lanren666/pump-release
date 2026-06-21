import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database_service.dart';
import '../diagnostics/app_logger.dart';
import '../diagnostics/pump_log.dart';
import 'dp_constants.dart';
import 'session_setting_parser.dart';
import 'ble_dp_service.dart';
import 'device_reconnect_policy.dart';

// SessionStatus 更新数据
class SessionStatusUpdate {
  final String deviceId;
  final Map<String, dynamic> status;

  SessionStatusUpdate({required this.deviceId, required this.status});
}

// DP 参数更新数据（吸力大小、混合模式等）
class DpParamUpdate {
  final String deviceId;
  final String dpId;
  final dynamic value;
  final String? position; // 'left' 或 'right'，从数据库查询得到

  DpParamUpdate({
    required this.deviceId,
    required this.dpId,
    required this.value,
    this.position,
  });
}

class DpChangeHandle {
  final DatabaseService _dbService = DatabaseService();
  static StreamSubscription? _dpReportSubscription;

  // SessionStatus 更新 Stream
  static final StreamController<SessionStatusUpdate> _sessionStatusController =
      StreamController<SessionStatusUpdate>.broadcast();

  // Control 页面可以订阅这个 Stream 来接收状态更新
  static Stream<SessionStatusUpdate> get sessionStatusStream =>
      _sessionStatusController.stream;

  // DP 参数更新 Stream（吸力大小、混合模式等）
  static final StreamController<DpParamUpdate> _dpParamController =
      StreamController<DpParamUpdate>.broadcast();

  // Control 页面可以订阅这个 Stream 来接收参数更新
  static Stream<DpParamUpdate> get dpParamStream => _dpParamController.stream;

  // 初始化 DP 上报监听
  static void init() {
    if (_dpReportSubscription != null) {
      return; // 已经初始化过了
    }

    // 延迟初始化，等待原生端 EventChannel 设置完成
    // 注意：如果出现 MissingPluginException，说明延迟时间不够，可以适当增加
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_dpReportSubscription != null) {
        return; // 已经初始化过了
      }

      final handleInstance = DpChangeHandle();

      try {
        _dpReportSubscription = BleDpService.dpReportStream.listen(
          (reportData) {
            for (final dp in reportData.dps) {
              final dpId = _normalizeDpId(dp.dpId);
              if (dpId == DpConstants.sessionStatus) {
                PumpLog.d(
                  'DP105',
                  'transport deviceId=${reportData.deviceId} '
                  'rawType=${dp.value.runtimeType} rawValue=${dp.value}',
                );
              } else if (dpId == DpConstants.stimulationSucLvl ||
                  dpId == DpConstants.expressionSucLvl) {
                PumpLog.d(
                  'DP$dpId',
                  'suction transport deviceId=${reportData.deviceId} value=${dp.value}',
                );
              }
              handleInstance.handle(reportData.deviceId, dpId, dp.value);
            }
          },
          onError: (error) {
            debugPrint('❌ DP 上报监听错误: $error');
            // 如果监听失败，尝试重新初始化
            _dpReportSubscription = null;
            Future.delayed(const Duration(milliseconds: 2000), () {
              init();
            });
          },
        );

        debugPrint('✅ DP 上报监听已初始化');
      } catch (e) {
        debugPrint('❌ DP 上报监听初始化失败: $e');
        // 如果初始化失败，延迟后重试
        Future.delayed(const Duration(milliseconds: 2000), () {
          init();
        });
      }
    });
  }

  // 取消监听
  static void dispose() {
    _dpReportSubscription?.cancel();
    _dpReportSubscription = null;
    debugPrint('✅ DP 上报监听已取消');
  }

  Future<void> handle(String deviceId, String dpId, dynamic dpValue) async {
    dpId = _normalizeDpId(dpId);
    AppLogger.hardwareDebug('dp_handle', {
      'deviceId': deviceId,
      'dpId': dpId,
      'value': dpId == DpConstants.sessionStatus
          ? _truncateForLog(dpValue.toString(), 96)
          : dpValue,
    });
    switch (dpId) {
      case DpConstants.stimulationSucLvl:
        final device = await _dbService.getDeviceByDevId(deviceId);
        final position = device?.position;
        _dpParamController.add(
          DpParamUpdate(
            deviceId: deviceId,
            dpId: dpId,
            value: dpValue is int
                ? dpValue
                : int.tryParse(dpValue.toString()) ?? 3,
            position: position,
          ),
        );
        break;
      case DpConstants.expressionSucLvl:
        final device2 = await _dbService.getDeviceByDevId(deviceId);
        final position2 = device2?.position;
        _dpParamController.add(
          DpParamUpdate(
            deviceId: deviceId,
            dpId: dpId,
            value: dpValue is int
                ? dpValue
                : int.tryParse(dpValue.toString()) ?? 3,
            position: position2,
          ),
        );
        break;
      case DpConstants.stimulationHybrid:
        final device3 = await _dbService.getDeviceByDevId(deviceId);
        final position3 = device3?.position;
        _dpParamController.add(
          DpParamUpdate(
            deviceId: deviceId,
            dpId: dpId,
            value: dpValue is bool
                ? dpValue
                : (dpValue == true || dpValue == 1 || dpValue == "true"),
            position: position3,
          ),
        );
        break;
      case DpConstants.expressionHybrid:
        final device4 = await _dbService.getDeviceByDevId(deviceId);
        final position4 = device4?.position;
        _dpParamController.add(
          DpParamUpdate(
            deviceId: deviceId,
            dpId: dpId,
            value: dpValue is bool
                ? dpValue
                : (dpValue == true || dpValue == 1 || dpValue == "true"),
            position: position4,
          ),
        );
        break;
      case DpConstants.sessionStatus:
        try {
          final String dpValueStr = dpValue is String
              ? dpValue
              : dpValue.toString();
          PumpLog.d(
            'DP105',
            'received deviceId=$deviceId hexLen=${dpValueStr.length}',
          );
          final parsedStatus = parseSessionStatus(dpValueStr);
          PumpLog.d(
            'DP105',
            'parsed deviceId=$deviceId '
            'isRunning=${parsedStatus['isRunning']} '
            'timePast=${parsedStatus['timePast']}s '
            'phase=${parsedStatus['sessionPhase']} '
            'mode=${parsedStatus['sessionModeName']}',
          );

          DpAliveTracker.touch(deviceId);

          _sessionStatusController.add(
            SessionStatusUpdate(deviceId: deviceId, status: parsedStatus),
          );
          AppLogger.hardwareDebug('sessionStatus parsed', {
            'deviceId': deviceId,
            'isRunning': parsedStatus['isRunning'],
            'sessionPhase': parsedStatus['sessionPhase'],
            'sessionModeName': parsedStatus['sessionModeName'],
          });
        } catch (e, stackTrace) {
          debugPrint(
            '❌ DP105 sessionStatus [parse failed] deviceId=$deviceId '
            'rawValue=$dpValue error=$e',
          );
          debugPrint('❌ Stack trace: $stackTrace');
        }
        break;
      case DpConstants.sessionSetting:
        SessionSettingParser.logSessionSettingPayload(
          source: 'dpReport',
          deviceId: deviceId,
          rawValue: dpValue,
        );
        break;
      case DpConstants.batteryLevel:
        final device = await _dbService.getDeviceByDevId(deviceId);
        if (device != null) {
          final intValue = int.parse(dpValue.toString());
          await _dbService.updateDevice(device.copyWith(battery: intValue));
          _dpParamController.add(
            DpParamUpdate(
              deviceId: deviceId,
              dpId: dpId,
              value: intValue,
              position: device.position,
            ),
          );
        }
        break;
      default:
        AppLogger.hardwareDebug('dp_handle ignored dpId', {
          'deviceId': deviceId,
          'dpId': dpId,
        });
        break;
    }
  }

  static String _normalizeDpId(dynamic dpId) {
    if (dpId == null) return '';
    return dpId.toString();
  }

  static String _truncateForLog(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  // 解析会话状态（DP 105）
  // 固件格式：22 hex 核心字段 + 4 hex Bat_Volt（共 26 hex）；老设备可能仅 22 hex。
  static const int sessionStatusCoreHexLength = 22;
  static const int sessionStatusWithBatVoltHexLength = 26;

  static Map<String, dynamic> parseSessionStatus(String dpValue) {
    String normalizedValue = dpValue.trim().toUpperCase();
    if (normalizedValue.length == 24) {
      // Legacy: 24 hex with a 1-byte prefix — drop first byte.
      debugPrint(
        '⚠️ SessionStatus 数据长度异常 (24字符)，尝试去掉前2个字符: $normalizedValue',
      );
      normalizedValue = normalizedValue.substring(2);
    }

    final isLegacyCoreOnly = normalizedValue.length == sessionStatusCoreHexLength;
    final isWithBatVolt =
        normalizedValue.length == sessionStatusWithBatVoltHexLength;
    if (!isLegacyCoreOnly && !isWithBatVolt) {
      throw FormatException(
        'SessionStatus 数据长度不正确: 期望 $sessionStatusCoreHexLength 或 '
        '$sessionStatusWithBatVoltHexLength 个字符，实际 ${normalizedValue.length} 个字符，'
        '数据: $normalizedValue',
      );
    }

    final core = normalizedValue.substring(0, sessionStatusCoreHexLength);
    final batVolt = isWithBatVolt
        ? SessionSettingParser.parseBatVolt(normalizedValue)
        : null;

    final timePast = core.substring(0, 4);
    final timePastInPhase = core.substring(4, 8);
    final sessionPhase = core.substring(8, 10);
    final sessionMode = core.substring(10, 12);
    final totalPhase = core.substring(12, 14);
    final maxTime = core.substring(14, 16);
    final isCustom = core.substring(16, 18);
    final isRunning = core.substring(18, 20);
    final totalTimeInPhase = core.substring(20, 22);

    // timePast 单位是秒，十六进制转十进制
    final timePastSeconds = int.parse(timePast, radix: 16);
    final timePastFormatted = Duration(
      seconds: timePastSeconds,
    ).toString().substring(2);

    // timePastInPhase 单位是秒，十六进制转十进制
    final timePastInPhaseSeconds = int.parse(timePastInPhase, radix: 16);
    final timePastInPhaseFormatted = Duration(
      seconds: timePastInPhaseSeconds,
    ).toString().substring(2);

    // sessionPhase: 0x00-0x03 -> 1-4
    final sessionPhaseValue = int.parse(sessionPhase, radix: 16) + 1;

    // sessionMode: 0x01=stimulation, 0x02=expression
    final sessionModeValue = int.parse(sessionMode, radix: 16);
    final sessionModeName = sessionModeValue == 1
        ? 'stimulation'
        : 'expression';

    // totalPhase: 0x02-0x04 -> 2-4
    final totalPhaseValue = int.parse(totalPhase, radix: 16);

    // maxTime: 0x00=15min, 0x01=20min, 0x02=25min, 0x03=30min
    final maxTimeValue = int.parse(maxTime, radix: 16);
    if (maxTimeValue < 0 || maxTimeValue >= 4) {
      throw FormatException('maxTime 值超出范围: $maxTimeValue (期望 0-3)');
    }
    final maxTimeMinutes = [15, 20, 25, 30][maxTimeValue];

    // isCustom: 0x00=false, 0x01=true
    final isCustomValue = int.parse(isCustom, radix: 16) == 1;

    // isRunning: 0x00=pause, 0x01=running, 0x02=stop
    final isRunningValue = int.parse(isRunning, radix: 16);

    // totalTimeInPhase: 单位是分钟
    final totalTimeInPhaseMinutes = int.parse(totalTimeInPhase, radix: 16);

    return {
      'timePast': timePastSeconds, // 疗程总计用时（秒）
      'timePastFormatted': timePastFormatted, // 格式化时间 (mm:ss)
      'timePastInPhase': timePastInPhaseSeconds, // 阶段总计用时（秒）
      'timePastInPhaseFormatted': timePastInPhaseFormatted, // 格式化时间 (mm:ss)
      'sessionPhase': sessionPhaseValue, // 当前阶段 (1-4)
      'sessionMode': sessionModeValue, // 0x01=stimulation, 0x02=expression
      'sessionModeName': sessionModeName, // 'stimulation' 或 'expression'
      'totalPhase': totalPhaseValue, // 总阶段数 (2-4)
      'maxTime': maxTimeMinutes, // 最大时间（分钟）
      'isCustom': isCustomValue, // 是否自定义会话
      'isRunning': isRunningValue, // 是否正在运行
      'totalTimeInPhase': totalTimeInPhaseMinutes, // 当前阶段总时间（分钟）
      if (batVolt != null) 'batVolt': batVolt, // 末尾 2 字节电池电压（仅 26 hex）
    };
  }
}
