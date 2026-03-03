import 'package:flutter/foundation.dart';
import '../storage/secure_storage.dart';
import 'logger.dart';

class AuthManager extends ChangeNotifier {
  final StorageManager _storage;
  final BLELogger _logger;

  String? _currentKey;

  String? get currentKey => _currentKey;
  bool get hasKey => _currentKey != null && _currentKey!.isNotEmpty;

  AuthManager(this._logger, this._storage) {
    loadKey();
  }

  Future<void> loadKey() async {
    _currentKey = await _storage.getAuthKey();
    notifyListeners();
  }

  Future<bool> saveKey(String hexString) async {
    final cleanHex = hexString.replaceAll(' ', '').trim();
    if (cleanHex.length != 32) {
      _logger
          .e("Invalid key length ${cleanHex.length}, expected 32 hex chars.");
      return false;
    }

    try {
      StorageManager.hexToBytes(cleanHex); // Validate format
    } catch (e) {
      _logger.e("Invalid hex encoding in key.");
      return false;
    }

    await _storage.saveAuthKey(cleanHex);
    _currentKey = cleanHex;
    notifyListeners();
    return true;
  }

  Future<void> clearKey() async {
    await _storage.clearAuthKey();
    _currentKey = null;
    notifyListeners();
  }
}
