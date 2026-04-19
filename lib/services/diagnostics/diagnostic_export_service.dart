import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../config/app_config.dart';
import 'app_logger.dart';

/// Bundles diagnostic log files and shares via the system sheet.
class DiagnosticExportService {
  DiagnosticExportService._();

  static Future<void> shareDiagnosticLogs() async {
    if (!AppConfig.diagnosticsEnabled) {
      throw StateError('Diagnostics export is disabled for this build');
    }
    final dir = AppLogger.directory;
    if (dir == null || !await dir.exists()) {
      throw StateError('Diagnostic directory not available');
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final meta = <String, Object?>{
      'appName': packageInfo.appName,
      'version': packageInfo.version,
      'buildNumber': packageInfo.buildNumber,
      'packageName': packageInfo.packageName,
      'flutter': kDebugMode ? 'debug' : 'release',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
    };

    if (!kIsWeb) {
      meta['os'] = Platform.operatingSystem;
      meta['osVersion'] = Platform.operatingSystemVersion;
      meta['localeName'] = Platform.localeName;
    } else {
      meta['platform'] = 'web';
    }

    final metaFile = File(p.join(dir.path, 'export_meta.json'));
    await metaFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(meta),
    );

    final files = <XFile>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.endsWith('.log') || name == 'export_meta.json') {
        files.add(XFile(entity.path));
      }
    }

    if (files.isEmpty) {
      throw StateError('No log files to export');
    }

    await SharePlus.instance.share(
      ShareParams(
        files: files,
        subject:
            'Pump diagnostic logs ${packageInfo.version}+${packageInfo.buildNumber}',
        text:
            'Diagnostic export (version ${packageInfo.version}+${packageInfo.buildNumber})',
      ),
    );
  }
}
