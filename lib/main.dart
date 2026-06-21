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
import 'services/tuya/device_listener_service.dart';
import 'services/tuya/device_reconnect_policy.dart';
import 'services/tuya/native_ble_device_id.dart';
import 'services/tuya/running_status_log.dart';
import 'models/connected_device.dart';

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
  bool _hasSavedLanguagePreference = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _localeManager.localeNotifier.addListener(_onLocaleChanged);
    _loadLanguageSetting();
    _startPeriodicTask();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_executePeriodicTask());
    });
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

      final Locale newLocale;
      if (languageSetting != null) {
        _hasSavedLanguagePreference = true;
        newLocale = LocaleManager.localeForLanguageCode(languageSetting.value);
      } else if (AppConfig.debugLocale != null) {
        _hasSavedLanguagePreference = false;
        newLocale = AppConfig.debugLocale!;
      } else {
        // No saved preference: resolve system locale explicitly. Passing null to
        // MaterialApp.locale relies on LocalizationsResolver._resolvedLocale
        // captured at cold start, which may still be en before the platform
        // locale is ready (while PlatformDispatcher.locale is already zh).
        _hasSavedLanguagePreference = false;
        newLocale = LocaleManager.resolveSystemLocale();
      }

      _localeManager.localeNotifier.value = newLocale;

      if (mounted) {
        setState(() {
          _locale = newLocale;
          _isLoadingLocale = false;
        });
      }
    } catch (e) {
      debugPrint('加载语言设置失败: $e');
      final Locale fallbackLocale =
          AppConfig.debugLocale ?? LocaleManager.resolveSystemLocale();
      _hasSavedLanguagePreference = false;
      _localeManager.localeNotifier.value = fallbackLocale;
      if (mounted) {
        setState(() {
          _locale = fallbackLocale;
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
        if (!device.isRunning) continue;

        final registered = await DeviceListenerService.registerIfRunning(device);
        if (registered) {
          debugPrint('前台恢复: 已重新注册设备监听 bluetoothId=${device.bluetoothId}');
        }
      }
    } catch (e) {
      debugPrint('前台恢复监听初始化失败: $e');
    }
  }

  Future<Map<String, bool>> _fetchDevicesOnlineMap(
    List<ConnectedDevice> devices,
  ) async {
    final withDevId = devices
        .where((d) => d.devId != null && d.devId!.isNotEmpty)
        .toList();
    if (withDevId.isEmpty) return {};

    try {
      final raw =
          await _connectionChannel.invokeMethod('checkDevicesOnline', {
                'deviceIds': withDevId.map((d) => d.devId!).toList(),
              })
              as Map<dynamic, dynamic>?;
      if (raw == null) return {};

      final result = <String, bool>{};
      for (final device in withDevId) {
        final status = raw[device.devId];
        if (status is bool) {
          result[device.devId!] = status;
        }
      }
      return result;
    } catch (e) {
      debugPrint('批量检查设备在线状态失败: $e');
      return {};
    }
  }

  Future<bool> _isDeviceBleOnline(ConnectedDevice device) async {
    try {
      return await _connectionChannel.invokeMethod('isDeviceOnline', {
                'deviceId': device.nativeBleId,
              })
              as bool? ??
          false;
    } catch (e) {
      debugPrint('检查设备在线状态失败: $e');
      return false;
    }
  }

  Future<void> _healDeviceFromDp105(ConnectedDevice device) async {
    OfflineStreakTracker.reset(device.bluetoothId);
    debugPrint('DP105 近期活跃，恢复连接状态: devId=${device.devId}');
    if (!device.isRunning) {
      await _updateDeviceRunningStatus(
        device.devId!,
        true,
        source: 'periodic_dp105_heal',
      );
    }
    await DeviceListenerService.registerIfRunning(
      device.copyWith(isRunning: true),
      bypassOnlineCheck: true,
    );
  }

  Future<void> _markDeviceOnlineFromProbe(ConnectedDevice device) async {
    OfflineStreakTracker.reset(device.bluetoothId);
    debugPrint('设备已在线，更新状态并注册监听器: ${device.devId}');
    await _updateDeviceRunningStatus(
      device.devId!,
      true,
      source: 'periodic_already_online',
    );
    await DeviceListenerService.registerIfRunning(device);
  }

  Future<void> _applyBatchConnectResults(
    List<ConnectedDevice> devices,
    Map<dynamic, dynamic>? connectionResults,
  ) async {
    if (connectionResults == null) {
      debugPrint('批量连接失败，无法获取连接结果');
      return;
    }

    for (final device in devices) {
      if (device.devId == null || device.devId!.isEmpty) continue;

      final connected =
          connectionResults[device.nativeBleId] as bool? ?? false;
      debugPrint('设备连接结果: ${device.nativeBleId} -> $connected');

      if (connected) {
        OfflineStreakTracker.reset(device.bluetoothId);
        await _updateDeviceRunningStatus(
          device.devId!,
          true,
          source: 'periodic_reconnect_ok',
        );
        debugPrint('设备重连成功: ${device.devId}');
        await DeviceListenerService.registerIfRunning(
          device.copyWith(isRunning: true),
        );
        continue;
      }

      if (DeviceReconnectPolicy.shouldHealRunningFromDp(devId: device.devId!)) {
        await _healDeviceFromDp105(device);
      } else {
        debugPrint('设备重连失败: ${device.devId}');
      }
    }
  }

  Future<void> _batchConnectDevices(List<ConnectedDevice> devices) async {
    if (devices.isEmpty) return;

    final nativeIds = devices.map((d) => d.nativeBleId).toList();
    debugPrint('批量重连 ${devices.length} 台设备: $nativeIds');

    try {
      final connectionResults =
          await _connectionChannel.invokeMethod('connectBleDevices', {
                'deviceIds': nativeIds,
              })
              as Map<dynamic, dynamic>?;
      await _applyBatchConnectResults(devices, connectionResults);
    } catch (e) {
      debugPrint('批量重连设备时出错: $e');
    }
  }

  Future<void> _executePeriodicTask() async {
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

      final readyHomeId = await TuyaSdkService.ensureHomeReady(
        timeout: const Duration(seconds: 15),
      );
      if (readyHomeId == null || readyHomeId.isEmpty) {
        debugPrint('周期性任务跳过: 涂鸦 home 未就绪');
        return;
      }

      debugPrint('周期性任务: 检查 ${rememberedDevices.length} 个设备');
      final isColdStartPass = OfflineStreakTracker.coldStartPassActive;
      if (isColdStartPass) {
        debugPrint('冷启动设备同步：跳过 offline 防抖，并行重连');
      }

      final onlineMap = await _fetchDevicesOnlineMap(rememberedDevices);
      final devicesToConnect = <ConnectedDevice>[];

      for (final device in rememberedDevices) {
        if (device.devId == null || device.devId!.isEmpty) {
          debugPrint('设备缺少 devId，跳过: ${device.name}');
          continue;
        }

        final batchOnline = onlineMap[device.devId];
        var shouldReconnect = !device.isRunning;

        if (device.isRunning) {
          try {
            final isOnline = batchOnline ?? await _isDeviceBleOnline(device);

            if (DeviceReconnectPolicy.shouldRegisterListenerOnly(
              isRunning: device.isRunning,
              isOnline: isOnline,
            )) {
              OfflineStreakTracker.reset(device.bluetoothId);
              await DeviceListenerService.registerIfRunning(device);
              continue;
            }

            if (DeviceReconnectPolicy.isStaleRunningState(
              isRunning: device.isRunning,
              isOnline: isOnline,
            )) {
              if (DeviceReconnectPolicy.shouldSuppressRunningFalse(
                devId: device.devId!,
                isOnline: isOnline,
              )) {
                OfflineStreakTracker.reset(device.bluetoothId);
                await DeviceListenerService.registerIfRunning(
                  device,
                  bypassOnlineCheck: true,
                );
                continue;
              }

              if (isColdStartPass) {
                OfflineStreakTracker.reset(device.bluetoothId);
                debugPrint(
                  '冷启动纠正 stale isRunning: devId=${device.devId}, '
                  'bluetoothId=${device.bluetoothId}',
                );
                await _updateDeviceRunningStatus(
                  device.devId!,
                  false,
                  source: 'cold_start_stale_offline',
                );
                shouldReconnect = true;
              } else {
                final streak =
                    OfflineStreakTracker.recordOffline(device.bluetoothId);
                if (!OfflineStreakTracker.isConfirmedOffline(
                  device.bluetoothId,
                )) {
                  debugPrint(
                    '设备离线探测 $streak/${OfflineStreakTracker.confirmThreshold}，'
                    '暂不改 isRunning: devId=${device.devId}, '
                    'bluetoothId=${device.bluetoothId}',
                  );
                  continue;
                }

                OfflineStreakTracker.reset(device.bluetoothId);
                debugPrint(
                  '设备持续离线，纠正 isRunning: devId=${device.devId}, '
                  'bluetoothId=${device.bluetoothId}',
                );
                await _updateDeviceRunningStatus(
                  device.devId!,
                  false,
                  source: 'periodic_stale_offline',
                  streak: streak,
                );
                shouldReconnect = true;
              }
            }
          } catch (e) {
            debugPrint('检查运行中设备在线状态失败: $e');
            continue;
          }
        }

        if (!shouldReconnect) {
          continue;
        }

        debugPrint(
          '发现未运行的设备，待重连: ${device.name} (devId: ${device.devId}, bluetoothId: ${device.bluetoothId})',
        );

        if (DeviceReconnectPolicy.shouldHealRunningFromDp(
          devId: device.devId!,
        )) {
          await _healDeviceFromDp105(device);
          continue;
        }

        final isOnline = batchOnline ?? await _isDeviceBleOnline(device);
        if (isOnline) {
          await _markDeviceOnlineFromProbe(device);
          continue;
        }

        devicesToConnect.add(device);
      }

      if (devicesToConnect.isNotEmpty) {
        await _batchConnectDevices(devicesToConnect);
      }
    } catch (e) {
      debugPrint('周期性任务执行出错: $e');
    } finally {
      OfflineStreakTracker.completeColdStartPass();
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

  Future<void> _updateDeviceRunningStatus(
    String devId,
    bool isRunning, {
    required String source,
    int? streak,
  }) async {
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
      if (device.isRunning == isRunning) {
        return;
      }

      RunningStatusLog.log(
        source: source,
        devId: devId,
        isRunning: isRunning,
        streak: streak,
      );

      final updatedDevice = device.copyWith(isRunning: isRunning);
      await _dbService.updateDevice(updatedDevice);

      if (isRunning && !device.isRunning) {
        _publishDeviceSymbolThrice(device.bluetoothId, device.position);
      }
    } catch (e) {
      debugPrint('更新设备运行状态失败: $e');
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_hasSavedLanguagePreference) {
      return;
    }
    final Locale resolved = LocaleManager.resolveLocaleFromPreferredList(locales);
    _localeManager.localeNotifier.value = resolved;
    if (mounted) {
      setState(() {
        _locale = resolved;
      });
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
      supportedLocales: LocaleManager.supportedLocales,
      locale: _locale,
      localeResolutionCallback: (locale, supportedLocales) =>
          LocaleManager.resolveLocale(locale),
      home: const HomePage(),
    );
  }
}
