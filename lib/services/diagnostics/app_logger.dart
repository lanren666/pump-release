import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../config/app_config.dart';

/// Persistent diagnostic logging with size caps. Mirrors to console in debug builds.
class AppLogger {
  AppLogger._();

  static const String _dirName = 'pump_diagnostics';
  static const String _activeName = 'pump.log';
  static const String _rolledName = 'pump_prev.log';
  static const int _maxActiveBytes = 4 * 1024 * 1024;
  static const int _maxTotalBytes = 18 * 1024 * 1024;

  static Directory? _dir;
  static final List<String> _queue = [];
  static Future<void>? _writeChain;
  static bool _ready = false;

  static Future<void> ensureInitialized() async {
    if (!AppConfig.diagnosticsEnabled) return;
    if (_ready) return;
    final base = await getApplicationSupportDirectory();
    _dir = Directory(p.join(base.path, _dirName));
    await _dir!.create(recursive: true);
    await _pruneByTotalSize();
    _ready = true;
    _appendLine(_formatLine('sys', 'INFO', 'logger started', null));
    await (_writeChain ?? Future.value());
  }

  static void user(String message, [Map<String, Object?>? data]) {
    _log('user', 'INFO', message, data);
  }

  static void hardware(String message, [Map<String, Object?>? data]) {
    _log('hw', 'INFO', message, data);
  }

  static void sdk(String message, [Map<String, Object?>? data]) {
    _log('sdk', 'INFO', message, data);
  }

  static void w(String category, String message, [Map<String, Object?>? data]) {
    _log(category, 'WARN', message, data);
  }

  static void e(String category, String message, [Map<String, Object?>? data]) {
    _log(category, 'ERROR', message, data);
  }

  static void recordError(
    Object error,
    StackTrace stack, {
    String source = 'app',
  }) {
    if (!_ready) {
      if (kDebugMode) {
        debugPrint(
          '[diag] $source: $error\n${stack.toString().split('\n').take(8).join('\n')}',
        );
      }
      return;
    }
    final msg =
        '$source: $error\n${stack.toString().split('\n').take(12).join('\n')}';
    _log('sys', 'ERROR', msg, {'source': source});
  }

  static void recordFlutterError(FlutterErrorDetails details) {
    if (!_ready) {
      if (kDebugMode) {
        debugPrint('[diag] FlutterError: ${details.exceptionAsString()}');
      }
      return;
    }
    final buffer = StringBuffer()
      ..writeln(details.exceptionAsString())
      ..writeln(details.stack?.toString().split('\n').take(15).join('\n'));
    _log('sys', 'ERROR', 'FlutterError: $buffer', {
      'library': details.library ?? '',
    });
  }

  static void _log(
    String category,
    String level,
    String message,
    Map<String, Object?>? data,
  ) {
    if (!AppConfig.diagnosticsEnabled) return;
    final line = _formatLine(category, level, message, data);
    _appendLine(line);
    if (kDebugMode) {
      debugPrint('[diag] $line');
    }
  }

  static String _formatLine(
    String category,
    String level,
    String message,
    Map<String, Object?>? data,
  ) {
    final ts = DateTime.now().toUtc().toIso8601String();
    if (data == null || data.isEmpty) {
      return '$ts [$level] [$category] $message';
    }
    return '$ts [$level] [$category] $message ${_safeJson(data)}';
  }

  static String _safeJson(Map<String, Object?> data) {
    try {
      return jsonEncode(data);
    } catch (_) {
      return '{"error":"json_encode_failed"}';
    }
  }

  static void _appendLine(String line) {
    _queue.add(line);
    _writeChain ??= _drainQueue();
  }

  static Future<void> _drainQueue() async {
    try {
      while (_queue.isNotEmpty) {
        if (!_ready || _dir == null) {
          _queue.clear();
          return;
        }
        final line = _queue.removeAt(0);
        final file = File(p.join(_dir!.path, _activeName));
        await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
        final len = await file.length();
        if (len > _maxActiveBytes) {
          await _rollFiles();
        }
        await _pruneByTotalSize();
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[diag] write failed: $e $st');
      }
    } finally {
      _writeChain = null;
      if (_queue.isNotEmpty) {
        _writeChain = _drainQueue();
      }
    }
  }

  static Future<void> _rollFiles() async {
    final active = File(p.join(_dir!.path, _activeName));
    final prev = File(p.join(_dir!.path, _rolledName));
    if (await prev.exists()) {
      await prev.delete();
    }
    if (await active.exists()) {
      await active.rename(prev.path);
    }
  }

  static Future<void> _pruneByTotalSize() async {
    if (_dir == null || !await _dir!.exists()) return;
    var total = 0;
    final files = <File>[];
    await for (final ent in _dir!.list()) {
      if (ent is File && ent.path.endsWith('.log')) {
        final len = await ent.length();
        total += len;
        files.add(ent);
      }
    }
    if (total <= _maxTotalBytes) return;
    files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    for (final f in files) {
      if (total <= _maxTotalBytes) break;
      final len = await f.length();
      await f.delete();
      total -= len;
    }
  }

  /// Log files directory for export (null when diagnostics off or not initialized).
  static Directory? get directory =>
      AppConfig.diagnosticsEnabled ? _dir : null;

  static bool get isReady => AppConfig.diagnosticsEnabled && _ready;
}
