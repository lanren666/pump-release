import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../config/app_color.dart';
import '../config/responsive_text.dart';
import '../config/app_config.dart';
import '../config/ble_channels.dart';
import '../models/connected_device.dart';
import '../services/tuya/tuya_sdk_service.dart';
import '../models/bluetooth_device.dart';
import '../models/search_state.dart';
import '../services/database_service.dart';
import '../services/tuya/ble_dp_service.dart';
import '../services/tuya/dp_constants.dart';
import '../services/tuya/device_listener_service.dart';
import '../services/tuya/device_reconnect_policy.dart';
import '../l10n/app_localizations.dart';
import '../services/diagnostics/app_logger.dart';
import '../services/battery/battery_alert_logic.dart';
import '../services/battery/battery_voltage_service.dart';
import 'control.dart';
import 'widgets/pump_side_dialog.dart';
import 'widgets/low_battery_dialog.dart';
import 'database_viewer.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  SearchState _searchState = SearchState.idle;
  final List<BluetoothDevice> _devices = [];
  final List<ConnectedDevice> _connectedDevices = [];
  bool _isStatusMessageVisible = false;
  String _statusMessage = '';
  late AnimationController _statusAnimationController;
  late Animation<Offset> _statusSlideAnimation;
  StreamSubscription<dynamic>? _bleScanSubscription;
  StreamSubscription<dynamic>? _connectionEventSubscription;
  Timer? _refreshTimer;
  final DatabaseService _dbService = DatabaseService();
  final List<BluetoothDevice> _scannedDevices = [];
  ConnectedDevice? _devicePendingConnectLowBatteryCheck;

  @override
  void initState() {
    super.initState();
    if (AppConfig.tuyaEnabled) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (AppConfig.tuyaEnabled) {
          _setupBleScanListener();
        }
        _setupConnectionEventListener();
      });
    }
    _loadRememberedDevices();
    _startRefreshTimer();
    _statusAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _statusSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _statusAnimationController,
            curve: Curves.easeOut,
            reverseCurve: Curves.easeIn,
          ),
        );
  }

  Future<void> _loadRememberedDevices() async {
    final rememberedDevices = await _dbService.getRememberedDevices();
    if (mounted) {
      setState(() {
        _connectedDevices.clear();
        if (rememberedDevices.isNotEmpty) {
          _connectedDevices.addAll(rememberedDevices);
        }
      });
      await _checkAndConnectRememberedDevices(rememberedDevices);
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        _refreshDeviceStatus();
      }
    });
  }

  Future<void> _refreshDeviceStatus() async {
    try {
      final rememberedDevices = await _dbService.getRememberedDevices();
      if (!mounted) return;

      setState(() {
        _connectedDevices.clear();
        _connectedDevices.addAll(rememberedDevices);
      });
    } catch (e) {
      debugPrint('❌ 刷新设备状态失败: $e');
    }
  }

  Future<void> _checkAndConnectRememberedDevices(
    List<ConnectedDevice> devices,
  ) async {
    if (!AppConfig.tuyaEnabled) {
      return;
    }

    final devicesWithDevId = devices
        .where((d) => d.devId != null && d.devId!.isNotEmpty)
        .toList();
    if (devicesWithDevId.isEmpty) {
      return;
    }

    try {
      final readyHomeId = await TuyaSdkService.ensureHomeReady(
        timeout: const Duration(seconds: 15),
      );
      if (readyHomeId == null || readyHomeId.isEmpty) {
        debugPrint('checkDevicesOnline 跳过: 涂鸦 home 未就绪');
        return;
      }

      final deviceIds = devicesWithDevId.map((d) => d.devId!).toList();
      final onlineStatusMap =
          await connectionChannel.invokeMethod('checkDevicesOnline', {
                'deviceIds': deviceIds,
              })
              as Map<dynamic, dynamic>?;

      if (onlineStatusMap == null) {
        debugPrint('❌ 检查设备在线状态失败');
        return;
      }

      final offlineDevices = <ConnectedDevice>[];
      for (final device in devicesWithDevId) {
        final rawStatus = onlineStatusMap[device.devId];
        if (rawStatus is! bool) {
          debugPrint(
            '⚠️ checkDevicesOnline 返回缺少/非bool状态，跳过本次状态更新: devId=${device.devId}, raw=$rawStatus',
          );
          continue;
        }
        final isOnline = rawStatus;

        if (!isOnline) {
          offlineDevices.add(device);
        } else {
          NetworkStatusRunningPolicy.onOnline(device.bluetoothId);
          debugPrint(
            '🧭 isRunning 更新来源=checkDevicesOnline: devId=${device.devId}, isOnline=$isOnline',
          );
          await _updateDeviceRunningStatus(device.devId!, true);
          await DeviceListenerService.registerIfRunning(
            device.copyWith(isRunning: true),
          );
        }
      }

      if (offlineDevices.isNotEmpty) {
        for (final device in offlineDevices) {
          if (!NetworkStatusRunningPolicy.shouldApplyRunningFalse(
            dbIsRunning: device.isRunning,
            bluetoothId: device.bluetoothId,
          )) {
            final streak =
                OfflineStreakTracker.currentStreak(device.bluetoothId);
            debugPrint(
              'checkDevicesOnline 离线 $streak/'
              '${OfflineStreakTracker.confirmThreshold}，暂不改 isRunning: '
              'devId=${device.devId}, bluetoothId=${device.bluetoothId}',
            );
            continue;
          }

          if (device.devId != null &&
              DeviceReconnectPolicy.shouldSuppressRunningFalse(
                devId: device.devId!,
                isOnline: false,
              )) {
            debugPrint(
              'checkDevicesOnline 确认离线但 DP105 仍活跃，暂不改 isRunning: '
              'devId=${device.devId}',
            );
            continue;
          }
          debugPrint(
            '🧭 isRunning 更新来源=checkDevicesOnline(确认离线): devId=${device.devId}',
          );
          await _updateDeviceRunningStatus(device.devId!, false);
        }
      }
    } catch (e) {
      debugPrint('❌ 检查并连接设备时出错: $e');
    }
  }

  bool get _isAnyDeviceReconnecting =>
      _connectedDevices.any((d) => !d.isRunning);

  bool _hasAvailableDevices() {
    return _devices.any((device) {
      return !_connectedDevices.any(
        (connected) => connected.bluetoothId == device.bluetoothId,
      );
    });
  }

  void _setupBleScanListener() {
    _bleScanSubscription?.cancel();
    _bleScanSubscription = null;

    try {
      final stream = bleEventChannel.receiveBroadcastStream();
      _bleScanSubscription = stream.listen(
        (event) {
          if (event == 'SCAN_TIMEOUT' || event == 'SCAN_STOPPED') {
            if (mounted) {
              // 先更新设备列表，然后检查是否有可用设备
              _updateDeviceList().then((_) {
                if (mounted) {
                  setState(() {
                    // 如果有可用设备，设置为found
                    if (_hasAvailableDevices()) {
                      _searchState = SearchState.found;
                    } else if (event == 'SCAN_STOPPED' && _searchState == SearchState.searching) {
                      // 如果收到SCAN_STOPPED且正在搜索，可能是快速点击导致的
                      // Android端会在200ms后重新开始扫描，所以保持searching状态
                      // 这样新扫描到的设备可以立即显示
                      _searchState = SearchState.searching;
                    } else if (event == 'SCAN_TIMEOUT') {
                      // 超时时，如果没有设备，设置为idle
                      _searchState = SearchState.idle;
                    } else {
                      // 其他情况设置为idle
                      _searchState = SearchState.idle;
                    }
                  });
                }
              });
            }
          } else if (event is String && event.startsWith('{')) {
            try {
              final deviceJson = jsonDecode(event) as Map<String, dynamic>;
              final deviceId = deviceJson['id'] as String? ?? '';
              final devId = deviceJson['devId'] as String? ?? '';
              final uuid = deviceJson['uuid'] as String? ?? '';
              final productKey = deviceJson['providerName'] as String? ?? '';

              debugPrint('🔍 设备信息: $deviceJson');

              if (deviceId.isNotEmpty && uuid.isNotEmpty) {
                if (!_scannedDevices.any((d) => d.bluetoothId == deviceId)) {
                  final scannedDevice = BluetoothDevice(
                    bluetoothId: deviceId,
                    name: "",
                    battery: 3,
                    uuid: uuid,
                    productKey: productKey,
                    devId: devId,
                  );

                  if (mounted) {
                    // 保存当前状态，用于后续检查
                    final wasSearching = _searchState == SearchState.searching;
                    final wasIdle = _searchState == SearchState.idle;
                    final currentDeviceCount = _scannedDevices.length;
                    
                    setState(() {
                      _scannedDevices.add(scannedDevice);
                      
                      // 如果正在搜索或者是idle状态（可能是快速点击导致的），立即添加设备到_devices并更新状态
                      // 这样可以立即显示设备，不等待_updateDeviceList完成
                      if (wasSearching || wasIdle) {
                        // 快速添加设备到_devices列表
                        if (!_devices.any((d) => d.bluetoothId == deviceId)) {
                          final indexStr = (currentDeviceCount + 1).toString().padLeft(3, '0');
                          _devices.add(
                            BluetoothDevice(
                              bluetoothId: deviceId,
                              name: "SmartPump Pro $indexStr",
                              battery: 3,
                              uuid: uuid,
                              productKey: productKey,
                              devId: devId,
                            ),
                          );
                        }
                        // 立即更新状态为found
                        _searchState = SearchState.found;
                      }
                    });
                    
                    debugPrint('✅ 设备已添加到扫描列表: ${scannedDevice.bluetoothId}, 总数: ${_scannedDevices.length}, _devices: ${_devices.length}, 状态: $_searchState');
                    
                    // 如果状态已更新为found，显示状态消息
                    if ((wasSearching || wasIdle) && _searchState == SearchState.found) {
                      _showStatusMessage();
                    }
                    
                    // 异步更新设备列表详细信息（不阻塞UI显示）
                    _updateDeviceList().then((_) {
                      if (mounted) {
                        debugPrint('✅ 设备列表详细信息已更新，_devices数量: ${_devices.length}');
                      }
                    });
                  }
                } else {
                  debugPrint('⚠️ 设备已存在，跳过: $deviceId');
                }
              }
            } catch (e) {
              debugPrint('❌ 解析设备信息失败: $e');
            }
          }
        },
        onError: (error) {
          debugPrint('❌ 蓝牙扫描错误: $error');

          if (error.toString().contains('MissingPluginException')) {
            debugPrint('⚠️ EventChannel 未注册，1秒后重试...');
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                _setupBleScanListener();
              }
            });
          } else {
            if (mounted) {
              setState(() {
                _searchState = SearchState.idle;
              });
            }
          }
        },
      );
    } catch (e) {
      debugPrint('❌ 设置蓝牙监听器失败: $e');
      if (e.toString().contains('MissingPluginException')) {
        debugPrint('⚠️ EventChannel 未注册，1秒后重试...');
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            _setupBleScanListener();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _bleScanSubscription?.cancel();
    _connectionEventSubscription?.cancel();
    _statusAnimationController.dispose();
    super.dispose();
  }

  void _setupConnectionEventListener() {
    _connectionEventSubscription?.cancel();
    _connectionEventSubscription = null;

    try {
      final stream = connectionEventChannel.receiveBroadcastStream();
      _connectionEventSubscription = stream.listen(
        (event) {
          if (event is String) {
            try {
              final eventData = jsonDecode(event) as Map<String, dynamic>;
              final type = eventData['type'] as String?;

              if (type == 'deviceActivated') {
                final deviceId = eventData['deviceId'] as String?;
                final devId = eventData['devId'] as String?;

                if (deviceId != null && devId != null && devId.isNotEmpty) {
                  _updateDeviceDevId(deviceId, devId);
                }
              }

              if (type == 'networkStatusChanged') {
                debugPrint('🔍 网络状态变化: $eventData');
                final devId = eventData['devId'] as String?;
                final status = eventData['status'] as bool?;

                if (devId != null && status != null) {
                  unawaited(_handleNetworkStatusChanged(devId, status));
                }
              }
            } catch (e) {
              debugPrint('❌ 解析连接事件失败: $e');
            }
          }
        },
        onError: (error) {
          debugPrint('❌ 连接事件流错误: $error');
        },
      );
    } catch (e) {
      debugPrint('❌ 设置连接事件监听器失败: $e');
    }
  }

  Future<void> _updateDeviceDevId(String bluetoothId, String devId) async {
    try {
      // 更新内存中的设备列表
      final device = _devices
          .where((d) => d.bluetoothId == bluetoothId)
          .firstOrNull;
      if (device != null) {
        setState(() {
          device.devId = devId;
        });
      }

      // 更新数据库中的设备记录
      final dbDevice = await _dbService.getDeviceByBluetoothId(bluetoothId);
      if (dbDevice != null) {
        final updatedDevice = dbDevice.copyWith(devId: devId);
        await _dbService.updateDevice(updatedDevice);
        debugPrint('✅ 已更新数据库中的设备 devId: bluetoothId=$bluetoothId, devId=$devId');
      } else {
        debugPrint('⚠️ 数据库中未找到设备: bluetoothId=$bluetoothId');
      }
    } catch (e) {
      debugPrint('❌ 更新设备 devId 失败: $e');
    }
  }

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

  Future<void> _handleNetworkStatusChanged(String devId, bool online) async {
    try {
      final device = await _dbService.getDeviceByDevId(devId);
      if (device == null || !device.isRemembered) {
        return;
      }

      if (online) {
        NetworkStatusRunningPolicy.onOnline(device.bluetoothId);
        debugPrint(
          '🧭 isRunning 更新来源=networkStatusChanged(online): devId=$devId',
        );
        await _updateDeviceRunningStatus(devId, true);
        return;
      }

      if (!NetworkStatusRunningPolicy.shouldApplyRunningFalse(
        dbIsRunning: device.isRunning,
        bluetoothId: device.bluetoothId,
      )) {
        final streak = OfflineStreakTracker.currentStreak(device.bluetoothId);
        debugPrint(
          'networkStatusChanged 离线 $streak/'
          '${OfflineStreakTracker.confirmThreshold}，暂不改 isRunning: '
          'devId=$devId, bluetoothId=${device.bluetoothId}',
        );
        return;
      }

      if (DeviceReconnectPolicy.shouldSuppressRunningFalse(
        devId: devId,
        isOnline: false,
      )) {
        debugPrint(
          'networkStatusChanged 确认离线但 DP105 仍活跃，暂不改 isRunning: devId=$devId',
        );
        return;
      }

      debugPrint(
        '🧭 isRunning 更新来源=networkStatusChanged(确认离线): devId=$devId',
      );
      await _updateDeviceRunningStatus(devId, false);
    } catch (e) {
      debugPrint('❌ 处理 networkStatusChanged 失败: $e');
    }
  }

  Future<void> _updateDeviceRunningStatus(String devId, bool isRunning) async {
    try {
      final device = await _dbService.getDeviceByDevId(devId);

      if (device == null) {
        return;
      }

      if (!device.isRemembered) {
        return;
      }

      final updatedDevice = device.copyWith(isRunning: isRunning);
      await _dbService.updateDevice(updatedDevice);

      if (isRunning && !device.isRunning) {
        _publishDeviceSymbolThrice(device.bluetoothId, device.position);
      }

      if (mounted) {
        setState(() {
          final index = _connectedDevices.indexWhere((d) => d.devId == devId);
          if (index != -1) {
            _connectedDevices[index] = updatedDevice;
          }
        });
        await _updateDeviceList();
      }
    } catch (e) {
      debugPrint('❌ 更新设备运行状态失败: $e');
    }
  }

  void _startSearch() async {
    AppLogger.user('startSearch tapped', null);
    setState(() {
      _searchState = SearchState.searching;
      _scannedDevices.clear();
      _devices.clear();
    });

    final isBluetoothEnabled = await bleChannel.invokeMethod<bool>('checkBluetoothEnabled') ?? false;
        
    if (!isBluetoothEnabled) {
      // 蓝牙未开启，显示提示对话框
      if (mounted) {
        setState(() {
          _searchState = SearchState.idle;
        });
        AppLogger.user('startSearch blocked: bluetooth off', null);
        _showBluetoothDisabledDialog();
      }
      return;
    }

    if (AppConfig.tuyaEnabled) {
      // 先检查蓝牙是否已开启
      try {
        // 蓝牙已开启，开始扫描
        await bleChannel.invokeMethod('startScan');
        AppLogger.user('ble startScan invoked', null);
      } on PlatformException catch (e) {
        debugPrint('❌ 蓝牙扫描启动失败: $e');
        // 如果是蓝牙未开启的错误，显示提示对话框
        if (e.code == 'BLUETOOTH_DISABLED') {
          if (mounted) {
            setState(() {
              _searchState = SearchState.idle;
            });
            _showBluetoothDisabledDialog();
          }
        } else if (e.code == 'ALREADY_SCANNING') {
          // ALREADY_SCANNING 错误应该被忽略，因为原生端会自动处理（停止并重新开始）
          // 保持当前状态，不设置为 idle
          debugPrint('ℹ️ 扫描已在进行中，原生端会自动处理');
        } else {
          if (mounted) {
            setState(() {
              _searchState = SearchState.idle;
            });
          }
        }
      } catch (e) {
        debugPrint('❌ 蓝牙扫描启动失败: $e');
        if (mounted) {
          setState(() {
            _searchState = SearchState.idle;
          });
        }
      }
    } else {
      _scannedDevices.addAll(AppConfig.mockDevices);
      Future.delayed(const Duration(seconds: 2), () async {
        if (mounted) {
          await _updateDeviceList();
          if (mounted) {
            setState(() {
              _searchState = SearchState.found;
            });
            _showStatusMessage();
          }
        }
      });
    }
  }

  void _showBluetoothDisabledDialog() {
    final l10n = AppLocalizations.of(context)!;
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
            l10n.bluetoothDisabled,
            style: ResponsiveText.smallTitle(
              context,
              color: AppColor.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            l10n.bluetoothDisabledMessage,
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
                l10n.cancel,
                style: ResponsiveText.body(
                  context,
                  color: AppColor.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // 打开系统设置
                _openBluetoothSettings();
              },
              style: TextButton.styleFrom(
                padding: ResponsiveText.symmetric(
                  context,
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: Text(
                l10n.openSettings,
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

  Future<void> _openBluetoothSettings() async {
    try {
      await bleChannel.invokeMethod('openBluetoothSettings');
    } catch (e) {
      debugPrint('❌ 打开蓝牙设置失败: $e');
    }
  }

  Future<void> _updateDeviceList() async {
    _devices.clear();

    // 创建 _scannedDevices 的副本以避免并发修改错误
    final scannedDevicesCopy = List<BluetoothDevice>.from(_scannedDevices);

    int index = 1;
    for (final device in scannedDevicesCopy) {
      final deviceInfo = await _dbService.getDeviceByBluetoothId(
        device.bluetoothId,
      );
      
      // 如果设备在数据库中存在但已被删除（isRemembered = false），跳过它
      // 这样可以防止已删除的设备重新出现在可用设备列表中
      // if (deviceInfo != null && !deviceInfo.isRemembered) {
      //   continue;
      // }
      
      String indexStr = index.toString().padLeft(3, '0');
      if (deviceInfo == null) {
        _devices.add(
          BluetoothDevice(
            bluetoothId: device.bluetoothId,
            name: "SmartPump Pro $indexStr",
            battery: device.battery,
            uuid: device.uuid,
            productKey: device.productKey,
            devId: device.bluetoothId,
          ),
        );
      } else {
        _devices.add(
          BluetoothDevice(
            bluetoothId: device.bluetoothId,
            name: "SmartPump Pro $indexStr",
            battery: deviceInfo.battery,
            uuid: device.uuid,
            productKey: device.productKey,
            devId: device.devId,
          ),
        );
      }
      index++;
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: AppConfig.debug
          ? FloatingActionButton(
              onPressed: _showDatabaseContent,
              backgroundColor: AppColor.primaryPurple,
              child: const Icon(Icons.storage, color: Colors.white),
            )
          : null,
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
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 48),
                    Container(
                      width: ResponsiveText.getSize(context, 100),
                      height: ResponsiveText.getSize(context, 100),
                      decoration: BoxDecoration(
                        color: AppColor.primaryPurple,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.bluetooth,
                        color: AppColor.white,
                        size: ResponsiveText.getSize(context, 50),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppLocalizations.of(context)!.breastPumpControl,
                      style: ResponsiveText.title(
                        context,
                        color: AppColor.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppLocalizations.of(
                        context,
                      )!.connectYourWearableBreastPump,
                      style: ResponsiveText.title(
                        context,
                        color: const Color(0xFF6B6B6B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 36),
                    _buildSearchButton(),
                    const SizedBox(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            if (_connectedDevices.isNotEmpty)
                              _buildConnectedDevicesList(),
                            if (_searchState == SearchState.found &&
                                _connectedDevices.length < 2) ...[
                              const SizedBox(height: 24),
                              _buildDevicesList(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_connectedDevices.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildContinueButton(),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
            if (_isStatusMessageVisible) _buildAnimatedStatusMessage(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchButton() {
    if (_searchState == SearchState.searching) {
      return Container(
        width: double.infinity,
        padding: ResponsiveText.symmetric(context, horizontal: 32, vertical: 8),
        decoration: BoxDecoration(
          color: AppColor.primaryPurple,
          borderRadius: BorderRadius.circular(6),
        ),
        constraints: const BoxConstraints(minHeight: 36),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColor.white),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context)!.searching,
              style: ResponsiveText.smallTitle(
                context,
                fontWeight: FontWeight.w500,
                color: AppColor.white,
              ),
            ),
          ],
        ),
      );
    }

    final isMaxConnected = _connectedDevices.length >= 2;
    return ElevatedButton(
      onPressed: (isMaxConnected || _isAnyDeviceReconnecting) ? null : _startSearch,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColor.primaryPurple,
        foregroundColor: AppColor.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        minimumSize: const Size(double.infinity, 36),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth, size: ResponsiveText.getSize(context, 20)),
          const SizedBox(width: 8),
          Text(
            AppLocalizations.of(context)!.searchForDevices,
            style: ResponsiveText.smallTitle(
              context,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesList() {

    final availableDevices = _devices.where((device) {
      return !_connectedDevices.any(
        (connected) => connected.bluetoothId == device.bluetoothId,
      );
    }).toList();

    if (availableDevices.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.availableDevices,
            style: ResponsiveText.title(
              context,
              color: AppColor.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 28),
          ...availableDevices.asMap().entries.map((entry) {
            final index = entry.key;
            final device = entry.value;
            return _buildDeviceItem(
              device,
              index < availableDevices.length - 1,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildConnectedDevicesList() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.pairedDevices,
            style: ResponsiveText.title(
              context,
              color: AppColor.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          ..._connectedDevices.asMap().entries.map((entry) {
            final index = entry.key;
            final device = entry.value;
            return _buildConnectedDeviceItem(
              device,
              index < _connectedDevices.length - 1,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBatteryIcon(int level) {
    IconData batteryIcon;
    Color batteryColor;

    switch (level) {
      case 1:
        batteryIcon = Icons.battery_2_bar;
        batteryColor = Colors.red;
        break;
      case 2:
        batteryIcon = Icons.battery_4_bar;
        batteryColor = Colors.orange;
        break;
      case 3:
        batteryIcon = Icons.battery_full;
        batteryColor = Colors.green;
        break;
      default:
        batteryIcon = Icons.battery_1_bar;
        batteryColor = AppColor.textSecondary;
    }

    return Icon(
      batteryIcon,
      size: ResponsiveText.getSize(context, 24),
      color: batteryColor,
    );
  }

  Widget _buildConnectedDeviceItem(
    ConnectedDevice device,
    bool hasBottomMargin,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final sideLabel = device.position == 'left' ? l10n.left : l10n.right;
    return Container(
      margin: EdgeInsets.only(bottom: hasBottomMargin ? 12 : 0),
      padding: ResponsiveText.symmetric(context, horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: device.isRunning
            ? const Color(0xFFF0FDF4)
            : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        children: [
          device.isRunning
              ? Icon(
                  Icons.check,
                  color: Colors.green,
                  size: ResponsiveText.getSize(context, 24),
                )
              : SizedBox(
                  width: ResponsiveText.getSize(context, 22),
                  height: ResponsiveText.getSize(context, 22),
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        device.name,
                        style: ResponsiveText.smallTitle(
                          context,
                          fontWeight: FontWeight.w500,
                          color: AppColor.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5E6B3), // Light yellow
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        sideLabel,
                        style: ResponsiveText.captionSmall(
                          context,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF8D6E63), // Brown text
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                device.isRunning
                    ? const SizedBox(height: 4)
                    : const SizedBox.shrink(),
                device.isRunning
                    ? Row(
                        children: [
                          _buildBatteryIcon(device.battery),
                          const SizedBox(width: 4),
                          Text(
                            '${device.battery}/3',
                            style: ResponsiveText.body(
                              context,
                              color: AppColor.textSecondary,
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ],
            ),
          ),
          SizedBox(width: ResponsiveText.getSize(context, 12)),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
              Symbols.delete,
              weight: 500,
              color: Colors.red,
              size: ResponsiveText.getSize(context, 22),
            ),
            onPressed: () => _disconnectDevice(device.bluetoothId),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          AppLogger.user('navigate to ControlPage', {
            'pairedCount': _connectedDevices.length,
          });
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const ControlPage(),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColor.primaryPurple,
          foregroundColor: AppColor.white,
          padding: ResponsiveText.symmetric(
            context,
            horizontal: 10,
            vertical: 10,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          minimumSize: const Size(double.infinity, 30),
        ),
        child: Text(
          AppLocalizations.of(context)!.continueToControl,
          style: ResponsiveText.smallTitle(
            context,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceItem(BluetoothDevice device, bool hasBottomMargin) {
    return InkWell(
      onTap: () => _showPumpSideDialog(device),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        margin: EdgeInsets.only(bottom: hasBottomMargin ? 12 : 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: AppColor.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.grey.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 0),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.bluetooth,
              color: AppColor.textPrimary,
              size: ResponsiveText.getSize(context, 24),
            ),
            const SizedBox(width: 12),
            Text(
              device.name,
              style: ResponsiveText.body(
                context,
                fontWeight: FontWeight.w500,
                color: AppColor.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPumpSideDialog(BluetoothDevice device) {
    final occupiedPositions = _connectedDevices.map((d) => d.position).toSet();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PumpSideDialog(
          deviceName: device.name,
          occupiedPositions: occupiedPositions,
          onConnect: (String side) async {
            return await _connectDevice(device, side);
          },
        );
      },
    ).then((_) {
      final pending = _devicePendingConnectLowBatteryCheck;
      _devicePendingConnectLowBatteryCheck = null;
      if (pending != null && mounted) {
        _maybeShowConnectLowBatteryDialog(pending);
      }
    });
  }

  Future<void> _maybeShowConnectLowBatteryDialog(ConnectedDevice device) async {
    final batVolt = await BatteryVoltageService.readBatVolt(device.bluetoothId);
    final freshDevice =
        await _dbService.getDeviceByBluetoothId(device.bluetoothId);
    final battery = freshDevice?.battery ?? device.battery;

    final shouldWarn = BatteryAlertLogic.isBatVoltInsufficientForFullSession(
      batVolt,
    ) ||
        (batVolt == null && BatteryAlertLogic.isLowBatteryLevel(battery));

    if (!shouldWarn || !mounted) return;

    await LowBatteryDialog.show(
      context,
      LowBatteryDialogVariant.connectWarning,
    );
  }

  Future<bool> _connectDevice(BluetoothDevice device, String side) async {
    AppLogger.user('connectDevice attempt', {
      'bluetoothId': device.bluetoothId,
      'name': device.name,
      'side': side,
    });
    final position = side == 'Left' ? 'left' : 'right';

    // 检查蓝牙是否已开启
    final isBluetoothEnabled = await bleChannel.invokeMethod<bool>('checkBluetoothEnabled') ?? false;
    
    if (!isBluetoothEnabled) {
      // 蓝牙未开启，显示提示对话框
      if (mounted) {
        _showBluetoothDisabledDialog();
      }
      return false;
    }

    if (_connectedDevices.any((d) => d.bluetoothId == device.bluetoothId)) {
      return false;
    }

    if (_connectedDevices.any((d) => d.position == position)) {
      return false;
    }

    if (_connectedDevices.length >= 2) {
      return false;
    }

    try {
      bool result = false;
      String? returnedDevId;

      if (AppConfig.tuyaEnabled) {
        final sw = Stopwatch()..start();
        final readyHomeId = await TuyaSdkService.ensureHomeReady(
          timeout: const Duration(seconds: 15),
        );
        sw.stop();
        AppLogger.sdk('ensureHomeReady', {
          'ok': readyHomeId != null,
          'elapsedMs': sw.elapsedMilliseconds,
          'homeId': readyHomeId,
        });

        if (readyHomeId == null || readyHomeId.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('初始化中，请稍后重试')),
            );
          }
          return false;
        }

        final dbService = DatabaseService();
        final homeIdSetting = await dbService.getSettingByKey('tuya_home_id');
        final homeId = homeIdSetting?.value;

        final Map<String, dynamic> connectParams = {
          'deviceId': device.bluetoothId,
          'uuid': device.uuid,
          'productKey': device.productKey,
          'timeout': 30,
        };

        final effectiveHomeId = (homeId != null && homeId.isNotEmpty)
            ? homeId
            : readyHomeId;
        connectParams['homeId'] = int.parse(effectiveHomeId);

        final connectionResult = await connectionChannel.invokeMethod(
          'connectDevice',
          connectParams,
        );
        
        // 处理返回结果：可能是bool（旧版本兼容）或Map（新版本包含devId）
        if (connectionResult is bool) {
          result = connectionResult;
          returnedDevId = null;
        } else if (connectionResult is Map) {
          result = connectionResult['success'] as bool? ?? false;
          returnedDevId = connectionResult['devId'] as String?;
        } else {
          result = false;
          returnedDevId = null;
        }
        AppLogger.hardware('connectDevice native result', {
          'bluetoothId': device.bluetoothId,
          'success': result,
          'returnedDevId': returnedDevId,
        });
      } else {
        result = true;
        returnedDevId = null;
      }

      if (result == true) {
        // 优先使用返回的devId，如果没有则从数据库或内存中获取
        String? finalDevId = returnedDevId;
        
        if (finalDevId == null || finalDevId.isEmpty) {
          // 等待一小段时间，确保deviceActivated事件处理完成（更新devId）
          await Future.delayed(const Duration(milliseconds: 300));
          
          // 从数据库重新读取devId，因为_updateDeviceDevId会先更新数据库
          final dbDevice = await _dbService.getDeviceByBluetoothId(device.bluetoothId);
          final latestDevId = dbDevice?.devId;
          
          // 如果数据库中没有devId，再检查内存中的设备对象（事件可能已经更新了内存）
          if (latestDevId == null || latestDevId.isEmpty) {
            final memoryDevice = _devices
                .where((d) => d.bluetoothId == device.bluetoothId)
                .firstOrNull;
            finalDevId = memoryDevice?.devId;
          } else {
            finalDevId = latestDevId;
          }
        }
        
        final newDevice = ConnectedDevice(
          bluetoothId: device.bluetoothId,
          name: device.name,
          battery: device.battery,
          position: position,
          isRunning: true,
          isRemembered: true,
          devId: (finalDevId != null && finalDevId.isNotEmpty) ? finalDevId : null,
        );

        final rememberedDevices = await _dbService.getRememberedDevices();
        final existingRememberedForPosition = rememberedDevices
            .where((d) => d.position == position)
            .toList();

        for (final existing in existingRememberedForPosition) {
          await _dbService.updateDevice(
            existing.copyWith(isRemembered: false, isRunning: false),
          );
        }

        final existingDevice = await _dbService.getDeviceByBluetoothId(
          device.bluetoothId,
        );
        if (existingDevice != null) {
          // 如果newDevice有devId（来自returnedDevId），优先使用它；否则保留数据库中的devId
          final devIdToUse = (newDevice.devId != null && newDevice.devId!.isNotEmpty)
              ? newDevice.devId
              : existingDevice.devId;
          
          await _dbService.updateDevice(
            newDevice.copyWith(
              id: existingDevice.id,
              devId: devIdToUse,
              isRunning: true,
              isRemembered: true,
            ),
          );
        } else {
          await _dbService.insertDevice(newDevice);
        }

        if (AppConfig.tuyaEnabled) {
          _publishDeviceSymbolThrice(device.bluetoothId, position);
        }

        if (mounted) {
          setState(() {
            _connectedDevices.add(newDevice);
          });
        }

        _showConnectionMessage(device.name, side);
        AppLogger.user('connectDevice success', {
          'bluetoothId': device.bluetoothId,
          'devId': newDevice.devId,
          'position': position,
        });

        final savedDevice = await _dbService.getDeviceByBluetoothId(
          device.bluetoothId,
        );
        _devicePendingConnectLowBatteryCheck = savedDevice ?? newDevice;
        if (savedDevice != null) {
          await DeviceListenerService.registerIfRunning(savedDevice);
        }

        return true;
      } else {
        debugPrint('❌ 设备连接失败: ${device.bluetoothId}');
        AppLogger.e('user', 'connectDevice failed', {
          'bluetoothId': device.bluetoothId,
        });
        return false;
      }
    } on PlatformException catch (e) {
      debugPrint('❌ 连接设备出错: ${e.code} - ${e.message}');
      AppLogger.e('user', 'connectDevice PlatformException', {
        'code': e.code,
        'message': e.message,
      });
      return false;
    } catch (e) {
      debugPrint('❌ 连接设备出错: $e');
      AppLogger.e('user', 'connectDevice error', {'error': e.toString()});
      return false;
    }
  }

  Future<void> _disconnectDevice(String bluetoothId) async {
    AppLogger.user('disconnectDevice', {'bluetoothId': bluetoothId});
    final device = await _dbService.getDeviceByBluetoothId(bluetoothId);
    if (device != null) {
      if (device.devId != null &&
          device.devId!.isNotEmpty &&
          AppConfig.tuyaEnabled) {
        try {
          await connectionChannel.invokeMethod('removeDevice', {
            'devId': device.devId,
          });
        } catch (e) {
          debugPrint('❌ 移除设备失败: $e');
        }
      }

      await _dbService.updateDevice(
        device.copyWith(isRemembered: false, isRunning: false),
      );
    }

    setState(() {
      _connectedDevices.removeWhere(
        (device) => device.bluetoothId == bluetoothId,
      );
      _scannedDevices.removeWhere(
        (device) => device.bluetoothId == bluetoothId,
      );
    });

    // 更新设备列表，确保UI反映最新的状态
    await _updateDeviceList();

    _showDeviceRemovedMessage();
  }

  void _showStatusMessageWithAnimation(
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    setState(() {
      _statusMessage = message;
      _isStatusMessageVisible = true;
    });

    _statusAnimationController.forward();

    Future.delayed(duration, () {
      if (mounted) {
        _statusAnimationController.reverse().then((_) {
          if (mounted) {
            setState(() {
              _isStatusMessageVisible = false;
            });
          }
        });
      }
    });
  }

  void _showConnectionMessage(String deviceName, String side) {
    final l10n = AppLocalizations.of(context)!;
    _showStatusMessageWithAnimation(l10n.connectedToDevice(deviceName, side));
  }

  void _showDeviceRemovedMessage() {
    _showStatusMessageWithAnimation(
      AppLocalizations.of(context)!.deviceRemoved,
    );
  }

  void _showStatusMessage() {
    _showStatusMessageWithAnimation('');
  }

  Widget _buildAnimatedStatusMessage() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: SlideTransition(
        position: _statusSlideAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColor.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: _statusMessage.isNotEmpty
                      ? Colors.black
                      : AppColor.textPrimary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _statusMessage.isNotEmpty ? Icons.check : Icons.check,
                  color: AppColor.white,
                  size: 12,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _statusMessage.isNotEmpty
                      ? _statusMessage
                      : AppLocalizations.of(
                          context,
                        )!.foundDevices(_devices.length),
                  style: ResponsiveText.bodySmall(
                    context,
                    color: AppColor.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 临时方法：显示数据库内容
  Future<void> _showDatabaseContent() async {
    if (!mounted) return;
    await DatabaseViewer.show(context);
  }
}
