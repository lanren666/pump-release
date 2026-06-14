import 'package:flutter/services.dart';

import '../config/ble_channels.dart';

/// Opens http(s) links via the existing native BLE scan MethodChannel.
class ExternalLinkService {
  ExternalLinkService._();

  static Future<bool> openHttpUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }

    try {
      final result = await bleChannel.invokeMethod<bool>(
        'openExternalUrl',
        url,
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
