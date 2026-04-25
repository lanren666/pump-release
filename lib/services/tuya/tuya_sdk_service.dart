import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../database_service.dart';
import '../diagnostics/app_logger.dart';
import '../../models/setting.dart';

// 涂鸦 SDK 相关操作
class TuyaSdkService {
  static const MethodChannel _channel = MethodChannel('com.sporramom/ble_scan');
  static const String _homeIdKey = 'tuya_home_id';
  static const String _homeIdDesc = '涂鸦家庭ID';

  static Future<void>? _initializeFuture;
  static Completer<String?>? _homeReadyCompleter;
  static Timer? _warmUpRetryTimer;
  static bool _warmUpStarted = false;
  static int _warmUpAttempt = 0;
  static DateTime? _warmUpStartedAt;

  static bool _isUserSessionLoss(PlatformException e) => e.code == 'USER_SESSION_LOSS';

  static Future<T?> _retryOnceWithRelogin<T>(
    String opName,
    Future<T?> Function() action,
  ) async {
    try {
      return await action();
    } on PlatformException catch (e) {
      if (!_isUserSessionLoss(e)) rethrow;

      AppLogger.w(
        'sdk',
        '$opName USER_SESSION_LOSS -> relogin + retry once',
        {'message': e.message},
      );

      final reloginOk = await loginAnonymous();
      if (!reloginOk) {
        AppLogger.e('sdk', '$opName relogin failed', {'message': e.message});
        rethrow;
      }

      return await action();
    }
  }

  /// Fire-and-forget warm-up. It runs initialization in background and retries
  /// a few times on transient failures so that "connect" usually doesn't need to wait.
  static void warmUpHomeReady() {
    if (_warmUpStarted) return;
    _warmUpStarted = true;
    _warmUpStartedAt = DateTime.now();
    _scheduleWarmUpAttempt(immediate: true);
  }

  static void _scheduleWarmUpAttempt({required bool immediate}) {
    _warmUpRetryTimer?.cancel();
    final delay = immediate ? Duration.zero : _nextWarmUpDelay(_warmUpAttempt);
    _warmUpRetryTimer = Timer(delay, () async {
      await _runWarmUpAttempt();
    });
  }

  static Duration _nextWarmUpDelay(int attempt) {
    // 0s, 1s, 2s, 4s, 8s, 10s (cap)
    final seconds = attempt <= 0 ? 0 : (1 << (attempt - 1));
    return Duration(seconds: seconds.clamp(1, 10));
  }

  static Future<void> _runWarmUpAttempt() async {
    try {
      final existing = await getHomeId();
      if (existing != null && existing.isNotEmpty) {
        AppLogger.sdk('warmUpHomeReady alreadyReady', {
          'homeId': existing,
          'attempt': _warmUpAttempt,
          'elapsedMs': _warmUpStartedAt == null
              ? null
              : DateTime.now().difference(_warmUpStartedAt!).inMilliseconds,
        });
        return;
      }

      _warmUpAttempt += 1;
      final sw = Stopwatch()..start();
      AppLogger.sdk('warmUpHomeReady attempt', {'attempt': _warmUpAttempt});

      // Reset per-attempt completion so ensureHomeReady can await a new attempt.
      _homeReadyCompleter ??= Completer<String?>();
      _initializeFuture = _initializeFuture ?? initialize();
      await _initializeFuture;

      sw.stop();
      final homeId = await getHomeId();
      AppLogger.sdk('warmUpHomeReady done', {
        'attempt': _warmUpAttempt,
        'elapsedMs': sw.elapsedMilliseconds,
        'homeReady': homeId != null && homeId.isNotEmpty,
        'homeId': homeId,
      });

      if (homeId == null || homeId.isEmpty) {
        // allow next retry
        _initializeFuture = null;
        _homeReadyCompleter = null;
        if (_warmUpAttempt < 6) {
          _scheduleWarmUpAttempt(immediate: false);
        }
      }
    } catch (e) {
      AppLogger.e('sdk', 'warmUpHomeReady failed', {'error': e.toString()});
      _initializeFuture = null;
      _homeReadyCompleter = null;
      if (_warmUpAttempt < 6) {
        _scheduleWarmUpAttempt(immediate: false);
      }
    }
  }

  /// Ensure Tuya is initialized and a homeId is available.
  /// Returns the homeId when ready, or null on timeout/failure.
  static Future<String?> ensureHomeReady({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      warmUpHomeReady();
      final existing = await getHomeId();
      if (existing != null && existing.isNotEmpty) return existing;

      _homeReadyCompleter ??= Completer<String?>();
      // If last attempt finished unsuccessfully, allow a new attempt.
      _initializeFuture ??= initialize();

      final homeId = await _homeReadyCompleter!.future.timeout(timeout);
      return (homeId != null && homeId.isNotEmpty) ? homeId : null;
    } catch (e) {
      AppLogger.e('sdk', 'ensureHomeReady', {'error': e.toString()});
      _initializeFuture = null; // allow next ensure to retry
      _homeReadyCompleter = null;
      return null;
    }
  }

  // 检查 SDK 是否已初始化
  static Future<bool> checkSDKInitialized() async {
    try {
      final bool result =
          await _channel.invokeMethod('checkSDKInitialized') ?? false;
      AppLogger.sdk('checkSDKInitialized', {'ok': result});
      if (result) {
        debugPrint('✅ Tuya SDK 初始化成功');
        return true;
      } else {
        debugPrint('❌ Tuya SDK 初始化失败');
        return false;
      }
    } on PlatformException catch (e) {
      debugPrint('❌ Tuya SDK 初始化检查出错: ${e.message}');
      AppLogger.e('sdk', 'checkSDKInitialized', {'message': e.message});
      return false;
    } catch (e) {
      debugPrint('❌ Tuya SDK 初始化检查异常: $e');
      AppLogger.e('sdk', 'checkSDKInitialized', {'error': e.toString()});
      return false;
    }
  }

  // 匿名登录
  static Future<bool> loginAnonymous() async {
    try {
      final bool result =
          await _channel.invokeMethod('loginAnonymous') ?? false;
      AppLogger.sdk('loginAnonymous', {'ok': result});
      if (result) {
        debugPrint('✅ 匿名登录成功');
        return true;
      } else {
        debugPrint('❌ 匿名登录失败');
        return false;
      }
    } on PlatformException catch (e) {
      debugPrint('❌ 匿名登录出错: ${e.message}');
      AppLogger.e('sdk', 'loginAnonymous', {'message': e.message});
      return false;
    } catch (e) {
      debugPrint('❌ 匿名登录异常: $e');
      AppLogger.e('sdk', 'loginAnonymous', {'error': e.toString()});
      return false;
    }
  }

  // 获取家庭列表
  static Future<List<Map<String, dynamic>>> getHomeList() async {
    try {
      final String? result = await _retryOnceWithRelogin<String?>(
        'getHomeList',
        () => _channel.invokeMethod('getHomeList'),
      );
      if (result != null) {
        debugPrint('✅ 获取家庭列表成功: $result');
        final List<dynamic> homes = jsonDecode(result);
        debugPrint('找到 ${homes.length} 个家庭');
        AppLogger.sdk('getHomeList', {'homeCount': homes.length});
        return homes.cast<Map<String, dynamic>>();
      } else {
        debugPrint('❌ 获取家庭列表失败: 返回为空');
        AppLogger.w('sdk', 'getHomeList empty', null);
        return [];
      }
    } on PlatformException catch (e) {
      debugPrint('❌ 获取家庭列表出错: ${e.message}');
      AppLogger.e('sdk', 'getHomeList', {'message': e.message});
      return [];
    } catch (e) {
      debugPrint('❌ 获取家庭列表异常: $e');
      AppLogger.e('sdk', 'getHomeList', {'error': e.toString()});
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
      final String? homeId = await _retryOnceWithRelogin<String?>(
        'addHome',
        () => _channel.invokeMethod('addHome', {
              'homeName': homeName,
              'geoName': geoName,
              'rooms': rooms,
              // latitude 和 longitude 会在 iOS 端使用当前位置
            }),
      );

      if (homeId != null && homeId.isNotEmpty) {
        debugPrint('✅ 创建家庭成功: homeId=$homeId');
        AppLogger.sdk('addHome', {'homeId': homeId});
        return homeId;
      } else {
        debugPrint('❌ 创建家庭失败: 返回为空');
        return null;
      }
    } on PlatformException catch (e) {
      debugPrint('❌ 创建家庭出错: ${e.message}');
      AppLogger.e('sdk', 'addHome', {'message': e.message});
      return null;
    } catch (e) {
      debugPrint('❌ 创建家庭异常: $e');
      AppLogger.e('sdk', 'addHome', {'error': e.toString()});
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

      if (_homeReadyCompleter != null && !_homeReadyCompleter!.isCompleted) {
        _homeReadyCompleter!.complete(homeId);
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
    final sw = Stopwatch()..start();
    AppLogger.sdk('initialize start', {});
    // 1. 检查 SDK 初始化
    final isInitialized = await checkSDKInitialized();
    if (!isInitialized) {
      if (_homeReadyCompleter != null && !_homeReadyCompleter!.isCompleted) {
        _homeReadyCompleter!.complete(null);
      }
      sw.stop();
      AppLogger.sdk('initialize end', {
        'ok': false,
        'stage': 'checkSDKInitialized',
        'elapsedMs': sw.elapsedMilliseconds,
      });
      return;
    }

    // 2. 匿名登录
    final loginSuccess = await loginAnonymous();
    if (!loginSuccess) {
      if (_homeReadyCompleter != null && !_homeReadyCompleter!.isCompleted) {
        _homeReadyCompleter!.complete(null);
      }
      sw.stop();
      AppLogger.sdk('initialize end', {
        'ok': false,
        'stage': 'loginAnonymous',
        'elapsedMs': sw.elapsedMilliseconds,
      });
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
      } else {
        if (_homeReadyCompleter != null && !_homeReadyCompleter!.isCompleted) {
          _homeReadyCompleter!.complete(null);
        }
      }
    } else {
      // 如果有家庭，保存第一个家庭的 homeId
      final firstHome = homes[0];
      final homeId = firstHome['homeId']?.toString() ?? '';
      if (homeId.isNotEmpty) {
        await saveHomeId(homeId);
        debugPrint('✅ 已保存 homeId: $homeId');
      } else {
        if (_homeReadyCompleter != null && !_homeReadyCompleter!.isCompleted) {
          _homeReadyCompleter!.complete(null);
        }
      }
    }

    sw.stop();
    final finalHomeId = await getHomeId();
    AppLogger.sdk('initialize end', {
      'ok': finalHomeId != null && finalHomeId.isNotEmpty,
      'elapsedMs': sw.elapsedMilliseconds,
      'homeId': finalHomeId,
    });
  }
}
