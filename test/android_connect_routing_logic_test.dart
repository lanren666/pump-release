import 'package:flutter_test/flutter_test.dart';
import 'package:pump/services/tuya/android_connect_routing_logic.dart';

void main() {
  group('AndroidConnectRoutingLogic.decide — normal', () {
    test('remembered devId always direct-connects, even if scan looks unbound', () {
      expect(
        AndroidConnectRoutingLogic.decide(
          knownDevId: 'eb25b2sd0pnt2tcx',
          hasScanBean: true,
          scanIsBound: false,
        ),
        AndroidConnectRoute.directDartDevId,
      );
    });

    test('first pair: unbound scan bean → activate', () {
      expect(
        AndroidConnectRoutingLogic.decide(
          knownDevId: '',
          hasScanBean: true,
          scanIsBound: false,
        ),
        AndroidConnectRoute.activate,
      );
    });

    test('bound scan without remembered devId → home lookup, not empty connect', () {
      expect(
        AndroidConnectRoutingLogic.decide(
          knownDevId: '',
          hasScanBean: true,
          scanIsBound: true,
        ),
        AndroidConnectRoute.homeLookup,
      );
    });

    test('missing scan cache without remembered devId → home lookup', () {
      expect(
        AndroidConnectRoutingLogic.decide(
          knownDevId: '',
          hasScanBean: false,
          scanIsBound: false,
        ),
        AndroidConnectRoute.homeLookup,
      );
    });
  });

  group('AndroidConnectRoutingLogic.decideAfterHomeLookup — exception', () {
    test('uuid still in home → direct connect with real devId', () {
      expect(
        AndroidConnectRoutingLogic.decideAfterHomeLookup(
          foundDevId: 'ebcbe7qwvnnnau1o',
          hasScanBean: true,
          scanIsBound: true,
        ),
        AndroidHomeLookupRoute.directConnect,
      );
    });

    test('empty foundDevId is not a connectable id', () {
      expect(
        AndroidConnectRoutingLogic.decideAfterHomeLookup(
          foundDevId: '',
          hasScanBean: true,
          scanIsBound: true,
        ),
        AndroidHomeLookupRoute.notInHome,
      );
    });

    test('offline cloud-unbind + still-bound broadcast → re-pair, no empty connect', () {
      expect(
        AndroidConnectRoutingLogic.decideAfterHomeLookup(
          foundDevId: null,
          hasScanBean: true,
          scanIsBound: true,
        ),
        AndroidHomeLookupRoute.notInHome,
      );
    });

    test('home miss but scan unbound → activate as last resort', () {
      expect(
        AndroidConnectRoutingLogic.decideAfterHomeLookup(
          foundDevId: null,
          hasScanBean: true,
          scanIsBound: false,
        ),
        AndroidHomeLookupRoute.activate,
      );
    });

    test('no scan bean and not in home → re-pair error', () {
      expect(
        AndroidConnectRoutingLogic.decideAfterHomeLookup(
          foundDevId: null,
          hasScanBean: false,
          scanIsBound: false,
        ),
        AndroidHomeLookupRoute.notInHome,
      );
    });
  });

  group('FORCE vs NORMAL', () {
    test('user/activate connect may FORCE; periodic reconnect must not', () {
      expect(
        AndroidConnectRoutingLogic.shouldForceConnect(userInitiated: true),
        isTrue,
      );
      expect(
        AndroidConnectRoutingLogic.shouldForceConnect(userInitiated: false),
        isFalse,
      );
    });
  });
}
