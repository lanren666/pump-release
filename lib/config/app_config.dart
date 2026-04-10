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
