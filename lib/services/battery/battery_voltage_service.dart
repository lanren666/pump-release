import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';
import '../diagnostics/app_logger.dart';
import '../tuya/ble_dp_service.dart';
import '../tuya/dp_constants.dart';
import '../tuya/session_setting_parser.dart';

/// Reads Bat_Volt from device session_setting (DP 101).
class BatteryVoltageService {
  BatteryVoltageService._();

  static Future<int?> readBatVolt(String bluetoothId) async {
    if (!AppConfig.tuyaEnabled) return null;

    try {
      final response = await BleDpService.getDp(
        bluetoothId,
        DpConstants.sessionSetting,
      );
      final rawValue = response['value'];
      SessionSettingParser.logSessionSettingPayload(
        source: 'readBatVolt',
        deviceId: bluetoothId,
        rawValue: rawValue,
      );
      final hex = SessionSettingParser.normalizeHex(rawValue);
      final batVolt = SessionSettingParser.parseBatVolt(hex);

      AppLogger.hardware('readBatVolt', {
        'bluetoothId': bluetoothId,
        'hexLength': hex?.length,
        'batVolt': batVolt,
      });
      return batVolt;
    } catch (e, st) {
      debugPrint('readBatVolt failed for $bluetoothId: $e');
      AppLogger.e('hw', 'readBatVolt failed', {
        'bluetoothId': bluetoothId,
        'error': e.toString(),
        'stack': st.toString().split('\n').take(4).join('\n'),
      });
      return null;
    }
  }
}
