import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/logger.dart';

class StorageManager {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _authKeyKey = "mi_band_auth_key";
  static const String _lastDeviceKey = "mi_band_last_device_id";
  final BLELogger _logger;

  StorageManager(this._logger);

  // ── Auth key ──────────────────────────────────────────────────────────────

  Future<void> saveAuthKey(String hexKey) async {
    try {
      final bytes = hexToBytes(hexKey);
      await _storage.write(key: _authKeyKey, value: base64Encode(bytes));
      _logger.i("Auth key saved successfully to secure storage as base64.");
    } catch (e) {
      _logger.e("Failed to encode/save key: $e");
    }
  }

  Future<String?> getAuthKey() async {
    return await _storage.read(key: _authKeyKey);
  }

  Future<Uint8List?> getAuthKeyBytes() async {
    final stored = await _storage.read(key: _authKeyKey);
    if (stored != null) {
      try {
        final authKeyBytes = base64Decode(stored);
        _logger.d(
            "Retrieved auth key from storage, length: ${authKeyBytes.length}");
        return authKeyBytes;
      } catch (e) {
        _logger.e("Error decoding base64 key.");
        return null;
      }
    } else {
      _logger.d("No auth key found in storage.");
      return null;
    }
  }

  Future<void> clearAuthKey() async {
    await _storage.delete(key: _authKeyKey);
    _logger.i("Auth key cleared from storage.");
  }

  // ── Last device ───────────────────────────────────────────────────────────

  /// Saves the MAC address of the last successfully connected band.
  Future<void> saveLastDeviceId(String deviceId) async {
    await _storage.write(key: _lastDeviceKey, value: deviceId);
    _logger.d("Last device saved: $deviceId");
  }

  /// Returns the saved device MAC, or null if none saved.
  Future<String?> getLastDeviceId() async {
    return await _storage.read(key: _lastDeviceKey);
  }

  /// Clears the saved device MAC (call on explicit user disconnect).
  Future<void> clearLastDeviceId() async {
    await _storage.delete(key: _lastDeviceKey);
    _logger.d("Last device cleared.");
  }

  /// Converts a 32-character hex string to a 16-byte Uint8List.
  static Uint8List hexToBytes(String hexString) {
    hexString = hexString.replaceAll(" ", "");
    if (hexString.length != 32) {
      throw Exception("Auth key must be 32 hex chars");
    }
    var bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = int.parse(hexString.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
