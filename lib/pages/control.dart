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
import 'home.dart';
import 'settings.dart';
import 'system_settings.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/tuya/dp_constants.dart';
import '../services/tuya/ble_dp_service.dart';
import '../services/tuya/ble_types.dart';
import '../services/tuya/dp_change_handle.dart';
import '../config/app_config.dart';

enum PumpSelection { left, both, right }

enum SessionMode { defaultMode, custom }

enum IntensityMode { stimulation, expression }

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
  final Map<String, _PendingOperation> _pendingOperations = {};
  final Map<String, Timer> _pendingCheckTimers = {};
  static const int _toleranceDelayMs = 2500;

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
    if (!isLeftDevice && !isRightDevice) return;

    final status = update.status;
    final isRunning = status['isRunning'] as int;
    
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
      });
      // debugPrint(
      //   '✅ Control 页面已更新数据(跳过isRunning): deviceId=${update.deviceId}, timePast=${timePast}s, timePastInPhase=${timePastInPhase}s, phase=$sessionPhase',
      // );
      return;
    }

    if (isRunning == 0) {
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
        if (AppConfig.tuyaEnabled) {
          final modeDurations = await _getModeDurations();
          final totalPhase = initialState['totalPhase'] as int;
          final isCustom = _sessionMode == SessionMode.custom;
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
        final otherSideRunning = isLeftDevice
            ? _rightIsRunning
            : _leftIsRunning;
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
          final isCustom = _sessionMode == SessionMode.custom;
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
        });
      } else {
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
      });
    }
    debugPrint(
      '✅ Control 页面已更新状态: deviceId=${update.deviceId}, isRunning=$isRunning, timePast=${timePast}s, timePastInPhase=${timePastInPhase}s, phase=$sessionPhase',
    );
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

    // 根据设备的当前 intensity mode 过滤 DP 更新
    // 在刺激模式下，只处理刺激模式相关的 DP（106, 107）
    // 在吸乳模式下，只处理吸乳模式相关的 DP（108, 109）
    final deviceIntensityMode = isLeft ? _leftIntensityMode : _rightIntensityMode;
    final isStimulationDp = update.dpId == DpConstants.stimulationSucLvl || 
                           update.dpId == DpConstants.stimulationHybrid;
    final isExpressionDp = update.dpId == DpConstants.expressionSucLvl || 
                          update.dpId == DpConstants.expressionHybrid;
    
    if (deviceHasStarted) {
      // // 设备已启动时，根据当前模式过滤
      // if (deviceIntensityMode == IntensityMode.stimulation && isExpressionDp) {
      //   debugPrint('⚠️ 设备在刺激模式，忽略吸乳模式 DP 更新: ${update.dpId}');
      //   return;
      // }
      // if (deviceIntensityMode == IntensityMode.expression && isStimulationDp) {
      //   debugPrint('⚠️ 设备在吸乳模式，忽略刺激模式 DP 更新: ${update.dpId}');
      //   return;
      // }
    }

    // 检查是否是用户操作导致的设备状态更新，如果是且值不一致，则忽略旧值
    if (update.dpId == DpConstants.stimulationSucLvl || 
        update.dpId == DpConstants.expressionSucLvl) {
      final deviceId = update.deviceId;
      final deviceOperations = _recentUserOperations[deviceId];
      if (deviceOperations != null) {
        final userOp = deviceOperations[update.dpId];
        if (userOp != null) {
          final timeSinceOp = DateTime.now().difference(userOp.timestamp).inMilliseconds;
          if (timeSinceOp < _ignoreDeviceUpdateWindowMs) {
            final deviceValue = (update.value as num).toDouble();
            // 如果设备返回的值与用户操作的值不一致
            if ((deviceValue - userOp.expectedValue).abs() > 0.1) {
              // 检查当前UI显示的值
              double currentValue;
              if (update.dpId == DpConstants.stimulationSucLvl) {
                currentValue = isLeft ? _leftStimulationSuctionLevel : _rightStimulationSuctionLevel;
              } else {
                currentValue = isLeft ? _leftExpressionSuctionLevel : _rightExpressionSuctionLevel;
              }
              
              // 如果当前值更接近用户期望的值，说明用户已经操作到了更新的值
              // 此时设备返回的旧值应该被忽略，避免覆盖用户的最新操作
              final currentDiff = (currentValue - userOp.expectedValue).abs();
              final deviceDiff = (deviceValue - userOp.expectedValue).abs();
              
              if (currentDiff < deviceDiff) {
                // 当前值更接近用户期望的值，忽略设备返回的旧值
                // debugPrint('🚫 忽略设备返回的旧状态: 期望=${userOp.expectedValue}, 设备返回=$deviceValue, 当前=$currentValue');
                return;
              }
              // 如果设备返回的值更接近用户期望的值，可能是设备确认了用户操作，接受它
            } else {
              // 值匹配（误差在0.1以内），清除操作记录
              deviceOperations.remove(update.dpId);
              if (deviceOperations.isEmpty) {
                _recentUserOperations.remove(deviceId);
              }
            }
          } else {
            // 操作记录过期（超过800ms），清除
            deviceOperations.remove(update.dpId);
            if (deviceOperations.isEmpty) {
              _recentUserOperations.remove(deviceId);
            }
          }
        }
      }
    }
    // 混合模式：同样防止设备旧状态覆盖用户操作
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
            // debugPrint('✅ 更新左侧刺激吸力大小: $v');
          } else if (isRight) {
            _rightStimulationSuctionLevel = v;
            // debugPrint('✅ 更新右侧刺激吸力大小: $v');
          }
          break;
        case DpConstants.expressionSucLvl:
          final v = (update.value as num).toDouble();
          if (isLeft) {
            _leftExpressionSuctionLevel = v;
            // debugPrint('✅ 更新左侧吸乳吸力大小: $v');
          } else if (isRight) {
            _rightExpressionSuctionLevel = v;
            // debugPrint('✅ 更新右侧吸乳吸力大小: $v');
          }
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
          debugPrint('⚠️ 左设备断线或移除，清除启动状态');
          _leftHasStarted = false;
          _leftIsRunning = false;
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
          debugPrint('⚠️ 右设备断线或移除，清除启动状态');
          _rightHasStarted = false;
          _rightIsRunning = false;
        }
        _leftDevice = newLeftDevice;
        _rightDevice = newRightDevice;
      });
    } catch (e) {
      debugPrint('❌ 刷新设备状态失败: $e');
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
    final setting = await _dbService.getSettingByKey('custom_flow_phases');
    if (setting != null) {
      final List<dynamic> jsonList = jsonDecode(setting.value);
      final parts = jsonList.map((e) {
        final duration = e['duration'];
        return '${duration}min';
      }).toList();
      setState(() => _customFlowDescription = parts.join(' -> '));
    } else {
      // 用默认配置
      setState(() => _customFlowDescription = '2min -> 15min');
    }
  }

  Future<IntensityMode?> _getFirstPhaseIntensityMode() async {
    if (_sessionMode == SessionMode.custom) {
      final setting = await _dbService.getSettingByKey('custom_flow_phases');
      if (setting != null) {
        final List<dynamic> jsonList = jsonDecode(setting.value);
        if (jsonList.isNotEmpty) {
          final firstPhase = jsonList[0];
          final mode = firstPhase['mode'];
          return mode == 'stimulation'
              ? IntensityMode.stimulation
              : IntensityMode.expression;
        }
      }
    }
    return null;
  }

  Future<int> _getTotalPhases() async {
    if (_sessionMode == SessionMode.custom) {
      final setting = await _dbService.getSettingByKey('custom_flow_phases');
      if (setting != null) {
        final List<dynamic> jsonList = jsonDecode(setting.value);
        return jsonList.length;
      }
    }
    return 2;
  }

  Future<List<Map<String, int>>> _getModeDurations() async {
    if (_sessionMode == SessionMode.custom) {
      final setting = await _dbService.getSettingByKey('custom_flow_phases');
      if (setting != null) {
        final List<dynamic> jsonList = jsonDecode(setting.value);
        return jsonList.map<Map<String, int>>((e) {
          return {e['mode']: e['duration'] as int};
        }).toList();
      }
    }
    return [
      {'stimulation': 2},
      {'expression': 15},
    ];
  }

  Future<Map<String, dynamic>> _getInitialDeviceState(bool isLeft) async {
    if (_sessionMode == SessionMode.custom) {
      // Custom mode：从数据库拿初始值
      final setting = await _dbService.getSettingByKey('custom_flow_phases');
      if (setting != null) {
        final List<dynamic> jsonList = jsonDecode(setting.value);
        if (jsonList.isNotEmpty) {
          final firstPhase = jsonList[0];
          final mode = firstPhase['mode'] as String;
          final duration = firstPhase['duration'] as int;
          final totalPhases = jsonList.length;

          final intensityMode = mode == 'stimulation'
              ? IntensityMode.stimulation
              : IntensityMode.expression;

          return {
            'elapsedTime': Duration.zero,
            'elapsedTimeInPhase': Duration.zero,
            'currentPhase': 1,
            'totalPhase': totalPhases,
            'phaseDuration': Duration(minutes: duration),
            'intensityMode': intensityMode,
          };
        }
      }
    }

    return {
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

  bool _getCurrentIsRunning() {
    switch (_selectedPump) {
      case PumpSelection.left:
        return _leftIsRunning;
      case PumpSelection.right:
        return _rightIsRunning;
      case PumpSelection.both:
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

  Future<IntensityMode> _getDisplayIntensityMode() async {
    final hasStarted = _getCurrentHasStarted();
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
                            Builder(
                              builder: (context) {
                                debugPrint('🔄 条件满足，准备切换到独立模式: hasStarted=${_getCurrentHasStarted()}, selectedPump=$_selectedPump, isSynchronized=${_areDevicesSynchronized()}');
                                // _buildSynchronizationWarning(),
                                return _switchToIndividualMode();
                              },
                            ),

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
    final device = _selectedPump == PumpSelection.left
        ? _leftDevice
        : _rightDevice;
    Color backgroundColor;
    Color textColor;
    bool showBattery = false;
    int batteryLevel = 0;
    if (device == null || !device.isRemembered) {
      backgroundColor = Colors.grey.shade300;
      textColor = Colors.grey.shade700;
    } else if (device.isRunning) {
      backgroundColor = const Color(0xFFE8F5E9);
      textColor = Colors.green;
      showBattery = true;
      batteryLevel = device.battery;
    } else {
      backgroundColor = const Color(0xFFFEF3C7);
      textColor = const Color(0xFFA16207);
    }
    final displayText = (device == null || !device.isRemembered)
        ? AppLocalizations.of(context)!.notAvailable
        : device.name;

    return Container(
      padding: ResponsiveText.symmetric(context, vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Text(
            displayText,
            style: ResponsiveText.bodySmall(
              context,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          if (showBattery) ...[
            SizedBox(width: ResponsiveText.getSize(context, 8)),
            _buildBatteryIndicator(batteryLevel),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceStatusCard(String side, ConnectedDevice? device) {
    String statusText;
    Color backgroundColor;
    Color borderColor;
    Color textColor;
    bool showBattery = false;
    int batteryLevel = 0;
    if (device == null || !device.isRemembered) {
      statusText = AppLocalizations.of(context)!.notAvailable;
      backgroundColor = Colors.grey.shade300;
      borderColor = Colors.grey.shade400;
      textColor = Colors.grey.shade700;
    } else if (device.isRunning) {
      statusText = AppLocalizations.of(context)!.connected;
      backgroundColor = const Color(0xFFE8F5E9);
      borderColor = const Color(0xFFC8E6C9);
      textColor = Colors.green;
      showBattery = true;
      batteryLevel = device.battery;
    } else {
      statusText = AppLocalizations.of(context)!.disconnected;
      backgroundColor = const Color(0xFFFEF3C7);
      borderColor = const Color.fromRGBO(0, 0, 0, 0.1);
      textColor = const Color(0xFFA16207);
    }

    return Container(
      padding: ResponsiveText.symmetric(context, vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          Text(
            '${side == 'L' ? AppLocalizations.of(context)!.left : AppLocalizations.of(context)!.right}: ',
            style: ResponsiveText.bodySmall(
              context,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          if (showBattery) ...[
            _buildBatteryIndicator(batteryLevel),
            SizedBox(width: ResponsiveText.getSize(context, 8)),
          ],
          Text(
            statusText,
            style: ResponsiveText.bodySmall(
              context,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

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
          Row(
            children: [
              Expanded(
                child: _buildSessionModeButton(
                  AppLocalizations.of(context)!.defaultMode,
                  SessionMode.defaultMode,
                ),
              ),
              SizedBox(width: ResponsiveText.getSize(context, 12)),
              Expanded(
                child: _buildSessionModeButton(
                  AppLocalizations.of(context)!.custom,
                  SessionMode.custom,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveText.getSize(context, 30)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _sessionMode == SessionMode.defaultMode
                    ? '2min -> 15min'
                    : _customFlowDescription,
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
              label == AppLocalizations.of(context)!.defaultMode
                  ? AppLocalizations.of(context)!.defaultFlow
                  : AppLocalizations.of(context)!.customFlow,
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
    // 未启动时，时间重置为 00:00
    final currentHasStarted = _getCurrentHasStarted();
    final displayMinutes = currentHasStarted
        ? _elapsedTime.inMinutes.toString().padLeft(2, '0')
        : '00';
    final displaySeconds = currentHasStarted
        ? (_elapsedTime.inSeconds % 60).toString().padLeft(2, '0')
        : '00';
    final isBoth = _selectedPump == PumpSelection.both;

    if (isBoth) {
      return FutureBuilder<Map<String, dynamic>>(
        future: _getTimerDisplayData(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox.shrink();
          }
          final data = snapshot.data!;

          // 获取左右两侧的独立状态
          final leftHasStarted = _leftHasStarted;
          final leftDisplayMinutes = leftHasStarted
              ? _leftElapsedTime.inMinutes.toString().padLeft(2, '0')
              : '00';
          final leftDisplaySeconds = leftHasStarted
              ? (_leftElapsedTime.inSeconds % 60).toString().padLeft(2, '0')
              : '00';
          final leftPhaseMinutes = _leftPhaseDuration.inMinutes
              .toString()
              .padLeft(2, '0');
          final leftPhaseSeconds = (_leftPhaseDuration.inSeconds % 60)
              .toString()
              .padLeft(2, '0');

          final rightHasStarted = _rightHasStarted;
          final rightDisplayMinutes = rightHasStarted
              ? _rightElapsedTime.inMinutes.toString().padLeft(2, '0')
              : '00';
          final rightDisplaySeconds = rightHasStarted
              ? (_rightElapsedTime.inSeconds % 60).toString().padLeft(2, '0')
              : '00';
          final rightPhaseMinutes = _rightPhaseDuration.inMinutes
              .toString()
              .padLeft(2, '0');
          final rightPhaseSeconds = (_rightPhaseDuration.inSeconds % 60)
              .toString()
              .padLeft(2, '0');

          // 运行时用 _leftTotalPhase 和 _rightTotalPhase（由 _handleSessionStatusUpdate 控制）
          // 未运行时根据当前 flow mode 动态获取
          final leftTotalPhases = currentHasStarted
              ? _leftTotalPhase
              : (data['totalPhases'] as int);
          final rightTotalPhases = currentHasStarted
              ? _rightTotalPhase
              : (data['totalPhases'] as int);

          return Row(
            children: [
              Expanded(
                child: _buildSingleTimerCard(
                  AppLocalizations.of(context)!.left,
                  leftDisplayMinutes,
                  leftDisplaySeconds,
                  leftPhaseMinutes,
                  leftPhaseSeconds,
                  leftTotalPhases,
                  _leftIntensityMode,
                  // 用左侧的强度模式
                  hasStarted: leftHasStarted,
                  currentPhase: _leftCurrentPhase,
                  elapsedTimeInPhase: _leftElapsedTimeInPhase,
                  maxDuration: _maxDuration,
                  deviceMaxDuration: leftHasStarted ? _deviceMaxDuration : null,
                ),
              ),
              SizedBox(width: ResponsiveText.getSize(context, 12)),
              Expanded(
                child: _buildSingleTimerCard(
                  AppLocalizations.of(context)!.right,
                  rightDisplayMinutes,
                  rightDisplaySeconds,
                  rightPhaseMinutes,
                  rightPhaseSeconds,
                  rightTotalPhases,
                  _rightIntensityMode,
                  // 用右侧的强度模式
                  hasStarted: rightHasStarted,
                  currentPhase: _rightCurrentPhase,
                  elapsedTimeInPhase: _rightElapsedTimeInPhase,
                  maxDuration: _maxDuration,
                  deviceMaxDuration: rightHasStarted ? _deviceMaxDuration : null,
                ),
              ),
            ],
          );
        },
      );
    }

    Future<Map<String, dynamic>?> getInitialStateFuture() async {
      if (currentHasStarted) return null;
      return await _getInitialDeviceState(_selectedPump == PumpSelection.left);
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

            final effectivePhaseMinutes = effectivePhaseDuration.inMinutes
                .toString()
                .padLeft(2, '0');
            final effectivePhaseSeconds =
                (effectivePhaseDuration.inSeconds % 60).toString().padLeft(
                  2,
                  '0',
                );

            return Container(
              padding: ResponsiveText.padding(
                context,
                left: 8,
                right: 12,
                top: 12,
                bottom: 8,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFDF7E4), Color(0xFFF5E6B3)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.grey.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(),
                      Container(
                        padding: ResponsiveText.symmetric(
                          context,
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColor.primaryPurple,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          displayMode == IntensityMode.stimulation
                              ? AppLocalizations.of(context)!.stimulation
                              : AppLocalizations.of(context)!.expression,
                          style: ResponsiveText.caption(
                            context,
                            fontWeight: FontWeight.w500,
                            color: AppColor.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Center(
                    child: Text(
                      '$displayMinutes:$displaySeconds',
                      style: ResponsiveText.extraLarge(
                        context,
                        color: AppColor.textPrimary,
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '${AppLocalizations.of(context)!.phase} $currentPhase/$effectiveTotalPhases: ${currentHasStarted ? _elapsedTimeInPhase.inMinutes.toString().padLeft(2, '0') : '00'}:${currentHasStarted ? (_elapsedTimeInPhase.inSeconds % 60).toString().padLeft(2, '0') : '00'} / $effectivePhaseMinutes:$effectivePhaseSeconds | ${AppLocalizations.of(context)!.max.replaceAll(RegExp(r':'), '')} ${currentHasStarted ? (_deviceMaxDuration ?? _maxDuration) : _maxDuration}${AppLocalizations.of(context)!.minutes}',
                      style: ResponsiveText.bodySmall(
                        context,
                        color: AppColor.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSingleTimerCard(
    String side,
    String minutes,
    String seconds,
    String phaseMinutes,
    String phaseSeconds,
    int totalPhases,
    IntensityMode displayMode, {
    bool? hasStarted,
    int? currentPhase,
    Duration? elapsedTimeInPhase,
    int? maxDuration,
    int? deviceMaxDuration,
  }) {
    // 如果提供了独立的状态参数就用它们，否则用全局状态（单边模式用）
    final currentHasStarted = hasStarted ?? _getCurrentHasStarted();
    final phase = currentPhase ?? (currentHasStarted ? _currentPhase : 1);
    final timeInPhase = elapsedTimeInPhase ?? _elapsedTimeInPhase;
    // Max 显示逻辑：运行时用 deviceMaxDuration ?? maxDuration，非运行时用 maxDuration
    final effectiveMaxDuration = currentHasStarted 
        ? (deviceMaxDuration ?? maxDuration ?? _maxDuration)
        : (maxDuration ?? _maxDuration);

    return Container(
      padding: ResponsiveText.padding(context, all: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFDF7E4), Color(0xFFF5E6B3)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            side,
            style: ResponsiveText.bodySmall(
              context,
              color: AppColor.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              color: AppColor.primaryPurple,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              displayMode == IntensityMode.stimulation
                  ? AppLocalizations.of(context)!.stim
                  : AppLocalizations.of(context)!.expr,
              style: ResponsiveText.bodySmall(context, color: AppColor.white),
            ),
          ),
          Center(
            child: Text(
              '$minutes:$seconds',
              style: ResponsiveText.style(
                context,
                fontSize: 30,
                color: AppColor.textPrimary,
              ),
            ),
          ),
          Center(
            child: Text(
              '$phase/$totalPhases: ${currentHasStarted ? timeInPhase.inMinutes.toString().padLeft(2, '0') : '00'}:${currentHasStarted ? (timeInPhase.inSeconds % 60).toString().padLeft(2, '0') : '00'}',
              style: ResponsiveText.bodySmall(
                context,
                color: AppColor.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Center(
            child: Text(
              '${AppLocalizations.of(context)!.max.replaceAll(RegExp(r':'), '')} $effectiveMaxDuration${AppLocalizations.of(context)!.minutes}',
              style: ResponsiveText.bodySmall(
                context,
                color: AppColor.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
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
    final hybridPatternEnabled = isLeft ? _leftHybridPatternEnabled : _rightHybridPatternEnabled;
    final hasStarted = isLeft ? _leftHasStarted : _rightHasStarted;
    final device = isLeft ? _leftDevice : _rightDevice;

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
                      setState(() {
                        if (isLeft) {
                          _leftHybridPatternEnabled = value;
                        } else {
                          _rightHybridPatternEnabled = value;
                        }
                      });
                      // 与 suctionlevel 一致：页面操作后持久化到数据库
                      if (isLeft) {
                        _persistHybridPattern(_keyLeftHybridPattern, value);
                      } else {
                        _persistHybridPattern(_keyRightHybridPattern, value);
                      }

                      if (hasStarted && device != null) {
                        _recordUserHybridPatternOperation(device, DpConstants.stimulationHybrid, value);
                        // 跟硬件配合 固定只发刺激模式
                        BleDpService.publishDp(
                          device.bluetoothId,
                          DpConstants.stimulationHybrid,
                          value,
                        );
                        // // 暂停500ms
                        // await Future.delayed(const Duration(milliseconds: 500));
                        // BleDpService.publishDps(
                        //   device.bluetoothId,
                        //   [
                        //     DpData(dpId: DpConstants.expressionHybrid, value: value)
                        //   ],
                        // );
                      }
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
                      setState(() {
                        _setCurrentHybridPattern(value);
                      });
                      // 与 suctionlevel 一致：页面操作后持久化到数据库
                      if (_selectedPump == PumpSelection.left) {
                        _persistHybridPattern(_keyLeftHybridPattern, value);
                      } else if (_selectedPump == PumpSelection.right) {
                        _persistHybridPattern(_keyRightHybridPattern, value);
                      } else {
                        _persistHybridPattern(_keyLeftHybridPattern, value);
                        _persistHybridPattern(_keyRightHybridPattern, value);
                      }

                      final currentHasStarted = _getCurrentHasStarted();
                      if (currentHasStarted) {
                        if (_leftDevice != null && (_selectedPump == PumpSelection.left || _selectedPump == PumpSelection.both)) {
                          _recordUserHybridPatternOperation(_leftDevice, DpConstants.stimulationHybrid, value);
                        }
                        if (_rightDevice != null && (_selectedPump == PumpSelection.right || _selectedPump == PumpSelection.both)) {
                          _recordUserHybridPatternOperation(_rightDevice, DpConstants.stimulationHybrid, value);
                        }
                        // 跟硬件配合：固定只发刺激模式 107
                        _publishDpToDevices(DpConstants.stimulationHybrid, value);
                      }
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
    debugPrint('🔄 设备同步状态: $result');
    
    // 如果已经是独立模式
    if (_isIndividualMode) {
      // 如果设备重新同步，退出独立模式
      if (result) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isIndividualMode) {
            setState(() {
              _isIndividualMode = false;
              _bothNotSynchronizedCount = 0;
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
    if (!result) {
      _bothNotSynchronizedCount++;
    } else {
      _bothNotSynchronizedCount = 0;
    }
    // 当计数 >= 6 时，认为设备不同步（返回 false）
    // 当计数 < 6 时，认为设备同步（返回 true）
    return _bothNotSynchronizedCount < 6;
  }

  bool _checkDevicesSynchronization() {
    // if (_leftStimulationSuctionLevel != _rightStimulationSuctionLevel) {
    //   return false;
    // }
    // if (_leftExpressionSuctionLevel != _rightExpressionSuctionLevel) {
    //   return false;
    // }
    // if (_leftHybridPatternEnabled != _rightHybridPatternEnabled) {
    //   return false;
    // }
    if (_leftIntensityMode != _rightIntensityMode) {
      return false;
    }
    if (_leftCurrentPhase != _rightCurrentPhase) {
      return false;
    }
    // if (_leftTotalPhase != _rightTotalPhase) {
    //   return false;
    // }
    if ((_leftElapsedTime.inSeconds - _rightElapsedTime.inSeconds).abs() > 10) {
      return false;
    }
    if ((_leftElapsedTimeInPhase.inSeconds - _rightElapsedTimeInPhase.inSeconds)
            .abs() >
        10) {
      return false;
    }
    // if (_leftPhaseDuration != _rightPhaseDuration) {
    //   return false;
    // }
    return true;
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

  void _publishDpToDevices(String dpId, dynamic value) {
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
                            _setCurrentIsRunning(true);
                            _setCurrentHasStarted(true);
                          });

                          // setState 之后执行异步操作
                          if (AppConfig.tuyaEnabled &&
                              modeDurations != null &&
                              totalPhase != null) {
                            final isCustom = _sessionMode == SessionMode.custom;

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
                            } else if (_selectedPump == PumpSelection.both) {
                              _bothNotSynchronizedCount = 0;
                              // both 模式保持用户配置的左右独立吸力，不下发时覆盖右侧
                              final leftStimulationSucLvl =
                                  _leftStimulationSuctionLevel.toInt();
                              final leftExpressionSucLvl =
                                  _leftExpressionSuctionLevel.toInt();
                              final rightStimulationSucLvl =
                                  _rightStimulationSuctionLevel.toInt();
                              final rightExpressionSucLvl =
                                  _rightExpressionSuctionLevel.toInt();
                              final hybridPattern = _getCurrentHybridPattern();
                              // 并发执行两个设备的配置下发，左右各自使用各自的吸力
                              final futures = <Future>[];
                              if (_leftDevice != null) {
                                futures.add(
                                  BleDpService.pushSessionSetting(
                                    _leftDevice!.bluetoothId,
                                    _maxDuration,
                                    isCustom,
                                    totalPhase,
                                    leftStimulationSucLvl,
                                    leftExpressionSucLvl,
                                    hybridPattern,
                                    hybridPattern,
                                    modeDurations,
                                  ),
                                );
                              }
                              if (_rightDevice != null) {
                                futures.add(
                                  BleDpService.pushSessionSetting(
                                    _rightDevice!.bluetoothId,
                                    _maxDuration,
                                    isCustom,
                                    totalPhase,
                                    rightStimulationSucLvl,
                                    rightExpressionSucLvl,
                                    hybridPattern,
                                    hybridPattern,
                                    modeDurations,
                                  ),
                                );
                              }
                              if (futures.isNotEmpty) {
                                await Future.wait(futures);
                              }
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
