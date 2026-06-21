import '../diagnostics/pump_log.dart';

/// Unified isRunning DB writes — grep: `[INFO][RUNNING]`
class RunningStatusLog {
  RunningStatusLog._();

  static const String tag = 'RUNNING';

  static void log({
    required String source,
    required String devId,
    required bool isRunning,
    int? streak,
    String? note,
  }) {
    final buf = StringBuffer()
      ..write('source=$source devId=$devId isRunning=$isRunning');
    if (streak != null) {
      buf.write(' streak=$streak');
    }
    if (note != null && note.isNotEmpty) {
      buf.write(' note=$note');
    }
    PumpLog.i(tag, buf.toString());
  }
}
