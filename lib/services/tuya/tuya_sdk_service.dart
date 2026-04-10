import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../database_service.dart';
import '../../models/setting.dart';

// 涂鸦 SDK 相关操作
class TuyaSdkService {
  static const MethodChannel _channel = MethodChannel('com.sporramom/ble_scan');
  static const String _homeIdKey = 'tuya_home_id';
  static const String _homeIdDesc = '涂鸦家庭ID';

  // 检查 SDK 是否已初始化
  static Future<bool> checkSDKInitialized() async {
    try {
      final bool result =
          await _channel.invokeMethod('checkSDKInitialized') ?? false;
      if (result) {
        debugPrint('✅ Tuya SDK 初始化成功');
        return true;
      } else {
        debugPrint('❌ Tuya SDK 初始化失败');
        return false;
      }
    } on PlatformException catch (e) {
      debugPrint('❌ Tuya SDK 初始化检查出错: ${e.message}');
      return false;
    }
  }

  // 匿名登录
  static Future<bool> loginAnonymous() async {
    try {
      final bool result =
          await _channel.invokeMethod('loginAnonymous') ?? false;
      if (result) {
        debugPrint('✅ 匿名登录成功');
        return true;
      } else {
        debugPrint('❌ 匿名登录失败');
        return false;
      }
    } on PlatformException catch (e) {
      debugPrint('❌ 匿名登录出错: ${e.message}');
      return false;
    }
  }

  // 获取家庭列表
  static Future<List<Map<String, dynamic>>> getHomeList() async {
    try {
      final String? result = await _channel.invokeMethod('getHomeList');
      if (result != null) {
        debugPrint('✅ 获取家庭列表成功: $result');
        final List<dynamic> homes = jsonDecode(result);
        debugPrint('找到 ${homes.length} 个家庭');
        return homes.cast<Map<String, dynamic>>();
      } else {
        debugPrint('❌ 获取家庭列表失败: 返回为空');
        return [];
      }
    } on PlatformException catch (e) {
      debugPrint('❌ 获取家庭列表出错: ${e.message}');
      return [];
    }
  }

  // 创建新家庭
  static Future<String?> createHome({
    String homeName = '我的家',
    String geoName = '默认城市',
    List<String> rooms = const ['默认房间'],
  }) async {
    try {
      final String? homeId = await _channel.invokeMethod('addHome', {
        'homeName': homeName,
        'geoName': geoName,
        'rooms': rooms,
        // latitude 和 longitude 会在 iOS 端使用当前位置
      });

      if (homeId != null && homeId.isNotEmpty) {
        debugPrint('✅ 创建家庭成功: homeId=$homeId');
        return homeId;
      } else {
        debugPrint('❌ 创建家庭失败: 返回为空');
        return null;
      }
    } on PlatformException catch (e) {
      debugPrint('❌ 创建家庭出错: ${e.message}');
      return null;
    }
  }

  // 保存家庭ID到数据库
  static Future<void> saveHomeId(String homeId) async {
    try {
      final dbService = DatabaseService();

      // 检查是否已存在
      final existingSetting = await dbService.getSettingByKey(_homeIdKey);
      if (existingSetting != null) {
        // 更新现有设置
        await dbService.updateSetting(existingSetting.copyWith(value: homeId));
        debugPrint('✅ 已更新 homeId: $homeId');
      } else {
        // 创建新设置
        await dbService.insertSetting(
          Setting(key: _homeIdKey, desc: _homeIdDesc, value: homeId),
        );
        debugPrint('✅ 已保存 homeId: $homeId');
      }
    } catch (e) {
      debugPrint('❌ 保存 homeId 失败: $e');
    }
  }

  // 从数据库获取保存的家庭ID
  static Future<String?> getHomeId() async {
    try {
      final dbService = DatabaseService();
      final setting = await dbService.getSettingByKey(_homeIdKey);
      return setting?.value;
    } catch (e) {
      debugPrint('❌ 获取 homeId 失败: $e');
      return null;
    }
  }

  // 初始化 SDK 并设置家庭
  static Future<void> initialize() async {
    // 1. 检查 SDK 初始化
    final isInitialized = await checkSDKInitialized();
    if (!isInitialized) {
      return;
    }

    // 2. 匿名登录
    final loginSuccess = await loginAnonymous();
    if (!loginSuccess) {
      return;
    }

    // 3. 获取家庭列表
    final homes = await getHomeList();

    if (homes.isEmpty) {
      // 如果家庭列表为空，创建新家庭
      debugPrint('🏠 家庭列表为空，创建新家庭...');
      final homeId = await createHome();
      if (homeId != null) {
        await saveHomeId(homeId);
      }
    } else {
      // 如果有家庭，保存第一个家庭的 homeId
      final firstHome = homes[0];
      final homeId = firstHome['homeId']?.toString() ?? '';
      if (homeId.isNotEmpty) {
        await saveHomeId(homeId);
        debugPrint('✅ 已保存 homeId: $homeId');
      }
    }
  }
}
