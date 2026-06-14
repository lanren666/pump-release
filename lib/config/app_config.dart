import 'package:flutter/material.dart';
import '../models/bluetooth_device.dart';

/// 应用全局配置
/// 修改这里的值来控制应用功能
class AppConfig {
  /// 是否启用涂鸦功能
  /// true: 启用涂鸦SDK功能
  /// false: 禁用涂鸦SDK功能（使用 Mock 设备 mockDevices）
  static const bool tuyaEnabled = true;

  /// 开发环境指定语言（仅开发环境生效）
  /// null: 使用系统语言
  /// Locale('zh', 'CN'): 强制使用简体中文
  /// Locale('en', 'US'): 强制使用英文
  /// 生产环境请设置为 null
  static const Locale? debugLocale = null;

  /// 是否启用调试模式
  /// true: 启用调试功能（如数据库查看器浮动按钮）
  /// false: 禁用调试功能
  static const bool debug = false;

  /// Internal / beta only: file diagnostic logs + export button in System Settings.
  /// Enable at build time (not editable at runtime):
  /// `flutter build apk --dart-define=INTERNAL_DIAGNOSTICS=true`
  /// Default false: no log files, no export UI, no extra I/O.
  static const bool diagnosticsEnabled = bool.fromEnvironment(
    'INTERNAL_DIAGNOSTICS',
    defaultValue: false,
  );

  /// Bat_Volt max from firmware (0x1A4 = 420).
  static const int batVoltMax = 0x1A4;

  /// Placeholder: Bat_Volt below this → less than ~20 min full session.
  /// Tune when firmware voltage curve is confirmed.
  static const int batVoltLowSessionThreshold = 120;

  /// China mainland app ICP filing number (App 备案号). Shown in-app per MIIT rules.
  static const String icpFilingNumber = '粤ICP备2026075101号-1A';

  /// MIIT integrated filing query portal.
  static const String icpFilingQueryUrl = 'https://beian.miit.gov.cn/';

  /// Mock设备列表（用于测试，当tuyaEnabled为false时使用）
  static final List<BluetoothDevice> mockDevices = [
    BluetoothDevice(
      bluetoothId: '12345678901',
      name: 'SmartPump Pro 001',
      battery: 3,
      uuid: '12345678901',
      productKey: '1234567890',
    ),
    BluetoothDevice(
      bluetoothId: '12345678902',
      name: 'SmartPump Pro 002',
      battery: 3,
      uuid: '12345678902',
      productKey: '1234567890',
    ),
    BluetoothDevice(
      bluetoothId: '12345678903',
      name: 'SmartPump Pro 003',
      battery: 3,
      uuid: '12345678903',
      productKey: '1234567890',
    ),
    BluetoothDevice(
      bluetoothId: '12345678904',
      name: 'SmartPump Pro 004',
      battery: 3,
      uuid: '12345678904',
      productKey: '1234567890',
    ),
  ];
}
