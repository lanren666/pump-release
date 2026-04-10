import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../models/connected_device.dart';
import '../models/setting.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'pump.db');
    return await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE connected_devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bluetooth_id TEXT UNIQUE NOT NULL,
        dev_id TEXT DEFAULT '',
        name TEXT NOT NULL,
        battery INTEGER DEFAULT 0,
        position TEXT DEFAULT 'left',
        is_running INTEGER DEFAULT 0,
        is_remembered INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT UNIQUE NOT NULL,
        desc TEXT NOT NULL,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      // 重建表，加上 dev_id 字段
      await db.execute('DROP TABLE IF EXISTS connected_devices');
      await db.execute('''
        CREATE TABLE connected_devices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bluetooth_id TEXT UNIQUE NOT NULL,
          dev_id TEXT DEFAULT '',
          name TEXT NOT NULL,
          battery INTEGER DEFAULT 0,
          position TEXT DEFAULT 'left',
          is_running INTEGER DEFAULT 0,
          is_remembered INTEGER DEFAULT 0
        )
      ''');
    } else if (oldVersion < 2) {
      // 旧版本升级逻辑，先留着
      await db.execute('''
        ALTER TABLE connected_devices ADD COLUMN dev_id TEXT
      ''');
    }
  }

  // ConnectedDevice 相关操作

  Future<int> insertDevice(ConnectedDevice device) async {
    final db = await database;
    return await db.insert(
      'connected_devices',
      device.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ConnectedDevice?> getDeviceByBluetoothId(String bluetoothId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'connected_devices',
      where: 'bluetooth_id = ?',
      whereArgs: [bluetoothId],
    );
    if (maps.isEmpty) return null;
    return ConnectedDevice.fromMap(maps.first);
  }

  Future<ConnectedDevice?> getDeviceByDevId(String devId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'connected_devices',
      where: 'dev_id = ?',
      whereArgs: [devId],
    );
    if (maps.isEmpty) return null;
    return ConnectedDevice.fromMap(maps.first);
  }

  Future<int> updateDevice(ConnectedDevice device) async {
    final db = await database;
    final map = device.toMap();
    map.remove('id'); // 移除 id 字段，避免更新主键
    return await db.update(
      'connected_devices',
      map,
      where: 'id = ?',
      whereArgs: [device.id],
    );
  }

  Future<List<ConnectedDevice>> getRememberedDevices() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'connected_devices',
      where: 'is_remembered = ?',
      whereArgs: [1],
    );
    return maps.map((map) => ConnectedDevice.fromMap(map)).toList();
  }

  // Setting 相关操作

  Future<int> insertSetting(Setting setting) async {
    final db = await database;
    return await db.insert(
      'settings',
      setting.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Setting?> getSettingByKey(String key) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isEmpty) return null;
    return Setting.fromMap(maps.first);
  }

  Future<int> updateSetting(Setting setting) async {
    final db = await database;
    return await db.update(
      'settings',
      setting.toMap(),
      where: 'id = ?',
      whereArgs: [setting.id],
    );
  }

  Future<int> updateSettingByKey(String key, String value) async {
    final db = await database;
    return await db.update(
      'settings',
      {'value': value},
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  // 临时查询方法 - 查看所有数据库内容
  Future<Map<String, List<Map<String, dynamic>>>> getAllDatabaseContent() async {
    final db = await database;
    
    // 查询所有表
    final List<Map<String, dynamic>> tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    );
    
    Map<String, List<Map<String, dynamic>>> result = {};
    
    for (var table in tables) {
      final tableName = table['name'] as String;
      final List<Map<String, dynamic>> rows = await db.query(tableName);
      result[tableName] = rows;
    }
    
    return result;
  }

  // 获取数据库路径
  Future<String> getDatabasePath() async {
    String path = join(await getDatabasesPath(), 'pump.db');
    return path;
  }

  // 清空所有数据（临时方法，用于测试）
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('connected_devices');
    await db.delete('settings');
    debugPrint('✅ 已清空所有数据库数据');
  }
}
