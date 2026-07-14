/// Determines whether a connect attempt should re-activate (pair) the device
/// or go straight to a direct BLE connect.
///
/// Activation is only needed when the scan shows the device as unpaired AND
/// we have no previously-issued devId for it. If we already have a devId the
/// device is registered in the home; calling activeBLE on it again will time
/// out (MSG_CONN_ERROR_CONNECT_TIMEOUT / 205105).
///
/// This logic is extracted so it can be unit-tested without platform channels.
/// The native implementations (AppDelegate.swift, MainActivity.kt) mirror this
/// decision using the `devId` arg passed from Dart.
enum ConnectRoute { activate, directConnect }

class ConnectDeviceRoutingLogic {
  const ConnectDeviceRoutingLogic._();

  /// [isActiveInScan] — ThingBLEAdvModel.isActive / ScanDeviceBean.isActive.
  ///   true  → device is already paired and connected in Tuya cloud.
  ///   false → device is advertising as unpaired (e.g. after battery re-insert
  ///           or manual disconnect that resets the device's BLE state).
  ///
  /// [knownDevId] — Tuya devId from the app's local DB. Empty string = unknown.
  ///   Non-empty means the device has already been through activation before;
  ///   it is registered in the home and a direct connect should be attempted.
  static ConnectRoute decide({
    required bool isActiveInScan,
    required String knownDevId,
  }) {
    if (isActiveInScan) return ConnectRoute.directConnect;
    if (knownDevId.isNotEmpty) return ConnectRoute.directConnect;
    return ConnectRoute.activate;
  }
}
