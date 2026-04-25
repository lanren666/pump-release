import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'pages/home.dart';
import 'config/app_config.dart';
import 'config/locale_manager.dart';
import 'services/diagnostics/app_logger.dart';
import 'services/tuya/dp_change_handle.dart';
import 'services/tuya/tuya_sdk_service.dart';
import 'services/database_service.dart';
import 'services/tuya/dp_constants.dart';
import 'services/tuya/ble_dp_service.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    void startApp() {
      if (AppConfig.diagnosticsEnabled) {
        FlutterError.onError = (FlutterErrorDetails details) {
          AppLogger.recordFlutterError(details);
          FlutterError.presentError(details);
        };
        PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
          AppLogger.recordError(error, stack, source: 'platform');
          return true;
        };
      }

      if (AppConfig.tuyaEnabled) {
        DpChangeHandle.init();
        // Warm up home preparation in background to reduce first-connect latency.
        // iOS native channels are set up with a short delay; keep this slightly later
        // to avoid MissingPluginException during cold start.
        Future.delayed(const Duration(milliseconds: 800), () {
          TuyaSdkService.warmUpHomeReady();
        });
      } else {
        debugPrint('涂鸦功能已禁用，跳过 SDK 初始化');
      }

      runApp(const PumpApp());
    }

    if (AppConfig.diagnosticsEnabled) {
      AppLogger.ensureInitialized().then((_) {
        startApp();
      }).catchError((Object e, StackTrace st) {
        debugPrint('AppLogger init failed: $e');
        startApp();
      });
    } else {
      startApp();
    }
  }, (Object error, StackTrace stack) {
    if (AppConfig.diagnosticsEnabled) {
      AppLogger.recordError(error, stack, source: 'zone');
    } else if (kDebugMode) {
      debugPrint('Zone error: $error\n$stack');
    }
  });
}

class PumpApp extends StatefulWidget {
  const PumpApp({super.key});

  @override
  State<PumpApp> createState() => _PumpAppState();
}

class _PumpAppState extends State<PumpApp> with WidgetsBindingObserver {
  Timer? _periodicTimer;
  bool _isTaskRunning = false;
  DateTime? _taskStartTime;
  static const _connectionChannel = MethodChannel(
    'com.sporramom/ble_connection',
  );
  final DatabaseService _dbService = DatabaseService();
  final LocaleManager _localeManager = LocaleManager();
  Locale? _locale;
  bool _isLoadingLocale = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _localeManager.localeNotifier.addListener(_onLocaleChanged);
    _loadLanguageSetting();
    _startPeriodicTask();
  }

  void _onLocaleChanged() {
    if (mounted) {
      setState(() {
        _locale = _localeManager.localeNotifier.value;
      });
    }
  }

  Future<void> _loadLanguageSetting() async {
    try {
      const languageKey = 'app_language';
      final languageSetting = await _dbService.getSettingByKey(languageKey);

      Locale? newLocale;
      if (languageSetting != null) {
        if (languageSetting.value == 'zh') {
          newLocale = const Locale('zh', 'CN');
        } else {
          newLocale = const Locale('en', 'US');
        }
      } else {
        // 没设置就用默认的
        newLocale = AppConfig.debugLocale;
      }

      _localeManager.localeNotifier.value = newLocale;

      if (mounted) {
        setState(() {
          _isLoadingLocale = false;
        });
      }
    } catch (e) {
      debugPrint('加载语言设置失败: $e');
      if (mounted) {
        setState(() {
          _locale = AppConfig.debugLocale;
          _isLoadingLocale = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    _localeManager.localeNotifier.removeListener(_onLocaleChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startPeriodicTask() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _executePeriodicTask();
    });
  }

  void _stopPeriodicTask() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// 回到前台时：对「已连接且在线」的设备重新注册监听，避免后台被系统杀掉监听后收不到 DP 上报。
  void _onForegroundResumeListenerInit() async {
    if (!AppConfig.tuyaEnabled) return;

    try {
      final rememberedDevices = await _dbService.getRememberedDevices();
      if (rememberedDevices.isEmpty) return;

      for (final device in rememberedDevices) {
        if (device.devId == null || device.devId!.isEmpty) continue;
        if (!device.isRunning) continue;

        try {
          final isOnline =
              await _connectionChannel.invokeMethod('isDeviceOnline', {
                    'deviceId': device.devId,
                  })
                  as bool? ??
              false;
          if (!isOnline) continue;

          await _connectionChannel.invokeMethod('registerDeviceListener', {
            'deviceId': device.devId,
          });
          debugPrint('前台恢复: 已重新注册设备监听 devId=${device.devId}');
        } catch (e) {
          debugPrint('前台恢复: 检查/注册设备 ${device.devId} 失败: $e');
        }
      }
    } catch (e) {
      debugPrint('前台恢复监听初始化失败: $e');
    }
  }

  void _executePeriodicTask() async {
    if (!AppConfig.tuyaEnabled) {
      return;
    }

    // 如果上一个任务还在执行，检查是否超时
    if (_isTaskRunning) {
      if (_taskStartTime != null) {
        final duration = DateTime.now().difference(_taskStartTime!);
        // 如果超过30秒还没完成，强制重置（可能是异常情况）
        if (duration.inSeconds > 30) {
          // debugPrint('周期性任务执行超时，强制重置状态');
          _isTaskRunning = false;
          _taskStartTime = null;
        } else {
          // debugPrint('周期性任务正在执行中，跳过本次');
          return;
        }
      } else {
        // debugPrint('周期性任务正在执行中，跳过本次');
        return;
      }
    }

    _isTaskRunning = true;
    _taskStartTime = DateTime.now();
    try {
      final rememberedDevices = await _dbService.getRememberedDevices();

      if (rememberedDevices.isEmpty) {
        return;
      }

      debugPrint('周期性任务: 检查 ${rememberedDevices.length} 个设备');

      for (final device in rememberedDevices) {
        if (device.devId == null || device.devId!.isEmpty) {
          debugPrint('设备缺少 devId，跳过: ${device.name}');
          continue;
        }

        if (device.isRunning) {
          continue;
        }

        debugPrint('发现未运行的设备，尝试重连: ${device.name} (devId: ${device.devId})');

        // 先检查是否已经在线
        try {
          final isOnline =
              await _connectionChannel.invokeMethod('isDeviceOnline', {
                    'deviceId': device.devId,
                  })
                  as bool? ??
              false;

          if (isOnline) {
            debugPrint('设备已在线，更新状态并注册监听器: ${device.devId}');
            await _updateDeviceRunningStatus(device.devId!, true);
            
            // 注册设备监听器，确保能接收到 DP 更新和状态变化
            try {
              await _connectionChannel.invokeMethod('registerDeviceListener', {
                'deviceId': device.devId,
              });
              debugPrint('设备监听器注册成功: ${device.devId}');
            } catch (e) {
              debugPrint('注册设备监听器失败: $e');
            }
            
            continue;
          }
        } catch (e) {
          debugPrint('检查设备在线状态失败: $e');
        }

        // 不在线就尝试连接
        debugPrint('设备离线，尝试连接: ${device.devId}');
        try {
          final connectionResults =
              await _connectionChannel.invokeMethod('connectBleDevices', {
                    'deviceIds': [device.devId],
                  })
                  as Map<dynamic, dynamic>?;

          if (connectionResults != null) {
            final connected = connectionResults[device.devId] as bool? ?? false;
            debugPrint('设备连接结果: ${device.devId} -> $connected');

            await _updateDeviceRunningStatus(device.devId!, connected);

            if (connected) {
              debugPrint('设备重连成功: ${device.devId}');
            } else {
              debugPrint('设备重连失败: ${device.devId}');
            }
          } else {
            debugPrint('连接设备失败，无法获取连接结果: ${device.devId}');
          }
        } catch (e) {
          debugPrint('重连设备时出错: $e');
        }
      }
    } catch (e) {
      debugPrint('周期性任务执行出错: $e');
    } finally {
      _isTaskRunning = false;
      _taskStartTime = null;
    }
  }

  // 连续发送三次设备符号，间隔1秒
  void _publishDeviceSymbolThrice(String bluetoothId, String position) {
    unawaited(_publishDeviceSymbolThriceAsync(bluetoothId, position));
  }

  Future<void> _publishDeviceSymbolThriceAsync(
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

  Future<void> _updateDeviceRunningStatus(String devId, bool isRunning) async {
    try {
      final device = await _dbService.getDeviceByDevId(devId);

      if (device == null) {
        debugPrint('未找到设备: devId=$devId');
        return;
      }

      // 只更新已记住的设备
      if (!device.isRemembered) {
        debugPrint('设备未记住，跳过更新: devId=$devId');
        return;
      }

      final updatedDevice = device.copyWith(isRunning: isRunning);
      await _dbService.updateDevice(updatedDevice);

      if (isRunning) {
        _publishDeviceSymbolThrice(device.bluetoothId, device.position);
      }

      debugPrint('设备运行状态已更新: devId=$devId, isRunning=$isRunning');
    } catch (e) {
      debugPrint('更新设备运行状态失败: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        // 先对「已连接且在线」的设备重新注册监听，避免后台监听被系统杀掉导致回前台无数据
        _onForegroundResumeListenerInit();
        // 重置任务状态，防止异常情况下卡住
        _isTaskRunning = false;
        _taskStartTime = null;
        _startPeriodicTask();
        debugPrint('应用进入前台，恢复周期性任务');
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // 后台也可以继续运行，需要的话可以在这里停止
        // _stopPeriodicTask();
        break;
      case AppLifecycleState.detached:
        _stopPeriodicTask();
        _isTaskRunning = false;
        _taskStartTime = null;
        if (AppConfig.tuyaEnabled) {
          DpChangeHandle.dispose();
          debugPrint('应用退出，已清理 DP 上报监听');
        }
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> reloadLanguageSetting() async {
    await _loadLanguageSetting();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingLocale) {
      return MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      title: 'Wearable Breast Pump',
      theme: ThemeData(useMaterial3: true),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
      locale: _locale,
      home: const HomePage(),
    );
  }
}
