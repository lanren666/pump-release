/// Mirrors Android [MainActivity.handleConnectDevice] so the official Tuya
/// connect routes can be unit-tested without the SDK.
enum AndroidConnectRoute { directDartDevId, activate, homeLookup }

enum AndroidHomeLookupRoute { directConnect, activate, notInHome }

class AndroidConnectRoutingLogic {
  const AndroidConnectRoutingLogic._();

  /// [knownDevId] — remembered Tuya devId from Dart/DB.
  /// [hasScanBean] — scan cache still holds this uuid.
  /// [scanIsBound] — official ScanDeviceBean.isbind (not providerName).
  static AndroidConnectRoute decide({
    required String knownDevId,
    required bool hasScanBean,
    required bool scanIsBound,
  }) {
    if (knownDevId.isNotEmpty) return AndroidConnectRoute.directDartDevId;
    if (hasScanBean && !scanIsBound) return AndroidConnectRoute.activate;
    return AndroidConnectRoute.homeLookup;
  }

  /// After getHomeDetail: never connect with an empty devId.
  static AndroidHomeLookupRoute decideAfterHomeLookup({
    required String? foundDevId,
    required bool hasScanBean,
    required bool scanIsBound,
  }) {
    if (foundDevId != null && foundDevId.isNotEmpty) {
      return AndroidHomeLookupRoute.directConnect;
    }
    if (hasScanBean && !scanIsBound) {
      return AndroidHomeLookupRoute.activate;
    }
    return AndroidHomeLookupRoute.notInHome;
  }

  /// User/activate connect may FORCE; periodic dual-pump reconnect must not.
  static bool shouldForceConnect({required bool userInitiated}) => userInitiated;
}
