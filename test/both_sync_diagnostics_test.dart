import 'package:flutter_test/flutter_test.dart';
import 'package:pump/services/tuya/both_sync_diagnostics.dart';
import 'package:pump/services/tuya/device_reconnect_policy.dart';

void main() {
  group('BothSyncDiagnostics.failReason', () {
    setUp(DpAliveTracker.clearAll);

    test('returns null when both sides match', () {
      expect(
        BothSyncDiagnostics.failReason(
          leftAlive: true,
          rightAlive: true,
          leftMode: 'stimulation',
          rightMode: 'stimulation',
          leftPhase: 1,
          rightPhase: 1,
          leftTotalSec: 10,
          rightTotalSec: 12,
          leftPhaseSec: 5,
          rightPhaseSec: 7,
          thresholdSec: 30,
        ),
        isNull,
      );
    });

    test('detects phase mismatch', () {
      expect(
        BothSyncDiagnostics.failReason(
          leftAlive: true,
          rightAlive: true,
          leftMode: 'expression',
          rightMode: 'expression',
          leftPhase: 1,
          rightPhase: 2,
          leftTotalSec: 10,
          rightTotalSec: 10,
          leftPhaseSec: 5,
          rightPhaseSec: 5,
          thresholdSec: 30,
        ),
        'phase(1≠2)',
      );
    });
  });
}
