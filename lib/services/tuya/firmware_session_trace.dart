/// Grep: `[INFO][FW_SNAP]` — firmware session dumps after BLE drop/reconnect.
class FirmwareSessionTrace {
  FirmwareSessionTrace._();

  static const String tag = 'FW_SNAP';

  /// Log DP105 at INFO after a gap, on first report, or when session fields change.
  static const int reconnectGapSeconds = 8;

  static final Map<String, FirmwareDp105Snapshot> _lastByDevId = {};

  static void clear() => _lastByDevId.clear();

  static FirmwareDp105Snapshot? lastSnapshot(String deviceId) =>
      _lastByDevId[deviceId];

  static bool shouldLogDp105Info({
    required String deviceId,
    required int? gapSec,
    required FirmwareDp105Snapshot snapshot,
  }) {
    if (deviceId.isEmpty) return false;
    if (gapSec == null) return true;
    if (gapSec >= reconnectGapSeconds) return true;
    final prev = _lastByDevId[deviceId];
    if (prev == null) return true;
    return prev.sessionSignature != snapshot.sessionSignature;
  }

  static void remember(String deviceId, FirmwareDp105Snapshot snapshot) {
    if (deviceId.isEmpty) return;
    _lastByDevId[deviceId] = snapshot;
  }

  static String formatDp105({
    required String deviceId,
    String? position,
    required FirmwareDp105Snapshot snapshot,
    int? gapSec,
  }) {
    final side = position == 'left'
        ? 'L'
        : position == 'right'
        ? 'R'
        : '?';
    final gap = gapSec == null ? 'first' : '${gapSec}s';
    final hint = snapshot.looksLikeDefaultFlow ? ' hint=default_2plus5' : '';
    return 'DP105 side=$side id=${_shortId(deviceId)} '
        'running=${snapshot.isRunning} t=${snapshot.timePast}s '
        'pt=${snapshot.timePastInPhase}s phase=${snapshot.sessionPhase} '
        'mode=${snapshot.sessionModeName} phaseMin=${snapshot.totalTimeInPhase} '
        'maxMin=${snapshot.maxTime} custom=${snapshot.isCustom} '
        'gap=$gap$hint';
  }

  static String formatHybrid({
    required String dpId,
    required String deviceId,
    String? position,
    required bool value,
  }) {
    final side = position == 'left'
        ? 'L'
        : position == 'right'
        ? 'R'
        : '?';
    final name = dpId == '107' ? 'stim' : dpId == '109' ? 'expr' : dpId;
    return 'DP$dpId hybrid_$name side=$side id=${_shortId(deviceId)} on=$value';
  }

  static String? maxTimeSplitWarning({
    required int? leftMax,
    required int? rightMax,
  }) {
    if (leftMax == null || rightMax == null) return null;
    if (leftMax == rightMax) return null;
    return 'maxTime split L=${leftMax}min R=${rightMax}min';
  }

  static String _shortId(String id) {
    if (id.length <= 8) return id;
    return '…${id.substring(id.length - 8)}';
  }
}

class FirmwareDp105Snapshot {
  const FirmwareDp105Snapshot({
    required this.isRunning,
    required this.timePast,
    required this.timePastInPhase,
    required this.sessionPhase,
    required this.sessionModeName,
    required this.totalTimeInPhase,
    required this.maxTime,
    required this.isCustom,
  });

  final int isRunning;
  final int timePast;
  final int timePastInPhase;
  final int sessionPhase;
  final String sessionModeName;
  final int totalTimeInPhase;
  final int maxTime;
  final bool isCustom;

  factory FirmwareDp105Snapshot.fromParsed(Map<String, dynamic> status) {
    return FirmwareDp105Snapshot(
      isRunning: status['isRunning'] as int? ?? -1,
      timePast: status['timePast'] as int? ?? 0,
      timePastInPhase: status['timePastInPhase'] as int? ?? 0,
      sessionPhase: status['sessionPhase'] as int? ?? 0,
      sessionModeName: status['sessionModeName'] as String? ?? '',
      totalTimeInPhase: status['totalTimeInPhase'] as int? ?? 0,
      maxTime: status['maxTime'] as int? ?? 0,
      isCustom: status['isCustom'] as bool? ?? false,
    );
  }

  /// Default factory flow is 2 min stim + 5 min expression, max 20, not custom.
  bool get looksLikeDefaultFlow =>
      !isCustom && maxTime == 20 && totalTimeInPhase == 5;

  String get sessionSignature =>
      '$isRunning|$maxTime|$isCustom|$totalTimeInPhase|$sessionModeName|$sessionPhase';
}
