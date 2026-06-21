import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../config/app_color.dart';
import '../config/responsive_text.dart';
import '../services/database_service.dart';
import '../models/connected_device.dart';
import '../models/setting.dart';
import 'custom_flow.dart';
import 'custom_flow_config.dart';
import 'home.dart';
import 'settings.dart';
import 'system_settings.dart';
import 'help_about.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/tuya/dp_constants.dart';
import '../services/tuya/ble_dp_service.dart';
import '../services/tuya/ble_types.dart';
import '../services/tuya/dp_change_handle.dart';
import '../services/diagnostics/pump_log.dart';
import '../services/tuya/both_sync_diagnostics.dart';
import '../services/tuya/native_ble_device_id.dart';
import '../services/tuya/device_reconnect_policy.dart';
import '../services/tuya/device_listener_service.dart';
import '../services/tuya/tuya_sdk_service.dart';
import '../config/app_config.dart';
import '../config/ble_channels.dart';
import 'control_timer_display_logic.dart';
import 'control_hybrid_pattern_logic.dart';
import 'control_types.dart';
import 'widgets/unified_timer_card.dart';
import 'widgets/low_battery_dialog.dart';
import '../services/battery/battery_alert_logic.dart';

// 记录待确认的操作，用来处理容错
class _PendingOperation {
  final int expectedIsRunning; // 期望的状态：0=停止, 1=运行, 2=暂停
  final DateTime timestamp; // 操作时间

  _PendingOperation({required this.expectedIsRunning, required this.timestamp});
}

// 用户操作记录，用于防止设备返回的旧状态覆盖用户操作
class _UserOperation {
  final double expectedValue;
  final DateTime timestamp;
  final String dpId; // 用于区分不同的DP

  _UserOperation({
    required this.expectedValue,
    required this.timestamp,
    required this.dpId,
  });
}

class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> with WidgetsBindingObserver {
  PumpSelection _selectedPump = PumpSelection.both;
  SessionMode _sessionMode = SessionMode.defaultMode;

  // 为每个泵选择保存独立的 SessionMode 和 Max Duration
  final Map<PumpSelection, SessionMode> _pumpSessionModes = {
    PumpSelection.left: SessionMode.defaultMode,
    PumpSelection.both: SessionMode.defaultMode,
    PumpSelection.right: SessionMode.defaultMode,
  };
  final Map<PumpSelection, int> _pumpMaxDurations = {
    PumpSelection.left: 20,
    PumpSelection.both: 20,
    PumpSelection.right: 20,
  };

  // 左侧设备状态
  IntensityMode _leftIntensityMode = IntensityMode.stimulation;
  double _leftStimulationSuctionLevel = 3.0;
  double _leftExpressionSuctionLevel = 3.0;
  bool _leftHybridPatternEnabled = false;
  bool _leftIsRunning = false;
  bool _leftHasStarted = false;
  Duration _leftElapsedTime = Duration.zero;
  Duration _leftElapsedTimeInPhase = Duration.zero;
  int _leftCurrentPhase = 1;
  int _leftTotalPhase = 2;
  Duration _leftPhaseDuration = const Duration(minutes: 2);
  int _bothNotSynchronizedCount = 0;
  DateTime? _bothDesyncSince;
  DateTime? _bothSyncActionGraceUntil;
  String? _lastBothSyncFailReason;
  bool _isIndividualMode = false; // 标记是否已切换到独立模式

  // 右侧设备状态
  IntensityMode _rightIntensityMode = IntensityMode.stimulation;
  double _rightStimulationSuctionLevel = 3.0;
  double _rightExpressionSuctionLevel = 3.0;
  bool _rightHybridPatternEnabled = false;
  bool _rightIsRunning = false;
  bool _rightHasStarted = false;
  Duration _rightElapsedTime = Duration.zero;
  Duration _rightElapsedTimeInPhase = Duration.zero;
  int _rightCurrentPhase = 1;
  int _rightTotalPhase = 2;
  Duration _rightPhaseDuration = const Duration(minutes: 2);

  int _maxDuration = 20;
  int? _deviceMaxDuration;
  bool _isMenuOpen = false;
  bool _isClosingForDeviceSettings = false;
  Duration _elapsedTime = Duration.zero;
  Duration _elapsedTimeInPhase = Duration.zero;
  int _currentPhase = 1;
  int _totalPhase = 2;
  Duration _phaseDuration = const Duration(minutes: 2);
  String _customFlowDescription = '2min -> 15min';
  final DatabaseService _dbService = DatabaseService();

  // 吸力级别配置的 DB key，用于记忆上次设置
  static const String _keyLeftStimulationSuction = 'suction_left_stimulation';
  static const String _keyLeftExpressionSuction = 'suction_left_expression';
  static const String _keyRightStimulationSuction = 'suction_right_stimulation';
  static const String _keyRightExpressionSuction = 'suction_right_expression';
  static const String _descSuctionLevel = '吸力级别';

  // 混合模式配置的 DB key，用于记忆上次设置（与 suctionlevel 一致：优先数据库，页面/DP 动态回写）
  static const String _keyLeftHybridPattern = 'hybrid_pattern_left';
  static const String _keyRightHybridPattern = 'hybrid_pattern_right';
  static const String _descHybridPattern = '混合模式';

  // 设备数据
  ConnectedDevice? _leftDevice;
  ConnectedDevice? _rightDevice;

  StreamSubscription<SessionStatusUpdate>? _sessionStatusSubscription;
  StreamSubscription<DpParamUpdate>? _dpParamSubscription;
  Timer? _refreshTimer;
  final Set<String> _reconnectingDeviceIds = {};
  final Map<String, _PendingOperation> _pendingOperations = {};
  final Map<String, Timer> _pendingCheckTimers = {};
  static const int _toleranceDelayMs = 2500;
  static const int _bothTimeSyncThresholdSeconds = 30; // both 模式时间容差阈值（秒）
  static const int _bothBleCommandGapMs = 500;
  static const int _bothStopBeforeStartDelayMs = 800;
  static const int _bothSideKickCooldownMs = 8000;
  static const int _bothSyncActionGraceMs = 5000;
  static const int _bothSustainedDesyncMs = 15000;
  DateTime? _lastBothSideKickAt;
  bool _bothStartInProgress = false;

  /// Prevents duplicate session-complete low-battery dialogs per device per session.
  final Set<String> _sessionCompleteLowBatteryShown = {};

  /// Prevents duplicate in-session low-battery dialogs per device per session.
  final Set<String> _sessionRunningLowBatteryShown = {};

  // 用于防止设备返回的旧状态覆盖用户操作
  // 记录用户最近的操作：设备ID -> (期望值, 操作时间)
  final Map<String, Map<String, _UserOperation>> _recentUserOperations = {};
  static const int _ignoreDeviceUpdateWindowMs = 300; // 用户操作后300ms内忽略不一致的设备更新

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSuctionLevelSettings();
    _loadHybridPatternSettings();
    _loadCustomFlowDescription();
    _loadDevices();
    _subscribeToSessionStatus();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _sessionStatusSubscription?.cancel();
    _dpParamSubscription?.cancel();
    for (final timer in _pendingCheckTimers.values) {
      timer.cancel();
    }
    _pendingCheckTimers.clear();
    _pendingOperations.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // 当应用回到前台时，清理所有 pending operations
    // 因为应用在后台时设备状态可能已经变化，pending operations 可能已经过期
    if (state == AppLifecycleState.resumed) {
      final pendingCount = _pendingOperations.length;
      if (pendingCount > 0) {
        // debugPrint(
        //   '🔄 应用回到前台，清理 $pendingCount 个待确认操作（应用在后台时设备状态可能已变化）',
        // );
        // 取消所有定时器
        for (final timer in _pendingCheckTimers.values) {
          timer.cancel();
        }
        _pendingCheckTimers.clear();
        // 清理所有 pending operations
        _pendingOperations.clear();
      }
    }
  }

  void _subscribeToSessionStatus() {
    _sessionStatusSubscription = DpChangeHandle.sessionStatusStream.listen(
      _handleSessionStatusUpdate,
      onError: (error) => debugPrint('❌ SessionStatus Stream 错误: $error'),
    );
    _dpParamSubscription = DpChangeHandle.dpParamStream.listen(
      _handleDpParamUpdate,
      onError: (error) => debugPrint('❌ DP Param Stream 错误: $error'),
    );
  }

  Future<void> _handleSessionStatusUpdate(SessionStatusUpdate update) async {
    final isLeftDevice = _leftDevice?.devId == update.deviceId;
    final isRightDevice = _rightDevice?.devId == update.deviceId;
    if (!isLeftDevice && !isRightDevice) {
      debugPrint(
        '⚠️ DP105 sessionStatus [ignored] deviceId=${update.deviceId} '
        'leftDevId=${_leftDevice?.devId} rightDevId=${_rightDevice?.devId}',
      );
      return;
    }

    final status = update.status;
    final isRunning = status['isRunning'] as int;

    await _maybePromptLowBatteryAfterSessionEnd(
      isLeftDevice: isLeftDevice,
      newIsRunning: isRunning,
    );
    
    // 容错检查：判断是否应该跳过isRunning相关的状态变更
    // 但即使跳过，也要继续处理数据更新（timePast等）
    bool shouldSkipIsRunningUpdate = false;
    final pendingOp = _pendingOperations[update.deviceId];
    if (pendingOp != null) {
      final expectedRunning = pendingOp.expectedIsRunning;
      final timeSinceOp = DateTime.now()
          .difference(pendingOp.timestamp)
          .inMilliseconds;
      if (isRunning != expectedRunning && timeSinceOp < _toleranceDelayMs) {
        // debugPrint(
        //   '⏳ 容错检查: $update.deviceId 状态不符预期 (期望: $expectedRunning, 实际: $isRunning, 已等待: ${timeSinceOp}ms)，跳过isRunning更新但继续处理数据',
        // );
        shouldSkipIsRunningUpdate = true;
        _pendingCheckTimers[update.deviceId]?.cancel();
        final remainingTime = _toleranceDelayMs - timeSinceOp;
        _pendingCheckTimers[update.deviceId] = Timer(
          Duration(milliseconds: remainingTime),
          () {
            _pendingCheckTimers.remove(update.deviceId);
            // debugPrint('⏳ 容错检查超时: $update.deviceId，清除待确认操作（可能是硬件自己变化）');
            _pendingOperations.remove(update.deviceId);
          },
        );
      } else if (isRunning == expectedRunning) {
        // debugPrint(
        //   '✅ 容错检查通过: $update.deviceId 状态已符合预期 (期望: $expectedRunning, 实际: $isRunning)',
        // );
        _pendingOperations.remove(update.deviceId);
        _pendingCheckTimers[update.deviceId]?.cancel();
        _pendingCheckTimers.remove(update.deviceId);
      } else {
        // debugPrint(
        //   '⚠️ 容错检查超时: $update.deviceId 状态仍不符预期 (期望: $expectedRunning, 实际: $isRunning, 已等待: ${timeSinceOp}ms)，清除待确认操作',
        // );
        _pendingOperations.remove(update.deviceId);
        _pendingCheckTimers[update.deviceId]?.cancel();
        _pendingCheckTimers.remove(update.deviceId);
      }
    }
    
    final timePast = status['timePast'] as int; // 总用时，秒
    final timePastInPhase = status['timePastInPhase'] as int; // 当前阶段用时，秒
    final sessionPhase = status['sessionPhase'] as int;
    final sessionModeName =
        status['sessionModeName'] as String; // 'stimulation' 或 'expression'
    final totalTimeInPhase = status['totalTimeInPhase'] as int; // 当前阶段总时间，分钟
    final totalPhase = status['totalPhase'] as int; // 总阶段数
    final maxTime = status['maxTime'] as int; // 最大时间，分钟

    // 更新强度模式
    final intensityMode = sessionModeName == 'stimulation'
        ? IntensityMode.stimulation
        : IntensityMode.expression;

    // 如果容错检查要求跳过isRunning更新，只更新数据，不处理状态变更
    if (shouldSkipIsRunningUpdate) {
      // 保护逻辑：如果期望状态是运行中(1)，但硬件上报timePast=0，这可能是状态切换时的临时重置
      // 不应该将数据更新为0，应该保持当前数据或等待下一个正确的数据
      final expectedRunning = pendingOp!.expectedIsRunning;
      if (expectedRunning == 1 && timePast == 0) {
        debugPrint(
          '⚠️ 容错检查: 设备期望运行中但收到timePast=0，可能是硬件状态切换时的临时重置，跳过数据更新以避免数据被清0',
        );
        return;
      }
      
      // 只更新数据，不改变isRunning状态
      setState(() {
        if (isLeftDevice) {
          // 更新数据但保持当前isRunning状态
          _leftElapsedTime = Duration(seconds: timePast);
          _leftElapsedTimeInPhase = Duration(seconds: timePastInPhase);
          _leftCurrentPhase = sessionPhase;
          _leftTotalPhase = totalPhase;
          _leftPhaseDuration = Duration(minutes: totalTimeInPhase);
          _leftIntensityMode = intensityMode;
          if (_selectedPump == PumpSelection.left ||
              _selectedPump == PumpSelection.both) {
            _elapsedTime = Duration(seconds: timePast);
            _elapsedTimeInPhase = Duration(seconds: timePastInPhase);
            _currentPhase = sessionPhase;
            _totalPhase = totalPhase;
            _phaseDuration = Duration(minutes: totalTimeInPhase);
          }
        } else {
          _rightElapsedTime = Duration(seconds: timePast);
          _rightElapsedTimeInPhase = Duration(seconds: timePastInPhase);
          _rightCurrentPhase = sessionPhase;
          _rightTotalPhase = totalPhase;
          _rightPhaseDuration = Duration(minutes: totalTimeInPhase);
          _rightIntensityMode = intensityMode;
          if (_selectedPump == PumpSelection.right ||
              _selectedPump == PumpSelection.both) {
            _elapsedTime = Duration(seconds: timePast);
            _elapsedTimeInPhase = Duration(seconds: timePastInPhase);
            _currentPhase = sessionPhase;
            _totalPhase = totalPhase;
            _phaseDuration = Duration(minutes: totalTimeInPhase);
          }
        }
        _syncBothDisplayFromLeft();
      });
      // debugPrint(
      //   '✅ Control 页面已更新数据(跳过isRunning): deviceId=${update.deviceId}, timePast=${timePast}s, timePastInPhase=${timePastInPhase}s, phase=$sessionPhase',
      // );
      return;
    }

    if (isRunning == 0) {
      // Both 顺序启动里会先 stop；忽略此阶段的 idle DP105，避免清掉 hasStarted
      if (_bothStartInProgress) {
        PumpLog.i(
          'BOTH_START',
          '忽略 stop 阶段 DP105 isRunning=0 side=${isLeftDevice ? 'left' : 'right'}',
        );
        return;
      }
      // debugPrint(
      //   '⚠️ 设备已停止: $deviceSide设备，需要恢复到初始状态（sessionMode: $_sessionMode）',
      // );
      final deviceHasStarted = isLeftDevice
          ? _leftHasStarted
          : _rightHasStarted;
      final otherDeviceHasStarted = isLeftDevice
          ? _rightHasStarted
          : _leftHasStarted;
      final appIsRunning =
          deviceHasStarted ||
          (_selectedPump == PumpSelection.both && otherDeviceHasStarted);
      if (!appIsRunning) {
        // debugPrint('⚠️ 设备已停止且 app 未在运行中，跳过配置下发: $deviceSide设备');
        final initialState = await _getInitialDeviceState(isLeftDevice);
        setState(() {
          _deviceMaxDuration = null;

          if (isLeftDevice) {
            _leftIsRunning = false;
            _leftHasStarted = false;
            _leftElapsedTime = initialState['elapsedTime'] as Duration;
            _leftElapsedTimeInPhase =
                initialState['elapsedTimeInPhase'] as Duration;
            _leftCurrentPhase = initialState['currentPhase'] as int;
            _leftTotalPhase = initialState['totalPhase'] as int;
            _leftPhaseDuration = initialState['phaseDuration'] as Duration;
            _leftIntensityMode = initialState['intensityMode'] as IntensityMode;
            if (_selectedPump == PumpSelection.left) {
              _elapsedTime = _leftElapsedTime;
              _elapsedTimeInPhase = _leftElapsedTimeInPhase;
              _currentPhase = _leftCurrentPhase;
              _totalPhase = _leftTotalPhase;
              _phaseDuration = _leftPhaseDuration;
            }
          } else {
            _rightIsRunning = false;
            _rightHasStarted = false;
            _rightElapsedTime = initialState['elapsedTime'] as Duration;
            _rightElapsedTimeInPhase =
                initialState['elapsedTimeInPhase'] as Duration;
            _rightCurrentPhase = initialState['currentPhase'] as int;
            _rightTotalPhase = initialState['totalPhase'] as int;
            _rightPhaseDuration = initialState['phaseDuration'] as Duration;
            _rightIntensityMode =
                initialState['intensityMode'] as IntensityMode;
            if (_selectedPump == PumpSelection.right) {
              _elapsedTime = _rightElapsedTime;
              _elapsedTimeInPhase = _rightElapsedTimeInPhase;
              _currentPhase = _rightCurrentPhase;
              _totalPhase = _rightTotalPhase;
              _phaseDuration = _rightPhaseDuration;
            }
          }
          
          // 如果所有设备都已停止，退出独立模式
          if (_isIndividualMode && !_leftHasStarted && !_rightHasStarted) {
            _isIndividualMode = false;
            _bothNotSynchronizedCount = 0;
            debugPrint('✅ 所有设备已停止，退出独立模式');
          }
        });
        return;
      }

      final initialState = await _getInitialDeviceState(isLeftDevice);
      if (_selectedPump == PumpSelection.both) {
        final otherSideRunning = isLeftDevice
            ? _rightIsRunning
            : _leftIsRunning;
        if (otherSideRunning) {
          await _kickBothSideSessionIfNeeded(
            isLeft: isLeftDevice,
            reason: 'dp105_stopped_while_other_running',
          );
          return;
        }
        if (AppConfig.tuyaEnabled) {
          final modeDurations = await _getModeDurations();
          final totalPhase = initialState['totalPhase'] as int;
          const isCustom = true;
          if (isLeftDevice && _leftDevice != null) {
            await BleDpService.pushSessionSetting(
              _leftDevice!.bluetoothId,
              _maxDuration,
              isCustom,
              totalPhase,
              _leftStimulationSuctionLevel.toInt(),
              _leftExpressionSuctionLevel.toInt(),
              _leftHybridPatternEnabled,
              _leftHybridPatternEnabled,
              modeDurations,
            );
          } else if (isRightDevice && _rightDevice != null) {
            await BleDpService.pushSessionSetting(
              _rightDevice!.bluetoothId,
              _maxDuration,
              isCustom,
              totalPhase,
              _rightStimulationSuctionLevel.toInt(),
              _rightExpressionSuctionLevel.toInt(),
              _rightHybridPatternEnabled,
              _rightHybridPatternEnabled,
              modeDurations,
            );
          }
        }
        // if (otherSideRunning) {
        //   debugPrint('⚠️ 设备状态不一致: $deviceSide已停止，但另一边还在运行');
        // }
        setState(() {
          if (!otherSideRunning) _deviceMaxDuration = null;
          if (isLeftDevice) {
            _leftIsRunning = false;
            _leftHasStarted = false;
            _leftElapsedTime = initialState['elapsedTime'] as Duration;
            _leftElapsedTimeInPhase =
                initialState['elapsedTimeInPhase'] as Duration;
            _leftCurrentPhase = initialState['currentPhase'] as int;
            _leftTotalPhase = initialState['totalPhase'] as int;
            _leftPhaseDuration = initialState['phaseDuration'] as Duration;
            _leftIntensityMode = initialState['intensityMode'] as IntensityMode;
          } else {
            _rightIsRunning = false;
            _rightHasStarted = false;
            _rightElapsedTime = initialState['elapsedTime'] as Duration;
            _rightElapsedTimeInPhase =
                initialState['elapsedTimeInPhase'] as Duration;
            _rightCurrentPhase = initialState['currentPhase'] as int;
            _rightTotalPhase = initialState['totalPhase'] as int;
            _rightPhaseDuration = initialState['phaseDuration'] as Duration;
            _rightIntensityMode =
                initialState['intensityMode'] as IntensityMode;
          }
          if ((isLeftDevice && _selectedPump == PumpSelection.left) ||
              (isRightDevice && _selectedPump == PumpSelection.right)) {
            if (isLeftDevice) {
              _elapsedTime = _leftElapsedTime;
              _elapsedTimeInPhase = _leftElapsedTimeInPhase;
              _currentPhase = _leftCurrentPhase;
              _phaseDuration = _leftPhaseDuration;
            } else {
              _elapsedTime = _rightElapsedTime;
              _elapsedTimeInPhase = _rightElapsedTimeInPhase;
              _currentPhase = _rightCurrentPhase;
              _phaseDuration = _rightPhaseDuration;
            }
          }
          
          // 如果所有设备都已停止，退出独立模式
          if (_isIndividualMode && !_leftHasStarted && !_rightHasStarted) {
            _isIndividualMode = false;
            _bothNotSynchronizedCount = 0;
            debugPrint('✅ 所有设备已停止，退出独立模式');
          }
        });
      } else {
        if (AppConfig.tuyaEnabled) {
          final modeDurations = await _getModeDurations();
          final totalPhase = initialState['totalPhase'] as int;
          const isCustom = true;
          if (isLeftDevice && _leftDevice != null) {
            await BleDpService.pushSessionSetting(
              _leftDevice!.bluetoothId,
              _maxDuration,
              isCustom,
              totalPhase,
              _leftStimulationSuctionLevel.toInt(),
              _leftExpressionSuctionLevel.toInt(),
              _leftHybridPatternEnabled,
              _leftHybridPatternEnabled,
              modeDurations,
            );
          } else if (isRightDevice && _rightDevice != null) {
            await BleDpService.pushSessionSetting(
              _rightDevice!.bluetoothId,
              _maxDuration,
              isCustom,
              totalPhase,
              _rightStimulationSuctionLevel.toInt(),
              _rightExpressionSuctionLevel.toInt(),
              _rightHybridPatternEnabled,
              _rightHybridPatternEnabled,
              modeDurations,
            );
          }
        }
        setState(() {
          _deviceMaxDuration = null;

          if (isLeftDevice) {
            _leftIsRunning = false;
            _leftHasStarted = false;
            _leftElapsedTime = initialState['elapsedTime'] as Duration;
            _leftElapsedTimeInPhase =
                initialState['elapsedTimeInPhase'] as Duration;
            _leftCurrentPhase = initialState['currentPhase'] as int;
            _leftTotalPhase = initialState['totalPhase'] as int;
            _leftPhaseDuration = initialState['phaseDuration'] as Duration;
            _leftIntensityMode = initialState['intensityMode'] as IntensityMode;
            if (_selectedPump == PumpSelection.left) {
              _elapsedTime = _leftElapsedTime;
              _elapsedTimeInPhase = _leftElapsedTimeInPhase;
              _currentPhase = _leftCurrentPhase;
              _totalPhase = _leftTotalPhase;
              _phaseDuration = _leftPhaseDuration;
            }
          } else {
            _rightIsRunning = false;
            _rightHasStarted = false;
            _rightElapsedTime = initialState['elapsedTime'] as Duration;
            _rightElapsedTimeInPhase =
                initialState['elapsedTimeInPhase'] as Duration;
            _rightCurrentPhase = initialState['currentPhase'] as int;
            _rightTotalPhase = initialState['totalPhase'] as int;
            _rightPhaseDuration = initialState['phaseDuration'] as Duration;
            _rightIntensityMode =
                initialState['intensityMode'] as IntensityMode;
            if (_selectedPump == PumpSelection.right) {
              _elapsedTime = _rightElapsedTime;
              _elapsedTimeInPhase = _rightElapsedTimeInPhase;
              _currentPhase = _rightCurrentPhase;
              _totalPhase = _rightTotalPhase;
              _phaseDuration = _rightPhaseDuration;
            }
          }
          
          // 如果所有设备都已停止，退出独立模式
          if (_isIndividualMode && !_leftHasStarted && !_rightHasStarted) {
            _isIndividualMode = false;
            _bothNotSynchronizedCount = 0;
            debugPrint('✅ 所有设备已停止，退出独立模式');
          }
        });
      }
    } else if (isRunning == 1) {
      if (isLeftDevice && !_leftHasStarted) {
        _clearSessionLowBatteryPromptFlag(_leftDevice?.bluetoothId);
      } else if (!isLeftDevice && !_rightHasStarted) {
        _clearSessionLowBatteryPromptFlag(_rightDevice?.bluetoothId);
      }

      final appIsRunning = _getCurrentHasStarted();
      // 在独立模式下，即使 appIsRunning 为 false，也应该更新数据
      final shouldUpdate = appIsRunning || _isIndividualMode;
      if (shouldUpdate) {
        setState(() {
          _deviceMaxDuration = maxTime;

          if (isLeftDevice) {
            _leftIsRunning = true;
            _leftIntensityMode = intensityMode;
            _leftHasStarted = true;
            _leftElapsedTime = Duration(seconds: timePast);
            _leftElapsedTimeInPhase = Duration(seconds: timePastInPhase);
            _leftCurrentPhase = sessionPhase;
            _leftTotalPhase = totalPhase;
            _leftPhaseDuration = Duration(minutes: totalTimeInPhase);
            // 只有当当前选择是 left 时，才更新显示变量（独立模式下只显示当前选中设备的时间）
            if (_selectedPump == PumpSelection.left) {
              _elapsedTime = Duration(seconds: timePast);
              _elapsedTimeInPhase = Duration(seconds: timePastInPhase);
              _currentPhase = sessionPhase;
              _totalPhase = totalPhase;
              _phaseDuration = Duration(minutes: totalTimeInPhase);
            }
          } else {
            _rightIsRunning = true;
            _rightIntensityMode = intensityMode;
            _rightHasStarted = true;
            _rightElapsedTime = Duration(seconds: timePast);
            _rightElapsedTimeInPhase = Duration(seconds: timePastInPhase);
            _rightCurrentPhase = sessionPhase;
            _rightTotalPhase = totalPhase;
            _rightPhaseDuration = Duration(minutes: totalTimeInPhase);
            // 只有当当前选择是 right 时，才更新显示变量（独立模式下只显示当前选中设备的时间）
            if (_selectedPump == PumpSelection.right) {
              _elapsedTime = Duration(seconds: timePast);
              _elapsedTimeInPhase = Duration(seconds: timePastInPhase);
              _currentPhase = sessionPhase;
              _totalPhase = totalPhase;
              _phaseDuration = Duration(minutes: totalTimeInPhase);
            }
          }
          _syncBothDisplayFromLeft();
        });
      } else {
        // Both 会话已标记开始，或正在顺序启动：只更新状态，不要抢切到 left/right
        if (_selectedPump == PumpSelection.both &&
            (_bothStartInProgress || _leftHasStarted || _rightHasStarted)) {
          setState(() {
            _deviceMaxDuration = maxTime;
            if (isLeftDevice) {
              _leftIsRunning = true;
              _leftIntensityMode = intensityMode;
              _leftHasStarted = true;
              _leftElapsedTime = Duration(seconds: timePast);
              _leftElapsedTimeInPhase = Duration(seconds: timePastInPhase);
              _leftCurrentPhase = sessionPhase;
              _leftTotalPhase = totalPhase;
              _leftPhaseDuration = Duration(minutes: totalTimeInPhase);
            } else {
              _rightIsRunning = true;
              _rightIntensityMode = intensityMode;
              _rightHasStarted = true;
              _rightElapsedTime = Duration(seconds: timePast);
              _rightElapsedTimeInPhase = Duration(seconds: timePastInPhase);
              _rightCurrentPhase = sessionPhase;
              _rightTotalPhase = totalPhase;
              _rightPhaseDuration = Duration(minutes: totalTimeInPhase);
            }
            _syncBothDisplayFromLeft();
          });
          return;
        }
        // debugPrint(
        //   '⚠️ 设备手动启动: $deviceSide设备正在运行，但app未在运行状态，需要调整',
        // );
        setState(() {
          _deviceMaxDuration = maxTime;

          if (isLeftDevice) {
            _leftIsRunning = true;
            _leftIntensityMode = intensityMode;
            _leftHasStarted = true; // 标记已开始
            _leftElapsedTime = Duration(seconds: timePast);
            _leftElapsedTimeInPhase = Duration(seconds: timePastInPhase);
            _leftCurrentPhase = sessionPhase;
            _leftTotalPhase = totalPhase;
            _leftPhaseDuration = Duration(minutes: totalTimeInPhase);
            // 只有在默认的 both 页面时，才允许“硬件手动启动”自动切到对应侧；
            // 如果用户已手动选择 left/right（尤其是 both 已禁用时），不要抢回 tab。
            if (_selectedPump == PumpSelection.both) {
              // 切换选择前先同步显示变量（保存 both 的状态并恢复 left 的状态）
              _syncDisplayVariables(PumpSelection.left);
              _selectedPump = PumpSelection.left;
            }
            if (_selectedPump == PumpSelection.left ||
                _selectedPump == PumpSelection.both) {
              _elapsedTime = Duration(seconds: timePast);
              _elapsedTimeInPhase = Duration(seconds: timePastInPhase);
              _currentPhase = sessionPhase;
              _totalPhase = totalPhase;
              _phaseDuration = Duration(minutes: totalTimeInPhase);
            }
          } else {
            _rightIsRunning = true;
            _rightIntensityMode = intensityMode;
            _rightHasStarted = true;
            _rightElapsedTime = Duration(seconds: timePast);
            _rightElapsedTimeInPhase = Duration(seconds: timePastInPhase);
            _rightCurrentPhase = sessionPhase;
            _rightTotalPhase = totalPhase;
            _rightPhaseDuration = Duration(minutes: totalTimeInPhase);
            // 同上：只在默认 both 页面时自动切换
            if (_selectedPump == PumpSelection.both) {
              _syncDisplayVariables(PumpSelection.right);
              _selectedPump = PumpSelection.right;
            }
            if (_selectedPump == PumpSelection.right ||
                _selectedPump == PumpSelection.both) {
              _elapsedTime = Duration(seconds: timePast);
              _elapsedTimeInPhase = Duration(seconds: timePastInPhase);
              _currentPhase = sessionPhase;
              _totalPhase = totalPhase;
              _phaseDuration = Duration(minutes: totalTimeInPhase);
            }
          }
        });
        // _fetchDeviceConfigs(
        //   isLeftDevice ? _leftDevice : _rightDevice,
        //   isLeftDevice,
        //   intensityMode: intensityMode,
        // );
      }
    } else if (isRunning == 2) {
      // debugPrint('⚠️ 设备已暂停: $deviceSide设备，保持当前状态');
      setState(() {
        _deviceMaxDuration = maxTime;

        if (isLeftDevice) {
          _leftIsRunning = false;
          _leftIntensityMode = intensityMode;
          _leftElapsedTime = Duration(seconds: timePast);
          _leftElapsedTimeInPhase = Duration(seconds: timePastInPhase);
          _leftCurrentPhase = sessionPhase;
          _leftTotalPhase = totalPhase;
          _leftPhaseDuration = Duration(minutes: totalTimeInPhase);
          // 只有当当前选择是 left 时，才更新显示变量（独立模式下只显示当前选中设备的时间）
          if (_selectedPump == PumpSelection.left) {
            _elapsedTime = Duration(seconds: timePast);
            _elapsedTimeInPhase = Duration(seconds: timePastInPhase);
            _currentPhase = sessionPhase;
            _phaseDuration = Duration(minutes: totalTimeInPhase);
          }
        } else {
          _rightIsRunning = false;
          _rightIntensityMode = intensityMode;
          _rightElapsedTime = Duration(seconds: timePast);
          _rightElapsedTimeInPhase = Duration(seconds: timePastInPhase);
          _rightCurrentPhase = sessionPhase;
          _rightTotalPhase = totalPhase;
          _rightPhaseDuration = Duration(minutes: totalTimeInPhase);
          // 只有当当前选择是 right 时，才更新显示变量（独立模式下只显示当前选中设备的时间）
          if (_selectedPump == PumpSelection.right) {
            _elapsedTime = Duration(seconds: timePast);
            _elapsedTimeInPhase = Duration(seconds: timePastInPhase);
            _currentPhase = sessionPhase;
            _phaseDuration = Duration(minutes: totalTimeInPhase);
          }
        }
        _syncBothDisplayFromLeft();
      });
    }
    PumpLog.d(
      'control',
      'sessionStatus deviceId=${update.deviceId} isRunning=$isRunning '
      'timePast=${timePast}s phase=$sessionPhase',
    );
  }

  Future<void> _maybePromptLowBatteryAfterSessionEnd({
    required bool isLeftDevice,
    required int newIsRunning,
  }) async {
    final device = isLeftDevice ? _leftDevice : _rightDevice;
    if (device == null || device.devId == null) return;

    final wasRunning = isLeftDevice ? _leftIsRunning : _rightIsRunning;
    final hadStarted = isLeftDevice ? _leftHasStarted : _rightHasStarted;
    final pendingOp = _pendingOperations[device.devId!];

    if (!BatteryAlertLogic.isSessionEndedTransition(
      wasRunning: wasRunning,
      newIsRunning: newIsRunning,
      hadStarted: hadStarted,
      expectedIsRunning: pendingOp?.expectedIsRunning,
    )) {
      return;
    }

    if (_sessionCompleteLowBatteryShown.contains(device.bluetoothId)) return;

    final freshDevice =
        await _dbService.getDeviceByBluetoothId(device.bluetoothId);
    final battery = freshDevice?.battery ?? device.battery;
    if (!BatteryAlertLogic.isLowBatteryLevel(battery)) return;

    _sessionCompleteLowBatteryShown.add(device.bluetoothId);

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      LowBatteryDialog.show(
        context,
        LowBatteryDialogVariant.sessionComplete,
      );
    });
  }

  void _clearSessionLowBatteryPromptFlag(String? bluetoothId) {
    if (bluetoothId != null) {
      _sessionCompleteLowBatteryShown.remove(bluetoothId);
      _sessionRunningLowBatteryShown.remove(bluetoothId);
    }
  }

  void _handleBatteryLevelUpdate(DpParamUpdate update) {
    final isLeftDevice = _leftDevice?.devId == update.deviceId;
    final isRightDevice = _rightDevice?.devId == update.deviceId;
    if (!isLeftDevice && !isRightDevice) return;

    final isLeft = update.position == 'left' || isLeftDevice;
    final device = isLeft ? _leftDevice : _rightDevice;
    if (device == null) return;

    final newBattery = (update.value as num).toInt();
    final previousBattery = device.battery;

    if (!mounted) return;
    setState(() {
      if (isLeft) {
        _leftDevice = device.copyWith(battery: newBattery);
      } else {
        _rightDevice = device.copyWith(battery: newBattery);
      }
    });

    _maybePromptLowBatteryDuringSession(
      bluetoothId: device.bluetoothId,
      hasStarted: isLeft ? _leftHasStarted : _rightHasStarted,
      previousBattery: previousBattery,
      newBattery: newBattery,
    );
  }

  void _maybePromptLowBatteryDuringSession({
    required String bluetoothId,
    required bool hasStarted,
    required int previousBattery,
    required int newBattery,
  }) {
    if (!hasStarted) return;
    if (!BatteryAlertLogic.isLowBatteryTransition(
      previousBattery: previousBattery,
      newBattery: newBattery,
    )) {
      return;
    }
    if (_sessionRunningLowBatteryShown.contains(bluetoothId)) return;

    _sessionRunningLowBatteryShown.add(bluetoothId);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      LowBatteryDialog.show(
        context,
        LowBatteryDialogVariant.runningWarning,
      );
    });
  }

  // Future<void> _fetchDeviceConfigs(
  //   ConnectedDevice? device,
  //   bool isLeftDevice, {
  //   IntensityMode? intensityMode,
  // }) async {
  //   if (device == null) {
  //     debugPrint('⚠️ 设备为空，无法获取配置');
  //     return;
  //   }
  //   // debugPrint('📥 开始获取设备配置: ${device.bluetoothId}, isLeft=$isLeftDevice, intensityMode=$intensityMode');
  //   try {
  //     // try {
  //     //   await BleDpService.getDp(device.bluetoothId, DpConstants.batteryLevel);
  //     // } catch (e) {
  //     //   // debugPrint('⚠️ 获取 DP 104 失败: $e');
  //     // }
  //
  //     // 根据当前的intensityMode来决定获取哪个hybrid pattern DP
  //     // 如果intensityMode为null，则获取当前设备的intensityMode
  //     final currentIntensityMode = intensityMode ??
  //         (isLeftDevice ? _leftIntensityMode : _rightIntensityMode);
  //
  //     // 检查设备是否正在运行，以及内存中的 hybrid pattern 状态
  //     final deviceIsRunning = isLeftDevice ? _leftIsRunning : _rightIsRunning;
  //     final currentHybridPattern = isLeftDevice
  //         ? _leftHybridPatternEnabled
  //         : _rightHybridPatternEnabled;
  //
  //     // 只获取当前模式对应的hybrid pattern DP，避免同时获取两个导致覆盖
  //     if (currentIntensityMode == IntensityMode.stimulation) {
  //       // 如果设备正在运行且内存中的 hybrid pattern 是 true，不重新获取
  //       // 这样可以避免在切换侧边时，设备状态更新覆盖用户刚刚开启的 hybrid 模式
  //       if (!(deviceIsRunning && currentHybridPattern)) {
  //         _fetchDpValue(
  //           device.bluetoothId,
  //           DpConstants.stimulationHybrid,
  //           107,
  //           (v) {
  //             if (isLeftDevice) {
  //               _leftHybridPatternEnabled = v;
  //             } else {
  //               _rightHybridPatternEnabled = v;
  //             }
  //           },
  //           isBool: true,
  //         );
  //       }
  //       _fetchDpValue(
  //         device.bluetoothId,
  //         DpConstants.stimulationSucLvl,
  //         106,
  //         (v) {
  //           if (isLeftDevice) {
  //             _leftStimulationSuctionLevel = v;
  //             _persistSuctionLevel(_keyLeftStimulationSuction, v);
  //           } else {
  //             _rightStimulationSuctionLevel = v;
  //             _persistSuctionLevel(_keyRightStimulationSuction, v);
  //           }
  //         },
  //       );
  //     } else {
  //       // 如果设备正在运行且内存中的 hybrid pattern 是 true，不重新获取
  //       // 这样可以避免在切换侧边时，设备状态更新覆盖用户刚刚开启的 hybrid 模式
  //       if (!(deviceIsRunning && currentHybridPattern)) {
  //         _fetchDpValue(
  //           device.bluetoothId,
  //           DpConstants.expressionHybrid,
  //           109,
  //           (v) {
  //             if (isLeftDevice) {
  //               _leftHybridPatternEnabled = v;
  //             } else {
  //               _rightHybridPatternEnabled = v;
  //             }
  //           },
  //           isBool: true,
  //         );
  //       }
  //       _fetchDpValue(
  //         device.bluetoothId,
  //         DpConstants.expressionSucLvl,
  //         108,
  //         (v) {
  //           if (isLeftDevice) {
  //             _leftExpressionSuctionLevel = v;
  //             _persistSuctionLevel(_keyLeftExpressionSuction, v);
  //           } else {
  //             _rightExpressionSuctionLevel = v;
  //             _persistSuctionLevel(_keyRightExpressionSuction, v);
  //           }
  //         },
  //       );
  //     }
  //     // debugPrint('✅ 设备配置获取完成: ${device.bluetoothId}');
  //   } catch (e) {
  //     debugPrint('❌ 获取设备配置时发生错误: $e');
  //   }
  // }

  // Future<void> _fetchDpValue(
  //   String deviceId,
  //   String dpId,
  //   int dpNum,
  //   void Function(dynamic) onValue, {
  //   bool isBool = false,
  // }) async {
  //   try {
  //     final dp = await BleDpService.getDp(deviceId, dpId);
  //     final value = dp['value'];
  //     if (value != null) {
  //       final processed = isBool
  //           ? (value is bool
  //                 ? value
  //                 : (value == true ||
  //                       value == 1 ||
  //                       value == 'true' ||
  //                       value == '1'))
  //           : (value is num
  //                 ? value.toDouble()
  //                 : double.tryParse(value.toString()) ?? 3.0);
  //       setState(() => onValue(processed));
  //       // debugPrint('✅ 获取 DP $dpNum: $processed');
  //     }
  //   } catch (e) {
  //     debugPrint('⚠️ 获取 DP $dpNum 失败: $e');
  //   }
  // }

  void _handleDpParamUpdate(DpParamUpdate update) {
    if (update.dpId == DpConstants.batteryLevel) {
      _handleBatteryLevelUpdate(update);
      return;
    }

    final isLeftDevice = _leftDevice?.devId == update.deviceId;
    final isRightDevice = _rightDevice?.devId == update.deviceId;
    if (!isLeftDevice && !isRightDevice) return;
    final isLeft = update.position == 'left' || isLeftDevice;
    final isRight = update.position == 'right' || isRightDevice;
    final deviceHasStarted = isLeft ? _leftHasStarted : _rightHasStarted;
    if (!deviceHasStarted) {
      if (_selectedPump == PumpSelection.both) {
        debugPrint('⚠️ 设备未启动且为both模式，忽略 DP 参数更新以保持同步: ${update.dpId}');
        return;
      }
      if ((isLeft && _selectedPump != PumpSelection.left) ||
          (isRight && _selectedPump != PumpSelection.right)) {
        debugPrint('⚠️ 设备未启动且更新的设备不匹配当前选中的泵，忽略: ${update.dpId}');
        return;
      }
    }

    // DP 106/108: apply device-reported suction as-is (no mode filter, no debounce).

    // 混合模式 hybrid：防止设备旧状态覆盖用户操作
    if (update.dpId == DpConstants.stimulationHybrid) {
      final deviceId = update.deviceId;
      final deviceOperations = _recentUserOperations[deviceId];
      if (deviceOperations != null) {
        final userOp = deviceOperations[update.dpId];
        if (userOp != null) {
          final timeSinceOp = DateTime.now().difference(userOp.timestamp).inMilliseconds;
          if (timeSinceOp < _ignoreDeviceUpdateWindowMs) {
            final deviceValue = (update.value as bool);
            final userExpectedBool = userOp.expectedValue >= 0.5;
            if (deviceValue != userExpectedBool) {
              final currentValue = isLeft ? _leftHybridPatternEnabled : _rightHybridPatternEnabled;
              if (currentValue == userExpectedBool) {
                return; // 当前 UI 已是用户期望，忽略设备旧值
              }
            } else {
              deviceOperations.remove(update.dpId);
              if (deviceOperations.isEmpty) {
                _recentUserOperations.remove(deviceId);
              }
            }
          } else {
            deviceOperations.remove(update.dpId);
            if (deviceOperations.isEmpty) {
              _recentUserOperations.remove(deviceId);
            }
          }
        }
      }
    }

    setState(() {
      switch (update.dpId) {
        case DpConstants.stimulationSucLvl:
          final v = (update.value as num).toDouble();
          if (isLeft) {
            _leftStimulationSuctionLevel = v;
          } else if (isRight) {
            _rightStimulationSuctionLevel = v;
          }
          debugPrint(
            '✅ DP106 stimulationSucLvl deviceId=${update.deviceId} '
            'side=${isLeft ? 'L' : 'R'} value=$v',
          );
          break;
        case DpConstants.expressionSucLvl:
          final v = (update.value as num).toDouble();
          if (isLeft) {
            _leftExpressionSuctionLevel = v;
          } else if (isRight) {
            _rightExpressionSuctionLevel = v;
          }
          debugPrint(
            '✅ DP108 expressionSucLvl deviceId=${update.deviceId} '
            'side=${isLeft ? 'L' : 'R'} value=$v',
          );
          break;
        case DpConstants.stimulationHybrid:
          final v = update.value as bool;
          if (isLeft) {
            _leftHybridPatternEnabled = v;
            // debugPrint('✅ 更新左侧刺激混合模式: $v');
          } else if (isRight) {
            _rightHybridPatternEnabled = v;
            // debugPrint('✅ 更新右侧刺激混合模式: $v');
          }
          break;
        // case DpConstants.expressionHybrid:
        //   final v = update.value as bool;
        //   if (isLeft) {
        //     _leftHybridPatternEnabled = v;
        //     // debugPrint('✅ 更新左侧吸乳混合模式: $v');
        //   } else if (isRight) {
        //     _rightHybridPatternEnabled = v;
        //     // debugPrint('✅ 更新右侧吸乳混合模式: $v');
        //   }
        //   break;
      }
    });
    if (update.dpId == DpConstants.stimulationSucLvl) {
      if (isLeft) {
        _persistSuctionLevel(_keyLeftStimulationSuction, _leftStimulationSuctionLevel);
      } else if (isRight) {
        _persistSuctionLevel(_keyRightStimulationSuction, _rightStimulationSuctionLevel);
      }
    } else if (update.dpId == DpConstants.expressionSucLvl) {
      if (isLeft) {
        _persistSuctionLevel(_keyLeftExpressionSuction, _leftExpressionSuctionLevel);
      } else if (isRight) {
        _persistSuctionLevel(_keyRightExpressionSuction, _rightExpressionSuctionLevel);
      }
    } else if (update.dpId == DpConstants.stimulationHybrid) {
      final v = update.value as bool;
      if (isLeft) {
        _persistHybridPattern(_keyLeftHybridPattern, v);
      } else if (isRight) {
        _persistHybridPattern(_keyRightHybridPattern, v);
      }
    }
    if (_selectedPump == PumpSelection.both &&
        (isLeft ? _leftIsRunning : _rightIsRunning)) {
      // debugPrint(
      //   '⚠️ Both 模式下设备参数更新，可能触发不同步: ${update.dpId}, position=${update.position}',
      // );
    }
  }

  Future<void> _loadDevices() async {
    final devices = await _dbService.getRememberedDevices();
    setState(() {
      try {
        _leftDevice = devices.firstWhere((device) => device.position == 'left');
      } catch (e) {
        _leftDevice = null;
      }

      try {
        _rightDevice = devices.firstWhere(
          (device) => device.position == 'right',
        );
      } catch (e) {
        _rightDevice = null;
      }
    });
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) _refreshDeviceStatus();
    });
  }

  Future<void> _refreshDeviceStatus() async {
    try {
      final devices = await _dbService.getRememberedDevices();
      if (!mounted) return;

      setState(() {
        ConnectedDevice? newLeftDevice;
        ConnectedDevice? newRightDevice;
        try {
          newLeftDevice = devices.firstWhere(
            (device) => device.position == 'left',
          );
        } catch (e) {
          newLeftDevice = null;
        }
        try {
          newRightDevice = devices.firstWhere(
            (device) => device.position == 'right',
          );
        } catch (e) {
          newRightDevice = null;
        }
        final wasLeftConnected =
            _leftDevice != null &&
            _leftDevice!.isRemembered &&
            _leftDevice!.isRunning;
        final isLeftConnected =
            newLeftDevice != null &&
            newLeftDevice.isRemembered &&
            newLeftDevice.isRunning;
        if ((wasLeftConnected && !isLeftConnected && _leftHasStarted) ||
            (_leftDevice != null && newLeftDevice == null && _leftHasStarted)) {
          if (_selectedPump == PumpSelection.both &&
              _rightHasStarted &&
              _rightIsRunning) {
            debugPrint(
              '⚠️ Both 运行中左泵 DB 瞬断，保留 started 并补发 start',
            );
            unawaited(
              _kickBothSideSessionIfNeeded(
                isLeft: true,
                reason: 'db_refresh_left_offline',
              ),
            );
          } else {
            debugPrint('⚠️ 左设备断线或移除，清除启动状态');
            _leftHasStarted = false;
            _leftIsRunning = false;
          }
        }
        if (!wasLeftConnected &&
            isLeftConnected &&
            _selectedPump == PumpSelection.both &&
            _rightHasStarted &&
            _rightIsRunning) {
          unawaited(
            _kickBothSideSessionIfNeeded(
              isLeft: true,
              reason: 'db_refresh_left_reconnected',
            ),
          );
        }
        final wasRightConnected =
            _rightDevice != null &&
            _rightDevice!.isRemembered &&
            _rightDevice!.isRunning;
        final isRightConnected =
            newRightDevice != null &&
            newRightDevice.isRemembered &&
            newRightDevice.isRunning;
        if ((wasRightConnected && !isRightConnected && _rightHasStarted) ||
            (_rightDevice != null &&
                newRightDevice == null &&
                _rightHasStarted)) {
          if (_selectedPump == PumpSelection.both &&
              _leftHasStarted &&
              _leftIsRunning) {
            debugPrint(
              '⚠️ Both 运行中右泵 DB 瞬断，保留 started 并补发 start',
            );
            unawaited(
              _kickBothSideSessionIfNeeded(
                isLeft: false,
                reason: 'db_refresh_right_offline',
              ),
            );
          } else {
            debugPrint('⚠️ 右设备断线或移除，清除启动状态');
            _rightHasStarted = false;
            _rightIsRunning = false;
          }
        }
        if (!wasRightConnected &&
            isRightConnected &&
            _selectedPump == PumpSelection.both &&
            _leftHasStarted &&
            _leftIsRunning) {
          unawaited(
            _kickBothSideSessionIfNeeded(
              isLeft: false,
              reason: 'db_refresh_right_reconnected',
            ),
          );
        }
        _leftDevice = newLeftDevice;
        _rightDevice = newRightDevice;
      });
    } catch (e) {
      debugPrint('❌ 刷新设备状态失败: $e');
    }
  }

  Future<void> _publishDeviceSymbolThrice(
    String bluetoothId,
    String position,
  ) async {
    for (int i = 0; i < 3; i++) {
      await BleDpService.publishDp(
        bluetoothId,
        DpConstants.deviceSymbol,
        position,
      );
      if (i < 2) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> _updateDeviceConnectionStatus(
    ConnectedDevice device,
    bool isRunning,
  ) async {
    if (!device.isRemembered) return;

    final updatedDevice = device.copyWith(isRunning: isRunning);
    await _dbService.updateDevice(updatedDevice);

    if (isRunning && !device.isRunning) {
      unawaited(_publishDeviceSymbolThrice(device.bluetoothId, device.position));
    }

    if (!mounted) return;
    setState(() {
      if (device.position == 'left') {
        _leftDevice = updatedDevice;
      } else {
        _rightDevice = updatedDevice;
      }
    });
  }

  Future<void> _reconnectDevice(ConnectedDevice device) async {
    if (!AppConfig.tuyaEnabled) return;
    if (_reconnectingDeviceIds.contains(device.bluetoothId)) return;

    setState(() {
      _reconnectingDeviceIds.add(device.bluetoothId);
    });

    var connected = false;
    try {
      final readyHomeId = await TuyaSdkService.ensureHomeReady(
        timeout: const Duration(seconds: 15),
      );
      if (readyHomeId == null || readyHomeId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('涂鸦初始化未完成，请检查网络后重试')),
          );
        }
        return;
      }

      if (device.devId != null &&
          DeviceReconnectPolicy.shouldHealRunningFromDp(devId: device.devId!)) {
        connected = true;
      } else {
        final isOnline =
            await connectionChannel.invokeMethod('isDeviceOnline', {
                  'deviceId': device.nativeBleId,
                })
                as bool? ??
            false;

        if (isOnline) {
          connected = true;
        } else {
          final connectionResults =
              await connectionChannel.invokeMethod('connectBleDevices', {
                    'deviceIds': [device.nativeBleId],
                  })
                  as Map<dynamic, dynamic>?;

          connected =
              connectionResults?[device.nativeBleId] as bool? ?? false;

          if (!connected &&
              device.devId != null &&
              DeviceReconnectPolicy.shouldHealRunningFromDp(
                devId: device.devId!,
              )) {
            connected = true;
          }
        }
      }

      if (connected) {
        await _updateDeviceConnectionStatus(device, true);
        try {
          final bypassOnline = device.devId != null &&
              DeviceReconnectPolicy.shouldHealRunningFromDp(
                devId: device.devId!,
              );
          await DeviceListenerService.registerIfRunning(
            device.copyWith(isRunning: true),
            bypassOnlineCheck: bypassOnline,
          );
        } catch (e) {
          debugPrint('注册设备监听器失败: $e');
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.reconnectFailed)),
        );
      }
    } catch (e) {
      debugPrint('手动重连失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.reconnectFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _reconnectingDeviceIds.remove(device.bluetoothId);
        });
      } else {
        _reconnectingDeviceIds.remove(device.bluetoothId);
      }
    }
  }

  /// 从数据库加载吸力级别配置；若不存在则用默认值 3 并写入数据库
  Future<void> _loadSuctionLevelSettings() async {
    const defaultLevel = 1.0;
    double leftStim = defaultLevel;
    double leftExpr = defaultLevel;
    double rightStim = defaultLevel;
    double rightExpr = defaultLevel;

    final sLeftStim = await _dbService.getSettingByKey(_keyLeftStimulationSuction);
    final sLeftExpr = await _dbService.getSettingByKey(_keyLeftExpressionSuction);
    final sRightStim = await _dbService.getSettingByKey(_keyRightStimulationSuction);
    final sRightExpr = await _dbService.getSettingByKey(_keyRightExpressionSuction);

    if (sLeftStim != null) leftStim = double.tryParse(sLeftStim.value) ?? defaultLevel;
    if (sLeftExpr != null) leftExpr = double.tryParse(sLeftExpr.value) ?? defaultLevel;
    if (sRightStim != null) rightStim = double.tryParse(sRightStim.value) ?? defaultLevel;
    if (sRightExpr != null) rightExpr = double.tryParse(sRightExpr.value) ?? defaultLevel;

    if (sLeftStim == null) await _persistSuctionLevel(_keyLeftStimulationSuction, leftStim);
    if (sLeftExpr == null) await _persistSuctionLevel(_keyLeftExpressionSuction, leftExpr);
    if (sRightStim == null) await _persistSuctionLevel(_keyRightStimulationSuction, rightStim);
    if (sRightExpr == null) await _persistSuctionLevel(_keyRightExpressionSuction, rightExpr);

    if (!mounted) return;
    setState(() {
      _leftStimulationSuctionLevel = leftStim.clamp(1.0, 9.0);
      _leftExpressionSuctionLevel = leftExpr.clamp(1.0, 9.0);
      _rightStimulationSuctionLevel = rightStim.clamp(1.0, 9.0);
      _rightExpressionSuctionLevel = rightExpr.clamp(1.0, 9.0);
    });
  }

  /// 将单个吸力级别持久化到数据库
  Future<void> _persistSuctionLevel(String key, double value) async {
    final valueStr = value.clamp(1.0, 9.0).toString();
    final existing = await _dbService.getSettingByKey(key);
    if (existing != null) {
      await _dbService.updateSettingByKey(key, valueStr);
    } else {
      await _dbService.insertSetting(
        Setting(key: key, desc: _descSuctionLevel, value: valueStr),
      );
    }
  }

  /// 将当前四个吸力级别全部持久化到数据库
  Future<void> _persistAllSuctionLevels() async {
    await _persistSuctionLevel(_keyLeftStimulationSuction, _leftStimulationSuctionLevel);
    await _persistSuctionLevel(_keyLeftExpressionSuction, _leftExpressionSuctionLevel);
    await _persistSuctionLevel(_keyRightStimulationSuction, _rightStimulationSuctionLevel);
    await _persistSuctionLevel(_keyRightExpressionSuction, _rightExpressionSuctionLevel);
  }

  /// 从数据库加载混合模式配置；若不存在则用默认值 false 并写入数据库
  Future<void> _loadHybridPatternSettings() async {
    const defaultEnabled = false;
    bool leftEnabled = defaultEnabled;
    bool rightEnabled = defaultEnabled;

    final sLeft = await _dbService.getSettingByKey(_keyLeftHybridPattern);
    final sRight = await _dbService.getSettingByKey(_keyRightHybridPattern);

    if (sLeft != null) leftEnabled = sLeft.value == 'true';
    if (sRight != null) rightEnabled = sRight.value == 'true';

    if (sLeft == null) await _persistHybridPattern(_keyLeftHybridPattern, leftEnabled);
    if (sRight == null) await _persistHybridPattern(_keyRightHybridPattern, rightEnabled);

    if (!mounted) return;
    setState(() {
      _leftHybridPatternEnabled = leftEnabled;
      _rightHybridPatternEnabled = rightEnabled;
    });
  }

  /// 将混合模式持久化到数据库
  Future<void> _persistHybridPattern(String key, bool value) async {
    final valueStr = value.toString();
    final existing = await _dbService.getSettingByKey(key);
    if (existing != null) {
      await _dbService.updateSettingByKey(key, valueStr);
    } else {
      await _dbService.insertSetting(
        Setting(key: key, desc: _descHybridPattern, value: valueStr),
      );
    }
  }

  /// 记录用户混合模式操作，用于防止设备返回的旧状态覆盖用户操作
  void _recordUserHybridPatternOperation(ConnectedDevice? device, String dpId, bool value) {
    if (device?.devId == null) return;
    final deviceId = device!.devId!;
    if (!_recentUserOperations.containsKey(deviceId)) {
      _recentUserOperations[deviceId] = {};
    }
    _recentUserOperations[deviceId]![dpId] = _UserOperation(
      expectedValue: value ? 1.0 : 0.0,
      timestamp: DateTime.now(),
      dpId: dpId,
    );
  }

  Future<void> _loadCustomFlowDescription() async {
    final phases = await CustomFlowConfig.loadPhasesForSelectedTab(_dbService);
    setState(
      () => _customFlowDescription = CustomFlowConfig.formatDescription(phases),
    );
  }

  List<Map<String, int>> _phasesToModeDurations(List<Phase> phases) {
    return phases
        .map(
          (p) => {
            p.mode == PhaseMode.stimulation ? 'stimulation' : 'expression':
                p.duration,
          },
        )
        .toList();
  }

  Future<List<Phase>> _getActiveCustomPhases() async {
    return CustomFlowConfig.loadPhasesForSelectedTab(_dbService);
  }

  Future<IntensityMode?> _getFirstPhaseIntensityMode() async {
    switch (_sessionMode) {
      case SessionMode.beginner:
      case SessionMode.boostMilk:
        return IntensityMode.stimulation;
      case SessionMode.custom:
        final phases = await _getActiveCustomPhases();
        if (phases.isNotEmpty) {
          return phases.first.mode == PhaseMode.stimulation
              ? IntensityMode.stimulation
              : IntensityMode.expression;
        }
        return null;
      case SessionMode.defaultMode:
        return null;
    }
  }

  Future<int> _getTotalPhases() async {
    switch (_sessionMode) {
      case SessionMode.beginner:
      case SessionMode.boostMilk:
        return 2;
      case SessionMode.custom:
        final phases = await _getActiveCustomPhases();
        return phases.isNotEmpty ? phases.length : 2;
      case SessionMode.defaultMode:
        return 2;
    }
  }

  Future<List<Map<String, int>>> _getModeDurations() async {
    switch (_sessionMode) {
      case SessionMode.beginner:
        return [
          {'stimulation': 2},
          {'expression': 5},
        ];
      case SessionMode.boostMilk:
        return [
          {'stimulation': 2},
          {'expression': 3},
        ];
      case SessionMode.custom:
        final phases = await _getActiveCustomPhases();
        if (phases.isNotEmpty) {
          return _phasesToModeDurations(phases);
        }
        return _phasesToModeDurations(CustomFlowConfig.defaultCustomPhases);
      case SessionMode.defaultMode:
        return [
          {'stimulation': 2},
          {'expression': 5},
        ];
    }
  }

  Future<Map<String, dynamic>> _getInitialDeviceState(bool isLeft) async {
    Map<String, dynamic>? result;

    switch (_sessionMode) {
      case SessionMode.beginner:
        result = {
          'elapsedTime': Duration.zero,
          'elapsedTimeInPhase': Duration.zero,
          'currentPhase': 1,
          'totalPhase': 2,
          'phaseDuration': const Duration(minutes: 2),
          'intensityMode': IntensityMode.stimulation,
        };
        break;
      case SessionMode.boostMilk:
        result = {
          'elapsedTime': Duration.zero,
          'elapsedTimeInPhase': Duration.zero,
          'currentPhase': 1,
          'totalPhase': 2,
          'phaseDuration': const Duration(minutes: 2),
          'intensityMode': IntensityMode.stimulation,
        };
        break;
      case SessionMode.custom:
        final phases = await _getActiveCustomPhases();
        if (phases.isNotEmpty) {
          final firstPhase = phases.first;
          result = {
            'elapsedTime': Duration.zero,
            'elapsedTimeInPhase': Duration.zero,
            'currentPhase': 1,
            'totalPhase': phases.length,
            'phaseDuration': Duration(minutes: firstPhase.duration),
            'intensityMode': firstPhase.mode == PhaseMode.stimulation
                ? IntensityMode.stimulation
                : IntensityMode.expression,
          };
        }
        break;
      case SessionMode.defaultMode:
        break;
    }

    return result ?? {
      'elapsedTime': Duration.zero,
      'elapsedTimeInPhase': Duration.zero,
      'currentPhase': 1,
      'totalPhase': 2,
      'phaseDuration': const Duration(minutes: 2),
      'intensityMode': IntensityMode.stimulation,
    };
  }

  IntensityMode _getCurrentIntensityMode() {
    switch (_selectedPump) {
      case PumpSelection.left:
        return _leftIntensityMode;
      case PumpSelection.right:
        return _rightIntensityMode;
      case PumpSelection.both:
        return _leftIntensityMode;
    }
  }

  void _setCurrentIntensityMode(IntensityMode mode) {
    switch (_selectedPump) {
      case PumpSelection.left:
        _leftIntensityMode = mode;
        break;
      case PumpSelection.right:
        _rightIntensityMode = mode;
        break;
      case PumpSelection.both:
        _leftIntensityMode = mode;
        _rightIntensityMode = mode;
        break;
    }
  }

  double _getCurrentSuctionLevel() {
    final intensityMode = _getCurrentIntensityMode();
    double value;
    switch (_selectedPump) {
      case PumpSelection.left:
        value = intensityMode == IntensityMode.stimulation
            ? _leftStimulationSuctionLevel
            : _leftExpressionSuctionLevel;
        break;
      case PumpSelection.right:
        value = intensityMode == IntensityMode.stimulation
            ? _rightStimulationSuctionLevel
            : _rightExpressionSuctionLevel;
        break;
      case PumpSelection.both:
        value = intensityMode == IntensityMode.stimulation
            ? _leftStimulationSuctionLevel
            : _leftExpressionSuctionLevel;
        break;
    }
    return value.clamp(1.0, 9.0);
  }

  void _setCurrentSuctionLevel(double value) {
    final intensityMode = _getCurrentIntensityMode();
    switch (_selectedPump) {
      case PumpSelection.left:
        if (intensityMode == IntensityMode.stimulation) {
          _leftStimulationSuctionLevel = value;
        } else {
          _leftExpressionSuctionLevel = value;
        }
        break;
      case PumpSelection.right:
        if (intensityMode == IntensityMode.stimulation) {
          _rightStimulationSuctionLevel = value;
        } else {
          _rightExpressionSuctionLevel = value;
        }
        break;
      case PumpSelection.both:
        if (intensityMode == IntensityMode.stimulation) {
          _leftStimulationSuctionLevel = value;
          _rightStimulationSuctionLevel = value;
        } else {
          _leftExpressionSuctionLevel = value;
          _rightExpressionSuctionLevel = value;
        }
        break;
    }
  }

  // 记录用户操作，用于防止设备返回的旧状态覆盖用户操作
  void _recordUserSuctionLevelOperation(ConnectedDevice? device, String dpId, double value) {
    if (device?.devId == null) return;
    final deviceId = device!.devId!;
    if (!_recentUserOperations.containsKey(deviceId)) {
      _recentUserOperations[deviceId] = {};
    }
    _recentUserOperations[deviceId]![dpId] = _UserOperation(
      expectedValue: value,
      timestamp: DateTime.now(),
      dpId: dpId,
    );
  }

  void _adjustSuctionLevel(int delta) {
    final currentLevel = _getCurrentSuctionLevel();
    final newLevel = (currentLevel + delta).clamp(1.0, 9.0);
    
    if (newLevel == currentLevel) {
      return; // 已达到边界，不执行任何操作
    }

    // 更新UI
    setState(() {
      _setCurrentSuctionLevel(newLevel);
    });
    _persistAllSuctionLevels();

    // 如果设备已启动，发送到设备并记录用户操作
    final currentHasStarted = _getCurrentHasStarted();
    if (currentHasStarted) {
      final intValue = newLevel.toInt();
      final intensityMode = _getCurrentIntensityMode();
      final dpId = intensityMode == IntensityMode.stimulation
          ? DpConstants.stimulationSucLvl
          : DpConstants.expressionSucLvl;
      
      if (_selectedPump == PumpSelection.both) {
        // both 模式：发送到两个设备
        if (intensityMode == IntensityMode.stimulation) {
          if (_leftDevice != null) {
            _recordUserSuctionLevelOperation(_leftDevice, dpId, newLevel);
            BleDpService.publishDp(
              _leftDevice!.bluetoothId,
              DpConstants.stimulationSucLvl,
              intValue,
            );
          }
          if (_rightDevice != null) {
            _recordUserSuctionLevelOperation(_rightDevice, dpId, newLevel);
            BleDpService.publishDp(
              _rightDevice!.bluetoothId,
              DpConstants.stimulationSucLvl,
              intValue,
            );
          }
        } else {
          if (_leftDevice != null) {
            _recordUserSuctionLevelOperation(_leftDevice, dpId, newLevel);
            BleDpService.publishDp(
              _leftDevice!.bluetoothId,
              DpConstants.expressionSucLvl,
              intValue,
            );
          }
          if (_rightDevice != null) {
            _recordUserSuctionLevelOperation(_rightDevice, dpId, newLevel);
            BleDpService.publishDp(
              _rightDevice!.bluetoothId,
              DpConstants.expressionSucLvl,
              intValue,
            );
          }
        }
      } else if (_selectedPump == PumpSelection.left &&
          _leftDevice != null) {
        // left 模式：只发送到左侧设备
        _recordUserSuctionLevelOperation(_leftDevice, dpId, newLevel);
        if (intensityMode == IntensityMode.stimulation) {
          BleDpService.publishDp(
            _leftDevice!.bluetoothId,
            DpConstants.stimulationSucLvl,
            intValue,
          );
        } else {
          BleDpService.publishDp(
            _leftDevice!.bluetoothId,
            DpConstants.expressionSucLvl,
            intValue,
          );
        }
      } else if (_selectedPump == PumpSelection.right &&
          _rightDevice != null) {
        // right 模式：只发送到右侧设备
        _recordUserSuctionLevelOperation(_rightDevice, dpId, newLevel);
        if (intensityMode == IntensityMode.stimulation) {
          BleDpService.publishDp(
            _rightDevice!.bluetoothId,
            DpConstants.stimulationSucLvl,
            intValue,
          );
        } else {
          BleDpService.publishDp(
            _rightDevice!.bluetoothId,
            DpConstants.expressionSucLvl,
            intValue,
          );
        }
      }
    }
  }

  // 获取左侧吸力级别
  double _getLeftSuctionLevel() {
    final intensityMode = _leftIntensityMode;
    return (intensityMode == IntensityMode.stimulation
            ? _leftStimulationSuctionLevel
            : _leftExpressionSuctionLevel)
        .clamp(1.0, 9.0);
  }

  // 获取右侧吸力级别
  double _getRightSuctionLevel() {
    final intensityMode = _rightIntensityMode;
    return (intensityMode == IntensityMode.stimulation
            ? _rightStimulationSuctionLevel
            : _rightExpressionSuctionLevel)
        .clamp(1.0, 9.0);
  }

  // 调整左侧吸力级别
  void _adjustLeftSuctionLevel(int delta) {
    final currentLevel = _getLeftSuctionLevel();
    final newLevel = (currentLevel + delta).clamp(1.0, 9.0);
    
    if (newLevel == currentLevel) {
      return;
    }

    setState(() {
      final intensityMode = _leftIntensityMode;
      if (intensityMode == IntensityMode.stimulation) {
        _leftStimulationSuctionLevel = newLevel;
      } else {
        _leftExpressionSuctionLevel = newLevel;
      }
    });
    _persistSuctionLevel(_keyLeftStimulationSuction, _leftStimulationSuctionLevel);
    _persistSuctionLevel(_keyLeftExpressionSuction, _leftExpressionSuctionLevel);

    if (_leftHasStarted && _leftDevice != null) {
      final intValue = newLevel.toInt();
      final intensityMode = _leftIntensityMode;
      final dpId = intensityMode == IntensityMode.stimulation
          ? DpConstants.stimulationSucLvl
          : DpConstants.expressionSucLvl;
      _recordUserSuctionLevelOperation(_leftDevice, dpId, newLevel);
      if (intensityMode == IntensityMode.stimulation) {
        BleDpService.publishDp(
          _leftDevice!.bluetoothId,
          DpConstants.stimulationSucLvl,
          intValue,
        );
      } else {
        BleDpService.publishDp(
          _leftDevice!.bluetoothId,
          DpConstants.expressionSucLvl,
          intValue,
        );
      }
    }
  }

  // 调整右侧吸力级别
  void _adjustRightSuctionLevel(int delta) {
    final currentLevel = _getRightSuctionLevel();
    final newLevel = (currentLevel + delta).clamp(1.0, 9.0);
    
    if (newLevel == currentLevel) {
      return;
    }

    setState(() {
      final intensityMode = _rightIntensityMode;
      if (intensityMode == IntensityMode.stimulation) {
        _rightStimulationSuctionLevel = newLevel;
      } else {
        _rightExpressionSuctionLevel = newLevel;
      }
    });
    _persistSuctionLevel(_keyRightStimulationSuction, _rightStimulationSuctionLevel);
    _persistSuctionLevel(_keyRightExpressionSuction, _rightExpressionSuctionLevel);

    if (_rightHasStarted && _rightDevice != null) {
      final intValue = newLevel.toInt();
      final intensityMode = _rightIntensityMode;
      final dpId = intensityMode == IntensityMode.stimulation
          ? DpConstants.stimulationSucLvl
          : DpConstants.expressionSucLvl;
      _recordUserSuctionLevelOperation(_rightDevice, dpId, newLevel);
      if (intensityMode == IntensityMode.stimulation) {
        BleDpService.publishDp(
          _rightDevice!.bluetoothId,
          DpConstants.stimulationSucLvl,
          intValue,
        );
      } else {
        BleDpService.publishDp(
          _rightDevice!.bluetoothId,
          DpConstants.expressionSucLvl,
          intValue,
        );
      }
    }
  }

  bool _getCurrentHybridPattern() {
    switch (_selectedPump) {
      case PumpSelection.left:
        return _leftHybridPatternEnabled;
      case PumpSelection.right:
        return _rightHybridPatternEnabled;
      case PumpSelection.both:
        return _leftHybridPatternEnabled;
    }
  }

  void _setCurrentHybridPattern(bool value) {
    switch (_selectedPump) {
      case PumpSelection.left:
        _leftHybridPatternEnabled = value;
        break;
      case PumpSelection.right:
        _rightHybridPatternEnabled = value;
        break;
      case PumpSelection.both:
        _leftHybridPatternEnabled = value;
        _rightHybridPatternEnabled = value;
        break;
    }
  }

  Future<void> _applyHybridPatternChange(bool value) async {
    setState(() => _setCurrentHybridPattern(value));

    final persistPlan = ControlHybridPatternLogic.persistPlan(_selectedPump);
    if (persistPlan.persistLeft) {
      await _persistHybridPattern(_keyLeftHybridPattern, value);
    }
    if (persistPlan.persistRight) {
      await _persistHybridPattern(_keyRightHybridPattern, value);
    }

    final publishPlan = ControlHybridPatternLogic.publishPlan(
      selectedPump: _selectedPump,
      sessionHasStarted: _getCurrentHasStarted(),
    );
    if (!publishPlan.publishLeft && !publishPlan.publishRight) {
      return;
    }

    if (publishPlan.publishLeft && _leftDevice != null) {
      _recordUserHybridPatternOperation(
        _leftDevice,
        DpConstants.stimulationHybrid,
        value,
      );
    }
    if (publishPlan.publishRight && _rightDevice != null) {
      _recordUserHybridPatternOperation(
        _rightDevice,
        DpConstants.stimulationHybrid,
        value,
      );
    }

    _publishDpToDevices(DpConstants.stimulationHybrid, value);
  }

  bool _getCurrentIsRunning() {
    switch (_selectedPump) {
      case PumpSelection.left:
        return _leftIsRunning;
      case PumpSelection.right:
        return _rightIsRunning;
      case PumpSelection.both:
        if (_bothStartInProgress) return true;
        return _leftIsRunning && _rightIsRunning;
    }
  }

  void _setCurrentIsRunning(bool value) {
    switch (_selectedPump) {
      case PumpSelection.left:
        _leftIsRunning = value;
        break;
      case PumpSelection.right:
        _rightIsRunning = value;
        break;
      case PumpSelection.both:
        _leftIsRunning = value;
        _rightIsRunning = value;
        break;
    }
  }

  bool _getCurrentHasStarted() {
    switch (_selectedPump) {
      case PumpSelection.left:
        return _leftHasStarted;
      case PumpSelection.right:
        return _rightHasStarted;
      case PumpSelection.both:
        return _leftHasStarted || _rightHasStarted;
    }
  }

  void _recordPendingOperation(ConnectedDevice? device, int expectedIsRunning) {
    if (device == null || device.devId == null) {
      debugPrint('⚠️ 无法记录待确认操作: 设备为空或 devId 为空');
      return;
    }
    _pendingOperations[device.devId!] = _PendingOperation(
      expectedIsRunning: expectedIsRunning,
      timestamp: DateTime.now(),
    );
    debugPrint('📝 记录待确认操作: devId=${device.devId}, 期望状态=$expectedIsRunning');
  }

  void _setCurrentHasStarted(bool value) {
    switch (_selectedPump) {
      case PumpSelection.left:
        _leftHasStarted = value;
        break;
      case PumpSelection.right:
        _rightHasStarted = value;
        break;
      case PumpSelection.both:
        _leftHasStarted = value;
        _rightHasStarted = value;
        break;
    }
  }

  /// 同步显示变量：根据当前选择的泵，将对应的状态同步到显示变量
  /// [newSelection] 新的泵选择，如果为 null 则使用当前的 _selectedPump
  void _syncDisplayVariables([PumpSelection? newSelection]) {
    final oldSelection = _selectedPump;
    final targetSelection = newSelection ?? _selectedPump;
    
    // 如果提供了新的选择，先保存旧选择的状态（SessionMode 和 Max Duration）
    if (newSelection != null && oldSelection != newSelection) {
      _pumpSessionModes[oldSelection] = _sessionMode;
      _pumpMaxDurations[oldSelection] = _maxDuration;
    }

    // 恢复目标选择的状态
    _sessionMode = _pumpSessionModes[targetSelection] ?? SessionMode.defaultMode;
    _maxDuration = _pumpMaxDurations[targetSelection] ?? 20;

    // 同步时间相关的显示变量
    switch (targetSelection) {
      case PumpSelection.left:
        _elapsedTime = _leftElapsedTime;
        _elapsedTimeInPhase = _leftElapsedTimeInPhase;
        _currentPhase = _leftCurrentPhase;
        _totalPhase = _leftTotalPhase;
        _phaseDuration = _leftPhaseDuration;
        break;
      case PumpSelection.right:
        _elapsedTime = _rightElapsedTime;
        _elapsedTimeInPhase = _rightElapsedTimeInPhase;
        _currentPhase = _rightCurrentPhase;
        _totalPhase = _rightTotalPhase;
        _phaseDuration = _rightPhaseDuration;
        break;
      case PumpSelection.both:
        // both模式下，使用左侧的值作为显示（或者可以根据需要选择其他逻辑）
        _elapsedTime = _leftElapsedTime;
        _elapsedTimeInPhase = _leftElapsedTimeInPhase;
        _currentPhase = _leftCurrentPhase;
        _totalPhase = _leftTotalPhase;
        _phaseDuration = _leftPhaseDuration;
        break;
    }
  }

  /// both 模式下且未进入独立模式时，统一用左侧时间展示，
  /// 避免左右设备轻微时差导致计时显示抖动。
  bool _shouldShowBothUsingLeft() {
    return ControlTimerDisplayLogic.useBothUnifiedRules(
      isBothSelected: _selectedPump == PumpSelection.both,
      isIndividualMode: _isIndividualMode,
    );
  }

  bool _bothRunningTogether() {
    return ControlTimerDisplayLogic.bothRunningTogether(
      leftHasStarted: _leftHasStarted,
      rightHasStarted: _rightHasStarted,
    );
  }

  bool _getTimerDisplayHasStarted() {
    return ControlTimerDisplayLogic.timerDisplayHasStarted(
      useBothUnifiedRules: _shouldShowBothUsingLeft(),
      leftHasStarted: _leftHasStarted,
      rightHasStarted: _rightHasStarted,
      singleSideHasStarted: _getCurrentHasStarted(),
    );
  }

  bool _getTimerInitialStateIsLeft() {
    return ControlTimerDisplayLogic.timerInitialStateUsesLeftDevice(
      isLeftSelected: _selectedPump == PumpSelection.left,
      isBothSelected: _selectedPump == PumpSelection.both,
    );
  }

  /// 将主展示时间同步为左侧设备时间（仅在 both 非独立模式生效）。
  void _syncBothDisplayFromLeft() {
    if (!_shouldShowBothUsingLeft()) return;
    _elapsedTime = _leftElapsedTime;
    _elapsedTimeInPhase = _leftElapsedTimeInPhase;
    _currentPhase = _leftCurrentPhase;
    _totalPhase = _leftTotalPhase;
    _phaseDuration = _leftPhaseDuration;
  }

  Future<IntensityMode> _getDisplayIntensityMode() async {
    final hasStarted = _getTimerDisplayHasStarted();
    if (!hasStarted) {
      final firstPhaseMode = await _getFirstPhaseIntensityMode();
      return firstPhaseMode ?? IntensityMode.stimulation;
    }
    return _getCurrentIntensityMode();
  }

  Future<Map<String, dynamic>> _getTimerDisplayData() async {
    final totalPhases = await _getTotalPhases();
    final displayMode = await _getDisplayIntensityMode();
    return {'totalPhases': totalPhases, 'displayMode': displayMode};
  }

  /// Timer card shows hybrid whenever the hybrid switch is on, matching DP/session
  /// behavior (no stimulation-phase gate).
  bool _shouldShowHybridTimerDisplay() => _getCurrentHybridPattern();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColor.primaryPurple,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColor.gradientStart, AppColor.gradientEnd],
            ),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(),
                  _buildPumpSelection(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: ResponsiveText.symmetric(
                        context,
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDeviceStatus(),
                          SizedBox(height: ResponsiveText.getSize(context, 10)),
                          _buildSessionSettings(),
                          SizedBox(height: ResponsiveText.getSize(context, 12)),
                          _buildTimerDisplay(),
                          SizedBox(height: ResponsiveText.getSize(context, 8)),
                          // both 模式下运行时的警告
                          // 只有在非独立模式下才检查同步状态
                          if (_getCurrentHasStarted() &&
                              _selectedPump == PumpSelection.both &&
                              !_isIndividualMode &&
                              !_areDevicesSynchronized())
                            _switchToIndividualMode(),

                          _buildIntensitySettings(),
                          SizedBox(height: ResponsiveText.getSize(context, 20)),
                          _buildControlButtons(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // 菜单遮罩
              if (_isMenuOpen) _buildMenuOverlay(),
              // 侧边菜单
              _buildSideMenu(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        left: ResponsiveText.getSize(context, 20),
        right: ResponsiveText.getSize(context, 20),
        top: statusBarHeight + ResponsiveText.getSize(context, 16),
        bottom: 0,
      ),
      decoration: const BoxDecoration(color: AppColor.primaryPurple),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            AppLocalizations.of(context)!.pumpControl,
            style: ResponsiveText.title(
              context,
              fontWeight: FontWeight.bold,
              color: AppColor.white,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.menu, color: AppColor.white),
            onPressed: () {
              setState(() {
                _isClosingForDeviceSettings = false;
                _isMenuOpen = true;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPumpSelection() {
    return Container(
      width: double.infinity,
      padding: ResponsiveText.padding(
        context,
        top: 10,
        bottom: 18,
        left: 18,
        right: 18,
      ),
      decoration: const BoxDecoration(color: AppColor.primaryPurple),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.selectWhichPumpToControl,
            style: ResponsiveText.body(context, color: AppColor.white),
          ),
          SizedBox(height: ResponsiveText.getSize(context, 12)),
          Row(
            children: [
              Expanded(
                child: _buildPumpButton(
                  AppLocalizations.of(context)!.left,
                  PumpSelection.left,
                ),
              ),
              SizedBox(width: ResponsiveText.getSize(context, 12)),
              Expanded(
                child: _buildPumpButton(
                  AppLocalizations.of(context)!.both,
                  PumpSelection.both,
                ),
              ),
              SizedBox(width: ResponsiveText.getSize(context, 12)),
              Expanded(
                child: _buildPumpButton(
                  AppLocalizations.of(context)!.right,
                  PumpSelection.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRunningStateDialog(PumpSelection targetSelection) {
    final l10n = AppLocalizations.of(context)!;
    String message = '';
    
    // 根据目标选择判断当前运行状态
    // 如果目标选择是 left 或 right，说明当前是 both 模式运行
    // 如果目标选择是 both，说明当前是单侧模式运行
    if (targetSelection == PumpSelection.both) {
      // 想切换到 both，说明当前是单侧运行
      message = l10n.singleSideRunningMessage;
    } else {
      // 想切换到 left 或 right，说明当前是 both 模式运行
      message = l10n.bothModeRunningMessage;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          titlePadding: ResponsiveText.padding(
            context,
            horizontal: 24,
            vertical: 20,
          ),
          contentPadding: ResponsiveText.padding(
            context,
            horizontal: 24,
            vertical: 0,
          ),
          actionsPadding: ResponsiveText.padding(
            context,
            horizontal: 8,
            vertical: 8,
          ),
          title: Text(
            l10n.runningStateDialogTitle,
            style: ResponsiveText.smallTitle(
              context,
              color: AppColor.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            message,
            style: ResponsiveText.body(
              context,
              color: AppColor.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                padding: ResponsiveText.symmetric(
                  context,
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: Text(
                l10n.ok,
                style: ResponsiveText.body(
                  context,
                  color: AppColor.primaryPurple,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPumpButton(String label, PumpSelection selection) {
    final isSelected = _selectedPump == selection;
    bool isDisabled = false;
    bool showIcon = false;

    // 检查设备是不是连接着（设备存在且正在运行）
    final leftDeviceConnected =
        _leftDevice != null &&
        _leftDevice!.isRemembered &&
        _leftDevice!.isRunning;
    final rightDeviceConnected =
        _rightDevice != null &&
        _rightDevice!.isRemembered &&
        _rightDevice!.isRunning;

    // 独立模式下：禁用 both 按钮，启用 left 和 right 按钮
    if (_isIndividualMode) {
      if (selection == PumpSelection.both) {
        isDisabled = true;
      }
      // left 和 right 按钮在独立模式下保持可用，跳过后续的禁用逻辑
      // 直接返回，不执行后续的禁用检查
    } else {
      // 非独立模式下的正常禁用逻辑
      final currentHasStarted = _getCurrentHasStarted();
      // 只有设备连接且已启动时，才禁用切换
      if (currentHasStarted) {
        switch (_selectedPump) {
          case PumpSelection.both:
            // both 模式启动：禁用 left 和 right（但前提是设备都连接着）
            if (leftDeviceConnected && rightDeviceConnected) {
              isDisabled =
                  selection == PumpSelection.left ||
                  selection == PumpSelection.right;
            }
            // 设备断线了，允许切换
            break;
          case PumpSelection.left:
            // left 模式启动：只禁用 both，right 可选（但前提是设备连接着）
            if (leftDeviceConnected) {
              isDisabled = selection == PumpSelection.both;
            }
            // 设备断线了，允许切换
            break;
          case PumpSelection.right:
            // right 模式启动：只禁用 both，left 可选（但前提是设备连接着）
            if (rightDeviceConnected) {
              isDisabled = selection == PumpSelection.both;
            }
            // 设备断线了，允许切换
            break;
        }
      } else {
        if (_selectedPump == PumpSelection.left &&
            _rightHasStarted &&
            rightDeviceConnected) {
          isDisabled = selection == PumpSelection.both;
        }
        if (_selectedPump == PumpSelection.right &&
            _leftHasStarted &&
            leftDeviceConnected) {
          isDisabled = selection == PumpSelection.both;
        }
      }
    }

    // earthquake icon 只在设备连接且已启动时显示
    switch (selection) {
      case PumpSelection.left:
        showIcon =
            _leftHasStarted &&
            (_selectedPump != PumpSelection.both) &&
            leftDeviceConnected;
        break;
      case PumpSelection.right:
        showIcon =
            _rightHasStarted &&
            (_selectedPump != PumpSelection.both) &&
            rightDeviceConnected;
        break;
      case PumpSelection.both:
        showIcon =
            (_selectedPump == PumpSelection.both) &&
            ((_leftHasStarted && leftDeviceConnected) ||
                (_rightHasStarted && rightDeviceConnected));
        break;
    }

    return InkWell(
      onTap: isDisabled
          ? () {
              _showRunningStateDialog(selection);
            }
          : () {
              setState(() {
                // 切换选择时，先同步显示变量（传入新选择，以便保存旧选择的状态）
                _syncDisplayVariables(selection);
                _selectedPump = selection;
              });
            },
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Container(
          padding: ResponsiveText.symmetric(context, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColor.white : AppColor.deepPurple,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.transparent : AppColor.white,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              showIcon
                  ? Icon(
                      Symbols.earthquake,
                      size: ResponsiveText.getSize(context, 18),
                      color: isSelected ? AppColor.deepPurple : AppColor.white,
                    )
                  : SizedBox.shrink(),
              showIcon
                  ? SizedBox(width: ResponsiveText.getSize(context, 4))
                  : SizedBox.shrink(),
              Text(
                label,
                textAlign: TextAlign.center,
                style: ResponsiveText.smallTitle(
                  context,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? AppColor.deepPurple : AppColor.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceStatus() {
    final isBoth = _selectedPump == PumpSelection.both;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.deviceStatus,
          style: ResponsiveText.bodySmall(
            context,
            color: const Color(0xFF6A7282),
          ),
        ),
        SizedBox(height: ResponsiveText.getSize(context, 8)),
        if (isBoth)
          Row(
            children: [
              Expanded(child: _buildDeviceStatusCard('L', _leftDevice)),
              SizedBox(width: ResponsiveText.getSize(context, 12)),
              Expanded(child: _buildDeviceStatusCard('R', _rightDevice)),
            ],
          )
        else
          _buildSingleDeviceStatusCard(),
      ],
    );
  }

  Widget _buildSingleDeviceStatusCard() {
    final side = _selectedPump == PumpSelection.left ? 'L' : 'R';
    final device = _selectedPump == PumpSelection.left
        ? _leftDevice
        : _rightDevice;
    return _buildDeviceStatusCard(side, device);
  }

  static const Color _statusConnectedBackground = Color(0xFFFEF9E7);
  static const Color _statusConnectedText = Color(0xFF8D6E63);
  static const Color _statusDisconnectedBackground = Color(0xFFFFF0F0);
  static const Color _statusDisconnectedText = Color(0xFFDC2626);

  Widget _buildDeviceStatusCard(String side, ConnectedDevice? device) {
    final l10n = AppLocalizations.of(context)!;
    final sideLabel = side == 'L' ? l10n.left : l10n.right;

    if (device == null || !device.isRemembered) {
      return _buildStatusCardShell(
        backgroundColor: Colors.grey.shade300,
        borderColor: Colors.grey.shade400,
        child: Text(
          l10n.notAvailable,
          style: ResponsiveText.bodySmall(
            context,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
      );
    }

    if (device.isRunning) {
      return _buildStatusCardShell(
        backgroundColor: _statusConnectedBackground,
        borderColor: const Color.fromRGBO(0, 0, 0, 0.1),
        child: Row(
          children: [
            Text(
              '$sideLabel: ',
              style: ResponsiveText.bodySmall(
                context,
                fontWeight: FontWeight.bold,
                color: _statusConnectedText,
              ),
            ),
            Text(
              l10n.deviceConnected,
              style: ResponsiveText.bodySmall(
                context,
                fontWeight: FontWeight.bold,
                color: _statusConnectedText,
              ),
            ),
            SizedBox(width: ResponsiveText.getSize(context, 8)),
            _buildBatteryIndicator(device.battery),
          ],
        ),
      );
    }

    final isReconnecting = _reconnectingDeviceIds.contains(device.bluetoothId);
    final card = _buildStatusCardShell(
      backgroundColor: _statusDisconnectedBackground,
      borderColor: const Color.fromRGBO(0, 0, 0, 0.08),
      child: isReconnecting
          ? Row(
              children: [
                SizedBox(
                  width: ResponsiveText.getSize(context, 14),
                  height: ResponsiveText.getSize(context, 14),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColor.primaryPurple,
                  ),
                ),
                SizedBox(width: ResponsiveText.getSize(context, 6)),
                Text(
                  '$sideLabel: ${l10n.connecting}',
                  style: ResponsiveText.bodySmall(
                    context,
                    fontWeight: FontWeight.bold,
                    color: AppColor.primaryPurple,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.bluetooth,
                      size: ResponsiveText.getSize(context, 16),
                      color: _statusDisconnectedText,
                    ),
                    SizedBox(width: ResponsiveText.getSize(context, 4)),
                    Text(
                      '$sideLabel: ${l10n.deviceOff}',
                      style: ResponsiveText.bodySmall(
                        context,
                        fontWeight: FontWeight.bold,
                        color: _statusDisconnectedText,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveText.getSize(context, 4)),
                Text(
                  l10n.tapToReconnect,
                  style: ResponsiveText.captionSmall(
                    context,
                    fontWeight: FontWeight.w500,
                    color: AppColor.primaryPurple,
                  ),
                ),
              ],
            ),
    );

    if (isReconnecting) {
      return card;
    }

    return GestureDetector(
      onTap: () => _reconnectDevice(device),
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }

  Widget _buildStatusCardShell({
    required Color backgroundColor,
    required Color borderColor,
    required Widget child,
  }) {
    return Container(
      padding: ResponsiveText.symmetric(context, vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: child,
    );
  }

  /// Static red icon at level 1 — no blink animation (host LED blinks instead).
  Widget _buildBatteryIndicator(int level) {
    final batteryData = switch (level) {
      1 => (Icons.battery_2_bar, Colors.red),
      2 => (Icons.battery_4_bar, Colors.orange),
      3 => (Icons.battery_full, Colors.green),
      _ => (Icons.battery_1_bar, Colors.grey),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          batteryData.$1,
          size: ResponsiveText.getSize(context, 14),
          color: batteryData.$2,
        ),
      ],
    );
  }

  /// 返回当前模式的阶段描述摘要（展示在流程设置区域）
  String _currentModeDescription() {
    switch (_sessionMode) {
      case SessionMode.defaultMode:
        return '2min -> 5min';
      case SessionMode.beginner:
        return '2min -> 5min';
      case SessionMode.boostMilk:
        return '2min -> 3min';
      case SessionMode.custom:
        return _customFlowDescription;
    }
  }

  /// 返回当前模式对应的按钮标签
  String _sessionModeFlowLabel(SessionMode mode, AppLocalizations l10n) {
    switch (mode) {
      case SessionMode.defaultMode:
        return l10n.defaultFlow;
      case SessionMode.beginner:
        return l10n.beginnerFlow;
      case SessionMode.boostMilk:
        return l10n.boostMilkFlow;
      case SessionMode.custom:
        return l10n.customFlow;
    }
  }

  Widget _buildSessionSettings() {
    return Container(
      padding: ResponsiveText.padding(
        context,
        top: 16,
        left: 16,
        right: 16,
        bottom: 24,
      ),
      decoration: BoxDecoration(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color.fromRGBO(0, 0, 0, 0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.sessionSettings,
            style: ResponsiveText.bodySmall(
              context,
              color: const Color(0xFF6A7282),
            ),
          ),
          SizedBox(height: ResponsiveText.getSize(context, 30)),
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildSessionModeButton(
                      AppLocalizations.of(context)!.defaultMode,
                      SessionMode.defaultMode,
                    ),
                  ),
                  SizedBox(width: ResponsiveText.getSize(context, 8)),
                  Expanded(
                    child: _buildSessionModeButton(
                      AppLocalizations.of(context)!.custom,
                      SessionMode.custom,
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: ResponsiveText.getSize(context, 30)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _currentModeDescription(),
                style: ResponsiveText.bodySmall(
                  context,
                  color: AppColor.textSecondary,
                ),
              ),
              SizedBox(width: ResponsiveText.getSize(context, 16)),
              Row(
                children: [
                  Text(
                    AppLocalizations.of(context)!.max,
                    style: ResponsiveText.bodySmall(
                      context,
                      color: AppColor.textSecondary,
                    ),
                  ),
                  SizedBox(width: ResponsiveText.getSize(context, 8)),
                  Container(
                    padding: ResponsiveText.symmetric(
                      context,
                      horizontal: 12,
                      vertical: 4,
                    ),
                    constraints: BoxConstraints(
                      minHeight: ResponsiveText.getSize(context, 32),
                      maxHeight: ResponsiveText.getSize(context, 36),
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F3F5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
                    ),
                    child: DropdownButton<int>(
                      value: _maxDuration,
                      underline: const SizedBox(),
                      icon: Icon(
                        Icons.arrow_drop_down,
                        size: ResponsiveText.getSize(context, 20),
                      ),
                      isDense: true,
                      style: ResponsiveText.bodySmall(
                        context,
                        fontWeight: FontWeight.normal,
                        color: AppColor.textSecondary,
                      ),
                      selectedItemBuilder: (BuildContext context) {
                        return [15, 20, 25, 30].map((int value) {
                          return Text('$value');
                        }).toList();
                      },
                      items: [15, 20, 25, 30].map((int value) {
                        return DropdownMenuItem<int>(
                          value: value,
                          child: Text(
                            '$value ${AppLocalizations.of(context)!.minutes}',
                          ),
                        );
                      }).toList(),
                      onChanged: (int? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _maxDuration = newValue;
                            // 保存到当前泵选择对应的状态
                            _pumpMaxDurations[_selectedPump] = newValue;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionModeButton(String label, SessionMode mode) {
    final isSelected = _sessionMode == mode;
    return InkWell(
      onTap: () {
        if (mode == SessionMode.custom && isSelected) {
          Navigator.of(context)
              .push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const CustomFlowPage(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              )
              .then((_) => _loadCustomFlowDescription());
        } else {
          setState(() {
            _sessionMode = mode;
            // 保存到当前泵选择对应的状态
            _pumpSessionModes[_selectedPump] = mode;
          });
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: ResponsiveText.symmetric(context, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColor.primaryPurple : AppColor.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : Colors.grey.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _sessionModeFlowLabel(mode, AppLocalizations.of(context)!),
              textAlign: TextAlign.center,
              style: ResponsiveText.body(
                context,
                fontWeight: FontWeight.w500,
                color: isSelected ? AppColor.white : AppColor.textPrimary,
              ),
            ),
            if (mode == SessionMode.custom && isSelected) ...[
              SizedBox(width: ResponsiveText.getSize(context, 4)),
              Icon(
                Icons.chevron_right,
                size: ResponsiveText.getSize(context, 20),
                color: AppColor.white,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimerDisplay() {
    final currentHasStarted = _getTimerDisplayHasStarted();
    final displayMinutes = currentHasStarted
        ? _elapsedTime.inMinutes.toString().padLeft(2, '0')
        : '00';
    final displaySeconds = currentHasStarted
        ? (_elapsedTime.inSeconds % 60).toString().padLeft(2, '0')
        : '00';

    Future<Map<String, dynamic>?> getInitialStateFuture() async {
      if (currentHasStarted) return null;
      return _getInitialDeviceState(_getTimerInitialStateIsLeft());
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _getTimerDisplayData(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data!;
        final displayMode = data['displayMode'] as IntensityMode;
        final currentPhase = currentHasStarted ? _currentPhase : 1;
        final effectiveTotalPhases = currentHasStarted
            ? _totalPhase
            : (data['totalPhases'] as int);
        return FutureBuilder<Map<String, dynamic>?>(
          future: getInitialStateFuture(),
          builder: (context, initialStateSnapshot) {
            final effectivePhaseDuration = currentHasStarted
                ? _phaseDuration
                : (initialStateSnapshot.data?['phaseDuration'] as Duration? ??
                      _phaseDuration);

            return UnifiedTimerCard(
              displayMode: displayMode,
              displayMinutes: displayMinutes,
              displaySeconds: displaySeconds,
              currentPhase: currentPhase,
              effectiveTotalPhases: effectiveTotalPhases,
              currentHasStarted: currentHasStarted,
              effectivePhaseDuration: effectivePhaseDuration,
              elapsedTimeInPhase: _elapsedTimeInPhase,
              maxDuration: _maxDuration,
              deviceMaxDuration: _deviceMaxDuration,
              showHybridDisplay: _shouldShowHybridTimerDisplay(),
            );
          },
        );
      },
    );
  }

  Widget _buildSuctionLevelButton({
    required BuildContext context,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final isDisabled = onPressed == null;
    final buttonSize = ResponsiveText.getSize(context, 40);
    
    return GestureDetector(
      onTap: onPressed,
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Container(
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            color: AppColor.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.grey.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            size: ResponsiveText.getSize(context, 20),
            color: isDisabled
                ? Colors.grey.withValues(alpha: 0.5)
                : AppColor.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildIntensitySettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.intensitySettings,
          style: ResponsiveText.bodySmall(
            context,
            color: const Color(0xFF6A7282),
          ),
        ),
        SizedBox(height: ResponsiveText.getSize(context, 4)),
        _selectedPump == PumpSelection.both
            ? Row(
                children: [
                  // 左侧模块
                  Expanded(
                    child: _buildIntensityModuleBoth(isLeft: true),
                  ),
                  SizedBox(width: ResponsiveText.getSize(context, 8)),
                  // 右侧模块
                  Expanded(
                    child: _buildIntensityModuleBoth(isLeft: false),
                  ),
                ],
              )
            : _buildIntensityModuleOriginal(),
      ],
    );
  }

  Widget _buildIntensityModuleBoth({required bool isLeft}) {
    // final intensityMode = isLeft ? _leftIntensityMode : _rightIntensityMode;
    final suctionLevel = isLeft ? _getLeftSuctionLevel() : _getRightSuctionLevel();
    final hybridPatternEnabled = _getCurrentHybridPattern();

    return Container(
      padding: ResponsiveText.padding(
        context,
        left: 10,
        right: 10,
        top: 10,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left/Right label
          Text(
            isLeft
                ? AppLocalizations.of(context)!.left
                : AppLocalizations.of(context)!.right,
            style: ResponsiveText.bodySmall(
              context,
              color: AppColor.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveText.getSize(context, 24)),
          // Fast rhythm text
          Text(
            AppLocalizations.of(context)!.stimulationDescription,
            style: ResponsiveText.caption(
              context,
              color: AppColor.textSecondary,
            ),
          ),
          SizedBox(height: ResponsiveText.getSize(context, 24)),
          // Suction
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                AppLocalizations.of(context)!.suction,
                style: ResponsiveText.bodySmall(
                  context,
                  color: AppColor.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveText.getSize(context, 4)),
          // - 数字 + 格式
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 减号按钮
              _buildSuctionLevelButton(
                context: context,
                icon: Icons.remove,
                onPressed: suctionLevel <= 1
                    ? null
                    : () => isLeft ? _adjustLeftSuctionLevel(-1) : _adjustRightSuctionLevel(-1),
              ),
              // 数字显示（居中）
              Expanded(
                child: Center(
                  child: Text(
                    suctionLevel.toInt().toString(),
                    style: ResponsiveText.title(
                      context,
                      color: AppColor.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              // 加号按钮
              _buildSuctionLevelButton(
                context: context,
                icon: Icons.add,
                onPressed: suctionLevel >= 9
                    ? null
                    : () => isLeft ? _adjustLeftSuctionLevel(1) : _adjustRightSuctionLevel(1),
              ),
            ],
          ),
          SizedBox(height: ResponsiveText.getSize(context, 4)),
          Divider(
            height: ResponsiveText.getSize(context, 24),
            thickness: 1,
            color: Colors.grey.withValues(alpha: 0.4),
          ),
          // Hybrid Pattern
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.hybrid,
                    style: ResponsiveText.bodySmall(
                      context,
                      fontWeight: FontWeight.w500,
                      color: AppColor.textPrimary,
                    ),
                  ),
                  SizedBox(height: ResponsiveText.getSize(context, 4)),
                  Text(
                    AppLocalizations.of(context)!.hybridPatternDescriptionShort,
                    style: ResponsiveText.bodySmall(
                      context,
                      color: AppColor.textSecondary,
                    ),
                  ),
                ],
              ),
              Transform.scale(
                scale: 0.65,
                child: SwitchTheme(
                  data: SwitchThemeData(
                    thumbColor: WidgetStateProperty.resolveWith<Color>((
                      Set<WidgetState> states,
                    ) {
                      return AppColor.white;
                    }),
                    trackColor: WidgetStateProperty.resolveWith<Color>((
                      Set<WidgetState> states,
                    ) {
                      if (states.contains(WidgetState.selected)) {
                        return AppColor.textPrimary;
                      }
                      return Colors.grey.withValues(
                        alpha: 0.3,
                      );
                    }),
                    overlayColor: WidgetStateProperty.resolveWith<Color>((
                      Set<WidgetState> states,
                    ) {
                      return Colors.transparent;
                    }),
                    splashRadius: 0,
                  ),
                  child: Switch(
                    value: hybridPatternEnabled,
                    onChanged: (bool value) async {
                      await _applyHybridPatternChange(value);
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIntensityModuleOriginal() {
    return Container(
      padding: ResponsiveText.padding(
        context,
        left: 10,
        right: 10,
        top: 10,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _getCurrentIntensityMode() == IntensityMode.stimulation
                ? AppLocalizations.of(context)!.stimulationDescription
                : AppLocalizations.of(context)!.expressionDescription,
            style: ResponsiveText.caption(
              context,
              color: AppColor.textSecondary,
            ),
          ),
          SizedBox(height: ResponsiveText.getSize(context, 24)),
          // Suction Level
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                AppLocalizations.of(context)!.suctionLevel,
                style: ResponsiveText.bodySmall(
                  context,
                  color: AppColor.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _getCurrentSuctionLevel().toInt().toString(),
                style: ResponsiveText.bodySmall(
                  context,
                  color: AppColor.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveText.getSize(context, 24)),
          Row(
            children: [
              // 减号按钮
              _buildSuctionLevelButton(
                context: context,
                icon: Icons.remove,
                onPressed: _getCurrentSuctionLevel() <= 1
                    ? null
                    : () => _adjustSuctionLevel(-1),
              ),
              // 滑块
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColor.textPrimary,
                    inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                    thumbColor: AppColor.white,
                    thumbShape: _CustomSliderThumb(
                      enabledThumbRadius: ResponsiveText.getSize(context, 8),
                    ),
                    overlayShape: RoundSliderOverlayShape(
                      overlayRadius: ResponsiveText.getSize(context, 16),
                    ),
                    trackHeight: ResponsiveText.getSize(context, 16),
                    tickMarkShape: const RoundSliderTickMarkShape(
                      tickMarkRadius: 0,
                    ),
                  ),
                  child: Slider(
                    value: _getCurrentSuctionLevel(),
                    min: 1,
                    max: 9,
                    divisions: 8,
                    onChanged: (double value) {
                      final roundedValue = value.roundToDouble();
                      setState(() {
                        _setCurrentSuctionLevel(roundedValue);
                      });
                    },
                    onChangeEnd: (double value) {
                      final currentHasStarted = _getCurrentHasStarted();
                      if (currentHasStarted) {
                        final roundedValue = value.roundToDouble();
                        final intValue = roundedValue.toInt();
                        final intensityMode = _getCurrentIntensityMode();
                        final dpId = intensityMode == IntensityMode.stimulation
                            ? DpConstants.stimulationSucLvl
                            : DpConstants.expressionSucLvl;
                        
                        if (_selectedPump == PumpSelection.both) {
                          if (intensityMode == IntensityMode.stimulation) {
                            if (_leftDevice != null) {
                              _recordUserSuctionLevelOperation(_leftDevice, dpId, roundedValue);
                              BleDpService.publishDp(
                                _leftDevice!.bluetoothId,
                                DpConstants.stimulationSucLvl,
                                intValue,
                              );
                            }
                            if (_rightDevice != null) {
                              _recordUserSuctionLevelOperation(_rightDevice, dpId, roundedValue);
                              BleDpService.publishDp(
                                _rightDevice!.bluetoothId,
                                DpConstants.stimulationSucLvl,
                                intValue,
                              );
                            }
                          } else {
                            if (_leftDevice != null) {
                              _recordUserSuctionLevelOperation(_leftDevice, dpId, roundedValue);
                              BleDpService.publishDp(
                                _leftDevice!.bluetoothId,
                                DpConstants.expressionSucLvl,
                                intValue,
                              );
                            }
                            if (_rightDevice != null) {
                              _recordUserSuctionLevelOperation(_rightDevice, dpId, roundedValue);
                              BleDpService.publishDp(
                                _rightDevice!.bluetoothId,
                                DpConstants.expressionSucLvl,
                                intValue,
                              );
                            }
                          }
                        } else if (_selectedPump == PumpSelection.left &&
                            _leftDevice != null) {
                          _recordUserSuctionLevelOperation(_leftDevice, dpId, roundedValue);
                          if (intensityMode == IntensityMode.stimulation) {
                            BleDpService.publishDp(
                              _leftDevice!.bluetoothId,
                              DpConstants.stimulationSucLvl,
                              intValue,
                            );
                          } else {
                            BleDpService.publishDp(
                              _leftDevice!.bluetoothId,
                              DpConstants.expressionSucLvl,
                              intValue,
                            );
                          }
                        } else if (_selectedPump == PumpSelection.right &&
                            _rightDevice != null) {
                          _recordUserSuctionLevelOperation(_rightDevice, dpId, roundedValue);
                          if (intensityMode == IntensityMode.stimulation) {
                            BleDpService.publishDp(
                              _rightDevice!.bluetoothId,
                              DpConstants.stimulationSucLvl,
                              intValue,
                            );
                          } else {
                            BleDpService.publishDp(
                              _rightDevice!.bluetoothId,
                              DpConstants.expressionSucLvl,
                              intValue,
                            );
                          }
                        }
                      }
                    },
                  ),
                ),
              ),
              // 加号按钮
              _buildSuctionLevelButton(
                context: context,
                icon: Icons.add,
                onPressed: _getCurrentSuctionLevel() >= 9
                    ? null
                    : () => _adjustSuctionLevel(1),
              ),
            ],
          ),
          SizedBox(height: ResponsiveText.getSize(context, 12)),
          Divider(
            height: ResponsiveText.getSize(context, 24),
            thickness: 1,
            color: Colors.grey.withValues(alpha: 0.4),
          ),
          // Hybrid Pattern
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.hybridPattern,
                    style: ResponsiveText.bodySmall(
                      context,
                      fontWeight: FontWeight.w500,
                      color: AppColor.textPrimary,
                    ),
                  ),
                  SizedBox(height: ResponsiveText.getSize(context, 4)),
                  Text(
                    AppLocalizations.of(context)!.hybridPatternDescription,
                    style: ResponsiveText.bodySmall(
                      context,
                      color: AppColor.textSecondary,
                    ),
                  ),
                ],
              ),
              Transform.scale(
                scale: 0.65,
                child: SwitchTheme(
                  data: SwitchThemeData(
                    thumbColor: WidgetStateProperty.resolveWith<Color>((
                      Set<WidgetState> states,
                    ) {
                      return AppColor.white;
                    }),
                    trackColor: WidgetStateProperty.resolveWith<Color>((
                      Set<WidgetState> states,
                    ) {
                      if (states.contains(WidgetState.selected)) {
                        return AppColor.textPrimary;
                      }
                      return Colors.grey.withValues(
                        alpha: 0.3,
                      );
                    }),
                    overlayColor: WidgetStateProperty.resolveWith<Color>((
                      Set<WidgetState> states,
                    ) {
                      return Colors.transparent;
                    }),
                    splashRadius: 0,
                  ),
                  child: Switch(
                    value: _getCurrentHybridPattern(),
                    onChanged: (bool value) async {
                      await _applyHybridPatternChange(value);
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isDeviceConnected(ConnectedDevice? device) {
    return device != null && device.isRemembered && device.isRunning;
  }

  bool _areDevicesSynchronized() {
    final result = _checkDevicesSynchronization();
    final deferDesync = _shouldDeferDesyncForGrace(_lastBothSyncFailReason);
    final effectivelySynced = result || deferDesync;
    debugPrint('🔄 设备同步状态: $effectivelySynced'
        '${deferDesync ? " (action_grace defer $_lastBothSyncFailReason)" : ""}');

    // 如果已经是独立模式
    if (_isIndividualMode) {
      // 如果设备重新同步，退出独立模式
      if (effectivelySynced) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isIndividualMode) {
            setState(() {
              _isIndividualMode = false;
              _bothNotSynchronizedCount = 0;
              _bothDesyncSince = null;
            });
            debugPrint('✅ 设备重新同步，退出独立模式');
          }
        });
      }
      // 在独立模式下，不再增加计数，直接返回 true（表示"已处理"，不需要再切换）
      return true;
    }

    // 非独立模式下的正常同步检查逻辑
    debugPrint('🔄 设备不同步计数: $_bothNotSynchronizedCount');
    if (effectivelySynced) {
      _bothNotSynchronizedCount = 0;
      _bothDesyncSince = null;
    } else {
      _bothDesyncSince ??= DateTime.now();
      _bothNotSynchronizedCount++;
    }

    final sustainedMs = _bothDesyncSince == null
        ? 0
        : DateTime.now().difference(_bothDesyncSince!).inMilliseconds;
    debugPrint('🔄 持续不同步: ${sustainedMs}ms / $_bothSustainedDesyncMs ms');
    return sustainedMs < _bothSustainedDesyncMs;
  }

  bool _isBothUserActionDp(String dpId) {
    return dpId == DpConstants.startN ||
        dpId == DpConstants.switchN ||
        dpId == DpConstants.stop ||
        dpId == DpConstants.pause;
  }

  void _markBothSyncActionGrace() {
    if (_selectedPump != PumpSelection.both) return;
    final until =
        DateTime.now().add(const Duration(milliseconds: _bothSyncActionGraceMs));
    if (_bothSyncActionGraceUntil == null ||
        until.isAfter(_bothSyncActionGraceUntil!)) {
      _bothSyncActionGraceUntil = until;
      PumpLog.i(
        'SYNC_GRACE',
        '用户操作后 ${_bothSyncActionGraceMs}ms 内 mode/phase 不同步不计入降级',
      );
    }
  }

  bool get _inBothSyncActionGrace {
    final until = _bothSyncActionGraceUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  bool _shouldDeferDesyncForGrace(String? failReason) {
    if (failReason == null || !_inBothSyncActionGrace) return false;
    return failReason.startsWith('mode(') ||
        failReason.startsWith('phase(') ||
        failReason.startsWith('phaseTime(');
  }

  bool _checkDevicesSynchronization() {
    final leftDevId = _leftDevice?.devId;
    final rightDevId = _rightDevice?.devId;

    final leftMode = _leftIntensityMode.name;
    final rightMode = _rightIntensityMode.name;
    final leftTotalSec = _leftElapsedTime.inSeconds;
    final rightTotalSec = _rightElapsedTime.inSeconds;
    final leftPhaseSec = _leftElapsedTimeInPhase.inSeconds;
    final rightPhaseSec = _rightElapsedTimeInPhase.inSeconds;

    String? failReason;
    if (_leftIntensityMode != _rightIntensityMode) {
      failReason = 'mode($leftMode≠$rightMode)';
    } else if (_leftCurrentPhase != _rightCurrentPhase) {
      failReason = 'phase($_leftCurrentPhase≠$_rightCurrentPhase)';
    } else if ((leftTotalSec - rightTotalSec).abs() >
        _bothTimeSyncThresholdSeconds) {
      failReason =
          'totalTime(diff=${(leftTotalSec - rightTotalSec).abs()}s>${_bothTimeSyncThresholdSeconds}s)';
    } else if ((leftPhaseSec - rightPhaseSec).abs() >
        _bothTimeSyncThresholdSeconds) {
      failReason =
          'phaseTime(diff=${(leftPhaseSec - rightPhaseSec).abs()}s>${_bothTimeSyncThresholdSeconds}s)';
    }

    final syncOk = failReason == null;
    _lastBothSyncFailReason = failReason;

    BothSyncDiagnostics.logCheck(
      leftDevId: leftDevId,
      rightDevId: rightDevId,
      leftHasStarted: _leftHasStarted,
      rightHasStarted: _rightHasStarted,
      leftPhase: _leftCurrentPhase,
      rightPhase: _rightCurrentPhase,
      leftMode: leftMode,
      rightMode: rightMode,
      leftTotalSec: leftTotalSec,
      rightTotalSec: rightTotalSec,
      leftPhaseSec: leftPhaseSec,
      rightPhaseSec: rightPhaseSec,
      syncOk: syncOk,
      failReason: failReason,
      desyncCount: _bothNotSynchronizedCount,
    );

    return syncOk;
  }

  /// 切换到独立模式：当 both 模式下检测到设备不同步时，切换到独立模式
  /// 禁用 both 按钮，启用 left/right 按钮，并默认切换到左侧
  Widget _switchToIndividualMode() {
    debugPrint('🔄 _switchToIndividualMode 被调用，当前 _isIndividualMode: $_isIndividualMode, 计数: $_bothNotSynchronizedCount');
    debugPrint('🔄 左侧时间: ${_leftElapsedTime.inSeconds}s, 右侧时间: ${_rightElapsedTime.inSeconds}s');
    // 如果还没有切换到独立模式，执行切换
    // 使用 addPostFrameCallback 避免在 build 期间调用 setState
    if (!_isIndividualMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isIndividualMode) {
          setState(() {
            _isIndividualMode = true;
            // 重置同步计数器，避免频繁切换
            _bothNotSynchronizedCount = 0;
            // 切换到左侧模式，并同步显示变量
            // 注意：在同步之前，确保两侧设备的时间变量都已经正确更新
            // _syncDisplayVariables 会从 _leftElapsedTime 和 _rightElapsedTime 复制到显示变量
            _syncDisplayVariables(PumpSelection.left);
            _selectedPump = PumpSelection.left;
          });
          BothSyncDiagnostics.logIndividualModeSwitch(
            reason: 'sustained_desync>=${_bothSustainedDesyncMs ~/ 1000}s',
            leftTotalSec: _leftElapsedTime.inSeconds,
            rightTotalSec: _rightElapsedTime.inSeconds,
            desyncCount: _bothNotSynchronizedCount,
          );
          debugPrint('✅ 检测到设备不同步，已切换到独立模式，并切换到左侧');
          debugPrint('🔄 切换后显示时间: ${_elapsedTime.inSeconds}s, 左侧时间: ${_leftElapsedTime.inSeconds}s, 右侧时间: ${_rightElapsedTime.inSeconds}s');
        }
      });
    } else {
      debugPrint('ℹ️ 已经在独立模式，无需再次切换');
    }
    // 返回空组件
    return const SizedBox.shrink();
  }

  bool _shouldDisableButtons() {
    switch (_selectedPump) {
      case PumpSelection.left:
        return !_isDeviceConnected(_leftDevice);
      case PumpSelection.right:
        return !_isDeviceConnected(_rightDevice);
      case PumpSelection.both:
        return !_isDeviceConnected(_leftDevice) ||
            !_isDeviceConnected(_rightDevice);
    }
  }

  Future<void> _gapBetweenBothBleCommands() async {
    await Future.delayed(const Duration(milliseconds: _bothBleCommandGapMs));
  }

  Future<void> _startBothSessionSequentially({
    required List<Map<String, int>> modeDurations,
    required int totalPhase,
  }) async {
    const isCustom = true;
    _bothStartInProgress = true;
    PumpLog.i('BOTH_START', 'Both 启动：按需 stop → DP101 → 并行 startN');
    try {
      final needsStop = _leftIsRunning || _rightIsRunning;
      if (needsStop) {
        _recordPendingForDevices(0);
        final stopFutures = <Future<bool>>[];
        if (_leftDevice != null) {
          stopFutures.add(
            BleDpService.publishDp(
              _leftDevice!.bluetoothId,
              DpConstants.stop,
              true,
            ),
          );
        }
        if (_rightDevice != null) {
          stopFutures.add(
            BleDpService.publishDp(
              _rightDevice!.bluetoothId,
              DpConstants.stop,
              true,
            ),
          );
        }
        final stopResults = await Future.wait(stopFutures);
        PumpLog.i('BOTH_START', '双侧 stop 并行完成 ok=$stopResults');
        PumpLog.i(
          'BOTH_START',
          '等待 ${_bothStopBeforeStartDelayMs}ms 再 start',
        );
        await Future.delayed(
          const Duration(milliseconds: _bothStopBeforeStartDelayMs),
        );
      } else {
        PumpLog.i('BOTH_START', '双侧已 idle，跳过 stop');
      }

      final settingFutures = <Future<bool>>[];
      if (_leftDevice != null) {
        settingFutures.add(
          BleDpService.pushSessionSetting(
            _leftDevice!.bluetoothId,
            _maxDuration,
            isCustom,
            totalPhase,
            _leftStimulationSuctionLevel.toInt(),
            _leftExpressionSuctionLevel.toInt(),
            _leftHybridPatternEnabled,
            _leftHybridPatternEnabled,
            modeDurations,
          ),
        );
      }
      if (_rightDevice != null) {
        settingFutures.add(
          BleDpService.pushSessionSetting(
            _rightDevice!.bluetoothId,
            _maxDuration,
            isCustom,
            totalPhase,
            _rightStimulationSuctionLevel.toInt(),
            _rightExpressionSuctionLevel.toInt(),
            _rightHybridPatternEnabled,
            _rightHybridPatternEnabled,
            modeDurations,
          ),
        );
      }
      final settingResults = await Future.wait(settingFutures);
      PumpLog.i('BOTH_START', '双侧 DP101 并行完成 ok=$settingResults');

      _recordPendingForDevices(1);
      final startFutures = <Future<bool>>[];
      if (_leftDevice != null) {
        startFutures.add(
          BleDpService.publishDp(
            _leftDevice!.bluetoothId,
            DpConstants.startN,
            true,
          ),
        );
      }
      if (_rightDevice != null) {
        startFutures.add(
          BleDpService.publishDp(
            _rightDevice!.bluetoothId,
            DpConstants.startN,
            true,
          ),
        );
      }
      await Future.wait(startFutures);
      PumpLog.i('BOTH_START', '双侧 startN 已并行下发');
    } finally {
      _bothStartInProgress = false;
    }
  }

  Future<void> _kickBothSideSessionIfNeeded({
    required bool isLeft,
    required String reason,
  }) async {
    if (!AppConfig.tuyaEnabled) return;
    if (_selectedPump != PumpSelection.both || _isIndividualMode) return;

    final device = isLeft ? _leftDevice : _rightDevice;
    final otherStarted = isLeft ? _rightHasStarted : _leftHasStarted;
    final otherRunning = isLeft ? _rightIsRunning : _leftIsRunning;
    if (device == null || !otherStarted || !otherRunning) return;

    if (_bothStartInProgress) {
      PumpLog.i(
        'BOTH_KICK',
        'skipped reason=$reason side=${isLeft ? 'left' : 'right'} (both_start_in_progress)',
      );
      return;
    }

    final now = DateTime.now();
    if (_lastBothSideKickAt != null &&
        now.difference(_lastBothSideKickAt!).inMilliseconds <
            _bothSideKickCooldownMs) {
      return;
    }
    _lastBothSideKickAt = now;

    PumpLog.i(
      'BOTH_KICK',
      'reason=$reason side=${isLeft ? 'left' : 'right'} devId=${device.devId} '
      '(一侧DP105报停止但另一侧仍在跑→补发sessionSetting+startN)',
    );

    final modeDurations = await _getModeDurations();
    final totalPhase = await _getTotalPhases();
    const isCustom = true;

    final ok = await BleDpService.pushSessionSetting(
      device.bluetoothId,
      _maxDuration,
      isCustom,
      totalPhase,
      isLeft ? _leftStimulationSuctionLevel.toInt() : _rightStimulationSuctionLevel.toInt(),
      isLeft ? _leftExpressionSuctionLevel.toInt() : _rightExpressionSuctionLevel.toInt(),
      isLeft ? _leftHybridPatternEnabled : _rightHybridPatternEnabled,
      isLeft ? _leftHybridPatternEnabled : _rightHybridPatternEnabled,
      modeDurations,
    );
    PumpLog.i('BOTH_KICK', 'DP101 ok=$ok side=${isLeft ? 'left' : 'right'}');
    await _gapBetweenBothBleCommands();
    _recordPendingOperation(device, 1);
    await BleDpService.publishDp(device.bluetoothId, DpConstants.startN, true);
    PumpLog.i('BOTH_KICK', 'startN 已下发 side=${isLeft ? 'left' : 'right'}');

    if (!mounted) return;
    setState(() {
      if (isLeft) {
        _leftHasStarted = true;
        _leftIsRunning = true;
      } else {
        _rightHasStarted = true;
        _rightIsRunning = true;
      }
    });
  }

  void _publishDpToDevices(String dpId, dynamic value) {
    if (_selectedPump == PumpSelection.both && _isBothUserActionDp(dpId)) {
      _markBothSyncActionGrace();
    }
    if (_selectedPump == PumpSelection.left && _leftDevice != null) {
      BleDpService.publishDp(_leftDevice!.bluetoothId, dpId, value);
    } else if (_selectedPump == PumpSelection.right && _rightDevice != null) {
      BleDpService.publishDp(_rightDevice!.bluetoothId, dpId, value);
    } else if (_selectedPump == PumpSelection.both) {
      final futures = <Future>[];
      if (_leftDevice != null) {
        futures.add(BleDpService.publishDp(_leftDevice!.bluetoothId, dpId, value));
      }
      if (_rightDevice != null) {
        futures.add(BleDpService.publishDp(_rightDevice!.bluetoothId, dpId, value));
      }
      Future.wait(futures);
    }
  }

  void _recordPendingForDevices(int expectedIsRunning) {
    if (_selectedPump == PumpSelection.left && _leftDevice != null) {
      _recordPendingOperation(_leftDevice, expectedIsRunning);
    } else if (_selectedPump == PumpSelection.right && _rightDevice != null) {
      _recordPendingOperation(_rightDevice, expectedIsRunning);
    } else if (_selectedPump == PumpSelection.both) {
      if (_leftDevice != null) {
        _recordPendingOperation(_leftDevice, expectedIsRunning);
      }
      if (_rightDevice != null) {
        _recordPendingOperation(_rightDevice, expectedIsRunning);
      }
    }
  }

  Widget _buildControlButtons() {
    final isDisabled = _shouldDisableButtons();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isDisabled
                    ? null
                    : () async {
                        // 如果是从未开始状态，根据 session settings 设置强度模式
                        final currentHasStarted = _getCurrentHasStarted();
                        final currentIsRunning = _getCurrentIsRunning();
                        if (!currentHasStarted && !currentIsRunning) {
                          if (_selectedPump == PumpSelection.both) {
                            setState(() {
                              _bothStartInProgress = true;
                              _setCurrentHasStarted(true);
                            });
                            _bothNotSynchronizedCount = 0;
                            _bothDesyncSince = null;
                            _markBothSyncActionGrace();

                            final firstPhaseMode =
                                await _getFirstPhaseIntensityMode();
                            List<Map<String, int>>? modeDurations;
                            int? totalPhase;
                            if (AppConfig.tuyaEnabled) {
                              modeDurations = await _getModeDurations();
                              totalPhase = await _getTotalPhases();
                            }
                            if (!mounted) return;
                            setState(() {
                              _setCurrentIntensityMode(
                                firstPhaseMode ?? IntensityMode.stimulation,
                              );
                            });
                            if (AppConfig.tuyaEnabled &&
                                modeDurations != null &&
                                totalPhase != null) {
                              await _startBothSessionSequentially(
                                modeDurations: modeDurations,
                                totalPhase: totalPhase,
                              );
                            } else {
                              _bothStartInProgress = false;
                            }
                            return;
                          }

                          final firstPhaseMode =
                              await _getFirstPhaseIntensityMode();

                          // 先获取异步数据，再 setState
                          List<Map<String, int>>? modeDurations;
                          int? totalPhase;
                          if (AppConfig.tuyaEnabled) {
                            modeDurations = await _getModeDurations();
                            totalPhase = await _getTotalPhases();
                          }

                          setState(() {
                            _setCurrentIntensityMode(
                              firstPhaseMode ?? IntensityMode.stimulation,
                            );
                            _setCurrentHasStarted(true);
                            _setCurrentIsRunning(true);
                          });

                          // setState 之后执行异步操作
                          if (AppConfig.tuyaEnabled &&
                              modeDurations != null &&
                              totalPhase != null) {
                            const isCustom = true;

                            if (_selectedPump == PumpSelection.left &&
                                _leftDevice != null) {
                              await BleDpService.pushSessionSetting(
                                _leftDevice!.bluetoothId,
                                _maxDuration,
                                isCustom,
                                totalPhase,
                                _leftStimulationSuctionLevel.toInt(),
                                _leftExpressionSuctionLevel.toInt(),
                                _leftHybridPatternEnabled,
                                _leftHybridPatternEnabled,
                                modeDurations,
                              );
                            } else if (_selectedPump == PumpSelection.right &&
                                _rightDevice != null) {
                              await BleDpService.pushSessionSetting(
                                _rightDevice!.bluetoothId,
                                _maxDuration,
                                isCustom,
                                totalPhase,
                                _rightStimulationSuctionLevel.toInt(),
                                _rightExpressionSuctionLevel.toInt(),
                                _rightHybridPatternEnabled,
                                _rightHybridPatternEnabled,
                                modeDurations,
                              );
                            }
                          }

                          _recordPendingForDevices(1);
                          _publishDpToDevices(DpConstants.startN, true);
                        } else {
                          if (currentIsRunning) {
                            _recordPendingForDevices(2);
                            _publishDpToDevices(DpConstants.pause, true);
                          } else {
                            _recordPendingForDevices(1);
                            _publishDpToDevices(DpConstants.startN, true);
                          }
                          setState(() {
                            _setCurrentIsRunning(!currentIsRunning);
                          });
                        }
                      },
                icon: Icon(
                  _getCurrentIsRunning()
                      ? Icons.pause_outlined
                      : Icons.play_arrow_outlined,
                  size: ResponsiveText.getSize(context, 32),
                ),
                label: Text(
                  _getCurrentIsRunning()
                      ? AppLocalizations.of(context)!.pause
                      : AppLocalizations.of(context)!.start,
                  style: ResponsiveText.body(
                    context,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDisabled
                      ? Colors.grey.withValues(alpha: 0.3)
                      : (_getCurrentIsRunning()
                            ? const Color(0xFFF0B100) // 黄色背景（运行中）
                            : AppColor.primaryPurple),
                  // 紫色背景（未运行）
                  foregroundColor: isDisabled
                      ? Colors.grey.withValues(alpha: 0.6)
                      : AppColor.white,
                  padding: ResponsiveText.symmetric(
                    context,
                    vertical: 4,
                    horizontal: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (isDisabled || !_getCurrentHasStarted())
                    ? null
                    : () {
                        setState(() {
                          _setCurrentIsRunning(false);
                          _setCurrentHasStarted(false);
                        });
                        _recordPendingForDevices(0);
                        _publishDpToDevices(DpConstants.stop, true);
                      },
                icon: Icon(
                  Icons.stop_outlined,
                  size: ResponsiveText.getSize(context, 30),
                  color: (isDisabled || !_getCurrentHasStarted())
                      ? Colors.grey.withValues(alpha: 0.6)
                      : AppColor.textSecondary,
                ),
                label: Text(
                  AppLocalizations.of(context)!.stop,
                  style: ResponsiveText.body(
                    context,
                    fontWeight: FontWeight.w500,
                    color: (isDisabled || !_getCurrentHasStarted())
                        ? Colors.grey.withValues(alpha: 0.6)
                        : AppColor.textSecondary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: (isDisabled || !_getCurrentHasStarted())
                      ? Colors.grey.withValues(alpha: 0.6)
                      : AppColor.textSecondary,
                  padding: ResponsiveText.symmetric(
                    context,
                    vertical: 4,
                    horizontal: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  side: BorderSide(
                    color: (isDisabled || !_getCurrentHasStarted())
                        ? Colors.grey.withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (isDisabled || !_getCurrentHasStarted())
                    ? null
                    : () => _publishDpToDevices(DpConstants.switchN, true),
                icon: Icon(
                  Icons.refresh_outlined,
                  size: ResponsiveText.getSize(context, 26),
                  color: (isDisabled || !_getCurrentHasStarted())
                      ? Colors.grey.withValues(alpha: 0.6)
                      : AppColor.textSecondary,
                ),
                label: Text(
                  AppLocalizations.of(context)!.switchMode,
                  style: ResponsiveText.body(
                    context,
                    fontWeight: FontWeight.w500,
                    color: (isDisabled || !_getCurrentHasStarted())
                        ? Colors.grey.withValues(alpha: 0.6)
                        : AppColor.textSecondary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: (isDisabled || !_getCurrentHasStarted())
                      ? Colors.grey.withValues(alpha: 0.6)
                      : AppColor.textSecondary,
                  padding: ResponsiveText.symmetric(
                    context,
                    vertical: 4,
                    horizontal: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  side: BorderSide(
                    color: (isDisabled || !_getCurrentHasStarted())
                        ? Colors.grey.withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          AppLocalizations.of(context)!.autoSwitchEnabled,
          style: ResponsiveText.caption(context, color: AppColor.textSecondary),
        ),
      ],
    );
  }

  // Widget _buildSynchronizationWarning() {
  //   return Container(
  //     padding: ResponsiveText.padding(
  //       context,
  //       top: 12,
  //       left: 6,
  //       right: 6,
  //       bottom: 12,
  //     ),
  //     decoration: BoxDecoration(
  //       color: const Color(0xFFFFF7ED),
  //       borderRadius: BorderRadius.circular(8),
  //       border: Border.all(color: const Color(0xFFFFD6A7), width: 2),
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         Row(
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           children: [
  //             Icon(
  //               Icons.warning_amber_rounded,
  //               color: const Color(0xFFF54900),
  //               size: ResponsiveText.getSize(context, 24),
  //             ),
  //             SizedBox(width: ResponsiveText.getSize(context, 18)),
  //             Expanded(
  //               child: Column(
  //                 crossAxisAlignment: CrossAxisAlignment.start,
  //                 children: [
  //                   // 翻译使用示例：使用 AppLocalizations.of(context)! 获取翻译对象
  //                   Text(
  //                     AppLocalizations.of(context)!.devicesNotSynchronized,
  //                     style: ResponsiveText.bodySmall(
  //                       context,
  //                       color: const Color(0xFF9F2D00),
  //                     ),
  //                   ),
  //                   const SizedBox(height: 4),
  //                   RichText(
  //                     text: TextSpan(
  //                       style: ResponsiveText.bodySmall(
  //                         context,
  //                         color: const Color(0xFFF54900),
  //                       ),
  //                       children: [
  //                         TextSpan(
  //                           text: AppLocalizations.of(
  //                             context,
  //                           )!.switchToLeftOrRight,
  //                           style: TextStyle(color: const Color(0xFFF54900)),
  //                         ),
  //                       ],
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //           ],
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildMenuOverlay() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isClosingForDeviceSettings = false;
          _isMenuOpen = false;
        });
      },
      child: Container(color: Colors.black.withValues(alpha: 0.5)),
    );
  }

  Widget _buildSideMenu() {
    final screenWidth = MediaQuery.of(context).size.width;
    final menuWidth = screenWidth * 0.7; // Menu takes 70% of screen width
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return AnimatedPositioned(
      duration: _isClosingForDeviceSettings
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      right: _isMenuOpen ? 0 : -menuWidth,
      top: 0,
      bottom: 0,
      width: menuWidth,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                SizedBox(
                  height: statusBarHeight + ResponsiveText.getSize(context, 16),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _buildMenuItem(
                        icon: Icons.settings,
                        title: AppLocalizations.of(context)!.deviceSettings,
                        onTap: () {
                          setState(() {
                            _isClosingForDeviceSettings = true;
                            _isMenuOpen = false;
                          });
                          if (mounted) {
                            Navigator.of(context)
                                .push(
                                  PageRouteBuilder(
                                    pageBuilder:
                                        (
                                          context,
                                          animation,
                                          secondaryAnimation,
                                        ) => const DeviceSettingsPage(),
                                    transitionDuration: Duration.zero,
                                    reverseTransitionDuration: Duration.zero,
                                  ),
                                )
                                .then((_) {
                                  _loadDevices();
                                  if (mounted) {
                                    setState(() {
                                      _isClosingForDeviceSettings = false;
                                      _isMenuOpen = false;
                                    });
                                  }
                                });
                          }
                        },
                      ),
                      SizedBox(height: ResponsiveText.getSize(context, 8)),
                      _buildMenuItem(
                        icon: Icons.settings,
                        title: AppLocalizations.of(context)!.systemSettings,
                        onTap: () {
                          setState(() {
                            _isClosingForDeviceSettings = true;
                            _isMenuOpen = false;
                          });
                          if (mounted) {
                            Navigator.of(context)
                                .push(
                                  PageRouteBuilder(
                                    pageBuilder:
                                        (
                                          context,
                                          animation,
                                          secondaryAnimation,
                                        ) => const SystemSettingsPage(),
                                    transitionDuration: Duration.zero,
                                    reverseTransitionDuration: Duration.zero,
                                  ),
                                )
                                .then((_) {
                                  _loadDevices();
                                  if (mounted) {
                                    setState(() {
                                      _isClosingForDeviceSettings = false;
                                      _isMenuOpen = false;
                                    });
                                  }
                                });
                          }
                        },
                      ),
                      SizedBox(height: ResponsiveText.getSize(context, 8)),
                      _buildMenuItem(
                        icon: Icons.help_outline,
                        title: AppLocalizations.of(context)!.helpAndAbout,
                        onTap: () {
                          setState(() {
                            _isClosingForDeviceSettings = true;
                            _isMenuOpen = false;
                          });
                          if (mounted) {
                            Navigator.of(context)
                                .push(
                                  PageRouteBuilder(
                                    pageBuilder:
                                        (
                                          context,
                                          animation,
                                          secondaryAnimation,
                                        ) => const HelpAboutPage(),
                                    transitionDuration: Duration.zero,
                                    reverseTransitionDuration: Duration.zero,
                                  ),
                                )
                                .then((_) {
                                  if (mounted) {
                                    setState(() {
                                      _isClosingForDeviceSettings = false;
                                      _isMenuOpen = false;
                                    });
                                  }
                                });
                          }
                        },
                      ),
                      SizedBox(height: ResponsiveText.getSize(context, 8)),
                      _buildMenuItem(
                        icon: Icons.bluetooth,
                        title: AppLocalizations.of(context)!.manageConnections,
                        onTap: () {
                          setState(() {
                            _isClosingForDeviceSettings = false;
                            _isMenuOpen = false;
                          });
                          Navigator.of(context).pushReplacement(
                            PageRouteBuilder(
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      const HomePage(),
                              transitionDuration: Duration.zero,
                              reverseTransitionDuration: Duration.zero,
                            ),
                          );
                        },
                      ),
                      if (AppConfig.debug) ...[
                        SizedBox(height: ResponsiveText.getSize(context, 8)),
                        _buildMenuItem(
                          icon: Icons.battery_alert,
                          title: AppLocalizations.of(context)!.lowBatteryTest,
                          onTap: () {
                            setState(() => _isMenuOpen = false);
                            LowBatteryDialog.show(
                              context,
                              LowBatteryDialogVariant.connectWarning,
                            );
                          },
                        ),
                        SizedBox(height: ResponsiveText.getSize(context, 8)),
                        _buildMenuItem(
                          icon: Icons.battery_alert,
                          title:
                              AppLocalizations.of(context)!.sessionCompleteTest,
                          onTap: () {
                            setState(() => _isMenuOpen = false);
                            LowBatteryDialog.show(
                              context,
                              LowBatteryDialogVariant.sessionComplete,
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: statusBarHeight + ResponsiveText.getSize(context, 8),
            right: ResponsiveText.getSize(context, 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isClosingForDeviceSettings = false;
                  _isMenuOpen = false;
                });
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: ResponsiveText.getSize(context, 48),
                height: ResponsiveText.getSize(context, 48),
                alignment: Alignment.center,
                child: Icon(
                  Icons.close,
                  color: Colors.black,
                  size: ResponsiveText.getSize(context, 24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: ResponsiveText.symmetric(
          context,
          horizontal: 20,
          vertical: 16,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: Colors.black,
              size: ResponsiveText.getSize(context, 24),
            ),
            SizedBox(width: ResponsiveText.getSize(context, 16)),
            Text(
              title,
              style: ResponsiveText.smallTitle(
                context,
                color: Colors.black,
                // fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomSliderThumb extends SliderComponentShape {
  final double enabledThumbRadius;

  const _CustomSliderThumb({this.enabledThumbRadius = 8.0});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(enabledThumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final Paint borderPaint = Paint()
      ..color = AppColor.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final Paint fillPaint = Paint()
      ..color = AppColor.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, enabledThumbRadius, fillPaint);
    canvas.drawCircle(center, enabledThumbRadius, borderPaint);
  }
}
