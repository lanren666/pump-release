import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_color.dart';
import '../config/responsive_text.dart';
import '../services/tuya/dp_constants.dart';
import '../models/connected_device.dart';
import '../services/database_service.dart';
import '../config/app_config.dart';
import '../services/tuya/ble_dp_service.dart';
import '../l10n/app_localizations.dart';

class DeviceSettingsPage extends StatefulWidget {
  const DeviceSettingsPage({super.key});

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  final DatabaseService _dbService = DatabaseService();
  List<ConnectedDevice> _rememberedDevices = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  final Map<String, bool> _editingStates = {};
  final Map<String, TextEditingController> _textControllers = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    for (var controller in _textControllers.values) {
      controller.dispose();
    }
    _textControllers.clear();
    super.dispose();
  }

  Future<void> _loadData() async {
    final devices = await _dbService.getRememberedDevices();

    if (mounted) {
      setState(() {
        _rememberedDevices = devices;
        _isLoading = false;
      });
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        _refreshDeviceStatus();
      }
    });
  }

  // 从数据库重新加载设备状态，同步后台任务更新的数据
  Future<void> _refreshDeviceStatus() async {
    try {
      final devices = await _dbService.getRememberedDevices();
      if (!mounted) return;

      setState(() {
        _rememberedDevices = devices;
      });
    } catch (e) {
      debugPrint('❌ 刷新设备状态失败: $e');
    }
  }

  Future<void> _saveSettings() async {
    // 暂时没有需要保存的设置
  }

  Future<void> _switchDeviceSide(ConnectedDevice device) async {
    final newPosition = device.position == 'left' ? 'right' : 'left';

    // 检查目标位置是否被占用
    final otherDevice = _rememberedDevices
        .where(
          (d) =>
              d.bluetoothId != device.bluetoothId && d.position == newPosition,
        )
        .firstOrNull;

    if (otherDevice != null) {
      // 如果被占用，先交换位置
      await _dbService.updateDevice(
        otherDevice.copyWith(position: device.position),
      );
      if (AppConfig.tuyaEnabled) {
        BleDpService.publishDp(
          otherDevice.bluetoothId,
          DpConstants.deviceSymbol,
          device.position,
        );
      }
    }

    await _dbService.updateDevice(device.copyWith(position: newPosition));
    if (AppConfig.tuyaEnabled) {
      BleDpService.publishDp(
        device.bluetoothId,
        DpConstants.deviceSymbol,
        newPosition,
      );
    }
    await _loadData();
  }

  void _startEditingDevice(ConnectedDevice device) {
    setState(() {
      _editingStates[device.bluetoothId] = true;
      if (!_textControllers.containsKey(device.bluetoothId)) {
        _textControllers[device.bluetoothId] = TextEditingController(
          text: device.name,
        );
      } else {
        _textControllers[device.bluetoothId]!.text = device.name;
      }
    });
  }

  void _cancelEditingDevice(String bluetoothId) {
    setState(() {
      _editingStates[bluetoothId] = false;
    });
  }

  Future<void> _saveDeviceName(ConnectedDevice device) async {
    final controller = _textControllers[device.bluetoothId];
    if (controller == null) return;

    final newName = controller.text.trim();
    if (newName.isEmpty) {
      // 空名称就取消编辑
      _cancelEditingDevice(device.bluetoothId);
      return;
    }

    await _dbService.updateDevice(device.copyWith(name: newName));
    await _loadData();

    setState(() {
      _editingStates[device.bluetoothId] = false;
    });
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
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColor.gradientStart, AppColor.gradientEnd],
                  ),
                ),
                child: SingleChildScrollView(
                  padding: ResponsiveText.symmetric(
                    context,
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDeviceSideSettings(),
                      SizedBox(height: ResponsiveText.getSize(context, 16)),
                      _buildSaveButton(),
                      SizedBox(height: ResponsiveText.getSize(context, 24)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        left: ResponsiveText.getSize(context, 8),
        right: ResponsiveText.getSize(context, 20),
        top: statusBarHeight + ResponsiveText.getSize(context, 8),
        bottom: ResponsiveText.getSize(context, 16),
      ),
      decoration: const BoxDecoration(color: AppColor.primaryPurple),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColor.white),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          Text(
            AppLocalizations.of(context)!.deviceSettings,
            style: ResponsiveText.title(
              context,
              fontWeight: FontWeight.bold,
              color: AppColor.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSideSettings() {
    if (_isLoading) {
      return Container(
        padding: ResponsiveText.padding(context, all: 20),
        decoration: BoxDecoration(
          color: AppColor.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      padding: ResponsiveText.symmetric(context, vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.deviceSideSettings,
            style: ResponsiveText.body(
              context,
              fontWeight: FontWeight.bold,
              color: AppColor.textPrimary,
            ),
          ),
          SizedBox(height: ResponsiveText.getSize(context, 36)),
          ..._rememberedDevices.asMap().entries.map((entry) {
            final index = entry.key;
            final device = entry.value;
            final l10n = AppLocalizations.of(context)!;
            final currentSide = device.position == 'left'
                ? l10n.left
                : l10n.right;
            final switchText = device.position == 'left'
                ? l10n.switchToRightSide
                : l10n.switchToLeftSide;
            return Column(
              children: [
                _buildDeviceCard(
                  device: device,
                  currentSide: currentSide,
                  onSwitchSide: () => _switchDeviceSide(device),
                  switchButtonText: switchText,
                ),
                if (index < _rememberedDevices.length - 1)
                  SizedBox(height: ResponsiveText.getSize(context, 12)),
              ],
            );
          }),
          SizedBox(height: ResponsiveText.getSize(context, 36)),
          Text(
            AppLocalizations.of(context)!.deviceSideSettingsHint,
            style: ResponsiveText.bodySmall(
              context,
              color: AppColor.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard({
    required ConnectedDevice device,
    required String currentSide,
    required VoidCallback onSwitchSide,
    required String switchButtonText,
  }) {
    final isEditing = _editingStates[device.bluetoothId] ?? false;
    final controller = _textControllers[device.bluetoothId];

    return Container(
      padding: ResponsiveText.padding(
        context,
        top: 14,
        left: 14,
        right: 14,
        bottom: 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF7E4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 1),
      ),
      child: isEditing
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: ResponsiveText.body(
                      context,
                      fontWeight: FontWeight.w500,
                      color: AppColor.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                        borderSide: BorderSide(
                          color: AppColor.primaryPurple,
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                        borderSide: BorderSide(
                          color: AppColor.primaryPurple,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                        borderSide: BorderSide(
                          color: AppColor.primaryPurple,
                          width: 2,
                        ),
                      ),
                    ),
                    autofocus: true,
                    onSubmitted: (_) => _saveDeviceName(device),
                  ),
                ),
                SizedBox(width: ResponsiveText.getSize(context, 8)),
                GestureDetector(
                  onTap: () => _saveDeviceName(device),
                  child: Icon(
                    Icons.check,
                    size: ResponsiveText.getSize(context, 24),
                    color: Colors.green,
                  ),
                ),
                SizedBox(width: ResponsiveText.getSize(context, 10)),
                GestureDetector(
                  onTap: () => _cancelEditingDevice(device.bluetoothId),
                  child: Icon(
                    Icons.close,
                    size: ResponsiveText.getSize(context, 24),
                    color: Colors.red,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                device.name,
                                style: ResponsiveText.body(
                                  context,
                                  fontWeight: FontWeight.bold,
                                  color: AppColor.textPrimary,
                                ),
                              ),
                              SizedBox(
                                width: ResponsiveText.getSize(context, 6),
                              ),
                              GestureDetector(
                                onTap: () => _startEditingDevice(device),
                                child: Icon(
                                  Icons.edit,
                                  size: ResponsiveText.getSize(context, 16),
                                  color: AppColor.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: ResponsiveText.getSize(context, 2)),
                          Text(
                            'ID: ${device.devId}',
                            style: ResponsiveText.bodySmall(
                              context,
                              color: AppColor.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                AppLocalizations.of(context)!.battery,
                                style: ResponsiveText.bodySmall(
                                  context,
                                  color: AppColor.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              _buildBatteryIcon(device.battery),
                              SizedBox(
                                width: ResponsiveText.getSize(context, 4),
                              ),
                              Text(
                                '${device.battery}/3',
                                style: ResponsiveText.bodySmall(
                                  context,
                                  color: AppColor.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: ResponsiveText.symmetric(
                        context,
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColor.primaryPurple,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        currentSide,
                        style: ResponsiveText.caption(
                          context,
                          fontWeight: FontWeight.w500,
                          color: AppColor.white,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveText.getSize(context, 12)),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onSwitchSide,
                    icon: Icon(
                      Icons.cached,
                      size: ResponsiveText.getSize(context, 24),
                    ),
                    label: Text(
                      switchButtonText,
                      style: ResponsiveText.body(
                        context,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColor.white,
                      foregroundColor: AppColor.textPrimary,
                      padding: ResponsiveText.symmetric(context, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: BorderSide(
                          color: Colors.grey.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      elevation: 0,
                      minimumSize: Size(0, 20),
                    ),
                  ),
                ),
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

    return Icon(batteryIcon, size: 16, color: batteryColor);
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () async {
          await _saveSettings();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.settingsSaved),
              ),
            );
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColor.primaryPurple,
          foregroundColor: AppColor.white,
          padding: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: Text(
          AppLocalizations.of(context)!.saveSettings,
          style: ResponsiveText.smallTitle(
            context,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
