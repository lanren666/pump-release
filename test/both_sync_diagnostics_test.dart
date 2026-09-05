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

    test('single-side DP105 drop is not a desync even when times already diverged', () {
      expect(
        BothSyncDiagnostics.failReason(
          leftAlive: true,
          rightAlive: false,
          leftMode: 'expression',
          rightMode: 'stimulation',
          leftPhase: 2,
          rightPhase: 1,
          leftTotalSec: 512,
          rightTotalSec: 387,
          leftPhaseSec: 200,
          rightPhaseSec: 20,
          thresholdSec: 30,
        ),
        isNull,
      );
      expect(
        BothSyncDiagnostics.isAsymmetricLink(
          leftAlive: true,
          rightAlive: false,
        ),
        isTrue,
      );
    });

    test('DB offline on one side is not a desync while the other is still linked', () {
      expect(
        BothSyncDiagnostics.failReason(
          leftAlive: true,
          rightAlive: true,
          leftLinked: true,
          rightLinked: false,
          leftMode: 'expression',
          rightMode: 'expression',
          leftPhase: 2,
          rightPhase: 2,
          leftTotalSec: 512,
          rightTotalSec: 387,
          leftPhaseSec: 200,
          rightPhaseSec: 267,
          thresholdSec: 30,
        ),
        isNull,
      );
    });

    test('both sides alive and linked still flags a real time desync', () {
      expect(
        BothSyncDiagnostics.failReason(
          leftAlive: true,
          rightAlive: true,
          leftLinked: true,
          rightLinked: true,
          leftMode: 'expression',
          rightMode: 'expression',
          leftPhase: 2,
          rightPhase: 2,
          leftTotalSec: 512,
          rightTotalSec: 387,
          leftPhaseSec: 200,
          rightPhaseSec: 267,
          thresholdSec: 30,
        ),
        'totalTime(diff=125s>30s)',
      );
    });

    test('mode mismatch is still a desync when both sides are alive', () {
      expect(
        BothSyncDiagnostics.failReason(
          leftAlive: true,
          rightAlive: true,
          leftLinked: true,
          rightLinked: true,
          leftMode: 'stimulation',
          rightMode: 'expression',
          leftPhase: 1,
          rightPhase: 2,
          leftTotalSec: 10,
          rightTotalSec: 10,
          leftPhaseSec: 5,
          rightPhaseSec: 5,
          thresholdSec: 30,
        ),
        'mode(stimulation≠expression)',
      );
    });

    test('time diff equal to threshold is still in sync', () {
      expect(
        BothSyncDiagnostics.failReason(
          leftAlive: true,
          rightAlive: true,
          leftLinked: true,
          rightLinked: true,
          leftMode: 'expression',
          rightMode: 'expression',
          leftPhase: 2,
          rightPhase: 2,
          leftTotalSec: 100,
          rightTotalSec: 130,
          leftPhaseSec: 10,
          rightPhaseSec: 10,
          thresholdSec: 30,
        ),
        isNull,
      );
    });

    test('both sides dead and unlinked still compares frozen state', () {
      expect(
        BothSyncDiagnostics.failReason(
          leftAlive: false,
          rightAlive: false,
          leftLinked: false,
          rightLinked: false,
          leftMode: 'expression',
          rightMode: 'expression',
          leftPhase: 2,
          rightPhase: 2,
          leftTotalSec: 512,
          rightTotalSec: 387,
          leftPhaseSec: 200,
          rightPhaseSec: 267,
          thresholdSec: 30,
        ),
        'totalTime(diff=125s>30s)',
      );
    });
  });

  group('BothSyncDiagnostics.canRecoverDroppedBothSide', () {
    test('Both tab recovers after a drop', () {
      expect(
        BothSyncDiagnostics.canRecoverDroppedBothSide(
          isIndividualMode: false,
          selectedPumpIsBoth: true,
          sessionStartedAsBoth: true,
        ),
        isTrue,
      );
    });

    test('sessionStartedAsBoth still recovers if the tab flickered away', () {
      expect(
        BothSyncDiagnostics.canRecoverDroppedBothSide(
          isIndividualMode: false,
          selectedPumpIsBoth: false,
          sessionStartedAsBoth: true,
        ),
        isTrue,
      );
    });

    test('individual mode never recovers into a Both kick', () {
      expect(
        BothSyncDiagnostics.canRecoverDroppedBothSide(
          isIndividualMode: true,
          selectedPumpIsBoth: true,
          sessionStartedAsBoth: true,
        ),
        isFalse,
      );
    });

    test('true single-side session does not recover as Both', () {
      expect(
        BothSyncDiagnostics.canRecoverDroppedBothSide(
          isIndividualMode: false,
          selectedPumpIsBoth: false,
          sessionStartedAsBoth: false,
        ),
        isFalse,
      );
    });
  });

  group('BothSyncDiagnostics.isAsymmetricLink', () {
    test('same alive and omitted links is symmetric', () {
      expect(
        BothSyncDiagnostics.isAsymmetricLink(
          leftAlive: true,
          rightAlive: true,
        ),
        isFalse,
      );
    });

    test('same alive but different DB link is asymmetric', () {
      expect(
        BothSyncDiagnostics.isAsymmetricLink(
          leftAlive: true,
          rightAlive: true,
          leftLinked: true,
          rightLinked: false,
        ),
        isTrue,
      );
    });
  });
}
