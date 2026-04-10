import 'package:flutter/services.dart';

const bleChannel = MethodChannel('com.sporramom/ble_scan');
const bleEventChannel = EventChannel('com.sporramom/ble_scan_events');
const connectionChannel = MethodChannel('com.sporramom/ble_connection');
const connectionEventChannel = EventChannel(
  'com.sporramom/ble_connection_events',
);
