/// Parses native connectDevice replies and the scan productKey field.
///
/// Official connectBleDevice has no success callback. Android may return
/// `{success:false, pending:true, devId}` instead of treating an 8s miss
/// as a confirmed drop.
class NativeConnectResult {
  const NativeConnectResult({
    required this.success,
    required this.pending,
    required this.devId,
  });

  final bool success;
  final bool pending;
  final String? devId;

  bool get shouldRemember => success || pending;

  bool get shouldMarkRunning => success;

  bool get shouldAnnounceConnected => success;

  bool get shouldPublishDeviceSymbol => success;

  bool get shouldRegisterListener => success;

  bool get shouldCheckLowBattery => success;

  /// Pending remember is only useful when periodic reconnect has a Tuya id.
  bool canRememberWithDevId(String? resolvedDevId) {
    if (success) return true;
    if (!pending) return false;
    return resolvedDevId != null && resolvedDevId.isNotEmpty;
  }
}

class NativeConnectResultLogic {
  const NativeConnectResultLogic._();

  static NativeConnectResult parse(dynamic raw) {
    if (raw is bool) {
      return NativeConnectResult(success: raw, pending: false, devId: null);
    }
    if (raw is Map) {
      final devId = raw['devId'];
      return NativeConnectResult(
        success: raw['success'] == true,
        pending: raw['pending'] == true,
        devId: devId is String && devId.isNotEmpty ? devId : null,
      );
    }
    return const NativeConnectResult(
      success: false,
      pending: false,
      devId: null,
    );
  }

  /// Official scan product id is productId. Older Android sent providerName.
  static String productKeyFromScan({
    required String productId,
    required String providerName,
  }) {
    return productId.isNotEmpty ? productId : providerName;
  }

  static bool shouldPromptRePair(String errorCode) =>
      errorCode == 'DEVICE_NOT_IN_HOME' || errorCode == 'MISSING_DEV_ID';

  static bool shouldPromptHomeRetry(String errorCode) =>
      errorCode == 'HOME_NOT_FOUND';
}
