import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'logger.dart';

/// Handles sending custom notifications, SMS, and incoming calls
/// to the Mi Band 6 via the custom Alert Notification Service (0x0020).
class AlertManager {
  final BLELogger _logger = BLELogger();
  BluetoothCharacteristic? _alertChar;

  void setCharacteristic(BluetoothCharacteristic? characteristic) {
    _alertChar = characteristic;
  }

  bool get isReady => _alertChar != null;

  /// Sends an incoming call alert to the band.
  Future<void> sendIncomingCall(String callerName) async {
    await _sendNotification(
      type: 1, // 1 = Call
      appName: 'Call',
      title: callerName,
      message: 'Incoming Call',
    );
  }

  /// Sends an SMS alert to the band.
  Future<void> sendSms(String sender, String message) async {
    await _sendNotification(
      type: 3, // 3 = SMS/Message
      appName: 'SMS',
      title: sender,
      message: message,
    );
  }

  /// Sends an App notification to the band.
  Future<void> sendAppNotification(
    String appName,
    String title,
    String message,
  ) async {
    await _sendNotification(
      type: 0, // 0 = App
      appName: appName,
      title: title,
      message: message,
    );
  }

  Future<void> _sendNotification({
    required int type,
    required String appName,
    required String title,
    required String message,
  }) async {
    if (_alertChar == null) {
      _logger.e('Alert characteristic not available');
      return;
    }

    try {
      final builder = BytesBuilder();

      // Flags (0x1F or 0x5F based on decompiled source)
      // We will use 0x1F (31)
      builder.addByte(0x1F);

      // Notification type flag
      // Decompiled source: if (type != 3) { isCallFlag = 0 } etc.
      // We will map: 1 for calls, 0 for apps, maybe 3 for SMS.
      builder.addByte(type == 3 ? 1 : (type == 1 ? 1 : 0));

      builder.addByte(0x00);

      // 2-byte Notification ID (little endian)
      // Just generate a random ID or use timestamp
      final int notifId = (DateTime.now().millisecondsSinceEpoch ~/ 1000) & 0xFFFF;
      builder.addByte(notifId & 0xFF);
      builder.addByte((notifId >> 8) & 0xFF);

      // Null terminated UTF-8 strings
      final appNameBytes = utf8.encode(appName.isEmpty ? '-' : appName);
      final titleBytes = utf8.encode(title.isEmpty ? '-' : title);
      final msgBytes = utf8.encode(message.isEmpty ? '-' : message);

      builder.add(appNameBytes);
      builder.addByte(0x00);

      builder.add(titleBytes);
      builder.addByte(0x00);

      builder.add(msgBytes);
      builder.addByte(0x00);

      // Timestamp at the end (2 bytes little endian) based on j10
      final int ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000) & 0xFFFF;
      builder.addByte(ts & 0xFF);
      builder.addByte((ts >> 8) & 0xFF);

      final payload = builder.toBytes();
      _logger.d('Sending notification payload: ${payload.length} bytes');

      // FlutterBluePlus automatically chunks writes if MTU is small, but
      // normally Mi Band MTU is around 250 so this should fit.
      await _alertChar!.write(payload, withoutResponse: true);
      _logger.i('Notification sent successfully');
    } catch (e) {
      _logger.e('Failed to send notification: $e');
    }
  }
}
