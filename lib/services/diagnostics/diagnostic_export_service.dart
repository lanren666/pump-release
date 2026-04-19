import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/app_config.dart';
import 'app_logger.dart';

/// Bundles diagnostic log files into a single zip and shares via the system sheet.
/// WeChat rejects multi-file shares unless all are photos; one zip avoids that.
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

    final archive = Archive();
    final metaBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(meta),
    );
    archive.addFile(
      ArchiveFile('export_meta.json', metaBytes.length, metaBytes),
    );

    var addedAny = false;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.log')) continue;
      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
      addedAny = true;
    }

    if (!addedAny) {
      throw StateError('No log files to export');
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw StateError('Failed to build diagnostic zip');
    }

    final tempDir = await getTemporaryDirectory();
    final zipName =
        'pump_diagnostic_${packageInfo.version}+${packageInfo.buildNumber}_${DateTime.now().millisecondsSinceEpoch}.zip';
    final zipFile = File(p.join(tempDir.path, zipName));
    await zipFile.writeAsBytes(zipBytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(zipFile.path, mimeType: 'application/zip')],
        subject:
            'Pump diagnostic logs ${packageInfo.version}+${packageInfo.buildNumber}',
        text:
            'Diagnostic export (version ${packageInfo.version}+${packageInfo.buildNumber})',
      ),
    );
  }
}
