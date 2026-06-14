import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pump/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('device status reconnect i18n', () {
    testWidgets('English strings for status card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context)!;
              expect(l10n.deviceOff, 'Off');
              expect(l10n.deviceConnected, 'Connected');
              expect(l10n.tapToReconnect, 'Tap to reconnect');
              expect(l10n.reconnectFailed, 'Reconnect failed. Please try again.');
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('Chinese strings for status card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context)!;
              expect(l10n.deviceOff, '关闭');
              expect(l10n.deviceConnected, '已连接');
              expect(l10n.tapToReconnect, '点击重新连接');
              expect(l10n.reconnectFailed, '重连失败，请重试');
              return const SizedBox();
            },
          ),
        ),
      );
    });
  });

  group('reconnect method channel contract', () {
    const channel = MethodChannel('com.sporramom/ble_connection');
    const bluetoothId = 'test-bluetooth-uuid';

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        switch (call.method) {
          case 'isDeviceOnline':
            return false;
          case 'connectBleDevices':
            final deviceIds =
                (call.arguments as Map)['deviceIds'] as List<dynamic>;
            expect(deviceIds, [bluetoothId]);
            return {bluetoothId: true};
          case 'registerDeviceListener':
            expect(
              (call.arguments as Map)['deviceId'],
              bluetoothId,
            );
            return null;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('manual reconnect flow calls expected native methods', () async {
      final isOnline = await channel.invokeMethod<bool>('isDeviceOnline', {
        'deviceId': bluetoothId,
      });
      expect(isOnline, isFalse);

      final results = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'connectBleDevices',
        {'deviceIds': [bluetoothId]},
      );
      expect(results?[bluetoothId], isTrue);

      await channel.invokeMethod<void>('registerDeviceListener', {
        'deviceId': bluetoothId,
      });
    });
  });
}
