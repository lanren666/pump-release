import 'device_reconnect_policy.dart';
import '../diagnostics/pump_log.dart';

/// One-line Both-mode sync diagnostics — grep: `[INFO][SYNC_DIAG]`
class BothSyncDiagnostics {
  BothSyncDiagnostics._();

  static const String tag = 'SYNC_DIAG';

  static void logCheck({
    required String? leftDevId,
    required String? rightDevId,
    required bool leftHasStarted,
    required bool rightHasStarted,
    required int leftPhase,
    required int rightPhase,
    required String leftMode,
    required String rightMode,
    required int leftTotalSec,
    required int rightTotalSec,
    required int leftPhaseSec,
    required int rightPhaseSec,
    required bool syncOk,
    String? failReason,
    int? desyncCount,
  }) {
    final leftAlive = leftDevId != null && DpAliveTracker.isRecentlyAlive(leftDevId);
    final rightAlive =
        rightDevId != null && DpAliveTracker.isRecentlyAlive(rightDevId);

    final buf = StringBuffer()
      ..write('[$tag] sync=${syncOk ? 'OK' : 'FAIL'}')
      ..write(' L=${_side(leftHasStarted, leftPhase, leftMode, leftTotalSec, leftPhaseSec, leftAlive, leftDevId)}')
      ..write(' R=${_side(rightHasStarted, rightPhase, rightMode, rightTotalSec, rightPhaseSec, rightAlive, rightDevId)}');

    if (failReason != null) buf.write(' reason=$failReason');
    if (desyncCount != null) buf.write(' count=$desyncCount/6');

    PumpLog.i(tag, buf.toString());
  }

  static void logAsymmetricDp105({
    required String? leftDevId,
    required String? rightDevId,
    required bool leftAlive,
    required bool rightAlive,
  }) {
    PumpLog.d(
      tag,
      'defer: DP105 asymmetric '
      'L_alive=$leftAlive(${_shortId(leftDevId)}) '
      'R_alive=$rightAlive(${_shortId(rightDevId)}) — skip desync until both report',
    );
  }

  static void logIndividualModeSwitch({
    required String reason,
    required int leftTotalSec,
    required int rightTotalSec,
    required int desyncCount,
  }) {
    PumpLog.i(
      tag,
      '>>> INDIVIDUAL_MODE reason=$reason '
      'L_time=${leftTotalSec}s R_time=${rightTotalSec}s count=$desyncCount',
    );
  }

  static String? failReason({
    required bool leftAlive,
    required bool rightAlive,
    required String leftMode,
    required String rightMode,
    required int leftPhase,
    required int rightPhase,
    required int leftTotalSec,
    required int rightTotalSec,
    required int leftPhaseSec,
    required int rightPhaseSec,
    required int thresholdSec,
  }) {
    if (leftAlive != rightAlive) return null;
    if (leftMode != rightMode) return 'mode($leftMode≠$rightMode)';
    if (leftPhase != rightPhase) return 'phase($leftPhase≠$rightPhase)';
    final totalDiff = (leftTotalSec - rightTotalSec).abs();
    if (totalDiff > thresholdSec) return 'totalTime(diff=${totalDiff}s>${thresholdSec}s)';
    final phaseDiff = (leftPhaseSec - rightPhaseSec).abs();
    if (phaseDiff > thresholdSec) {
      return 'phaseTime(diff=${phaseDiff}s>${thresholdSec}s)';
    }
    return null;
  }

  static String _side(
    bool started,
    int phase,
    String mode,
    int totalSec,
    int phaseSec,
    bool dp105Alive,
    String? devId,
  ) =>
      'started=$started phase=$phase mode=$mode t=${totalSec}s pt=${phaseSec}s '
      'dp105=${dp105Alive ? 'Y' : 'N'} id=${_shortId(devId)}';

  static String _shortId(String? id) {
    if (id == null || id.isEmpty) return '-';
    if (id.length <= 8) return id;
    return '…${id.substring(id.length - 8)}';
  }
}
