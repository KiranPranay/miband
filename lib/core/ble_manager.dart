import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'logger.dart';
import 'encryption.dart';
import '../storage/secure_storage.dart';
import 'dart:typed_data';

enum AuthState { notAuthenticated, authenticating, authenticated, failed }

enum _AuthPhase { idle, waitingForChallenge, waitingForResult }

class BLEManager extends ChangeNotifier {
  final BLELogger _logger;
  final StorageManager _storage;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _authChar;

  StreamSubscription<BluetoothConnectionState>? _connSubscription;
  StreamSubscription<List<int>>? _charSubscription;
  Timer? _authTimeoutTimer;

  bool get isConnected => _device != null && _device!.isConnected;
  bool _isAuthenticating = false;
  AuthState _authState = AuthState.notAuthenticated;
  _AuthPhase _authPhase = _AuthPhase.idle;

  BLEManager(this._logger, this._storage);

  BluetoothDevice? get device => _device;
  AuthState get authState => _authState;
  bool get isAuthenticating => _isAuthenticating;

  final Guid fee1ServiceUuid = Guid("0000fee1-0000-3512-2118-0009af100700");
  final Guid fec1CharUuid = Guid("0000fec1-0000-3512-2118-0009af100700");

  Future<void> connect(BluetoothDevice target) async {
    _logger.i("Connecting to ${target.remoteId}...");
    _device = target;
    notifyListeners();

    _connSubscription?.cancel();
    _connSubscription = target.connectionState.listen((state) {
      _logger.i("Connection state: $state");
      if (state == BluetoothConnectionState.disconnected) {
        _handleDisconnect();
      } else if (state == BluetoothConnectionState.connected) {
        _handleConnected();
      }
      notifyListeners();
    });

    try {
      await target.connect(autoConnect: false);
    } catch (e) {
      _logger.e("Connect error: $e");
    }
  }

  void _handleDisconnect() {
    _isAuthenticating = false;
    _authState = AuthState.notAuthenticated;
    _authPhase = _AuthPhase.idle;
    _authChar = null;
    _charSubscription?.cancel();
    _logger.e("Device disconnected.");
  }

  Future<void> _handleConnected() async {
    _logger.i("Connected successfully.");
    if (_device == null) return;

    // Request MTU 247
    try {
      await _device!.requestMtu(247);
      _logger.d("Requested MTU 247");
    } catch (e) {
      _logger.e("MTU request failed: $e");
    }

    _logger.i("Discovering services...");
    List<BluetoothService> services = await _device!.discoverServices();

    BluetoothService? authService;
    for (var svc in services) {
      final uuid = svc.uuid.str.toLowerCase();
      _logger.d("SERVICE UUID: $uuid");
      if (uuid.contains("fee1")) {
        _logger.i("FEE1 FOUND");
        authService = svc;
        break;
      }
    }

    if (authService == null) {
      _logger.e("FEE1 service not found.");
      return;
    }

    for (var char in authService.characteristics) {
      final cuuid = char.uuid.str.toLowerCase();
      _logger.d("CHAR UUID: $cuuid");
      if (cuuid.contains("fec1")) {
        _logger.i("FEC1 FOUND");
        _authChar = char;
        break;
      }
    }

    if (_authChar == null) {
      _logger.e("FEC1 characteristic not found.");
      return;
    }

    _logger.i("Found FEC1 characteristic. Subscribing...");
    await _startAuthHandshake();
  }

  Future<void> _startAuthHandshake() async {
    if (_isAuthenticating) return;
    if (_authChar == null || !_device!.isConnected) return;

    _isAuthenticating = true;
    _authState = AuthState.authenticating;
    notifyListeners();

    try {
      await _authChar!.setNotifyValue(true);
      _logger.d("Notifications enabled for FEC1.");

      _charSubscription?.cancel();
      _charSubscription = _authChar!.onValueReceived.listen((value) {
        if (value.isNotEmpty) {
          _handleAuthResponse(value);
        }
      });

      // Wait for stable GATT subscription
      await Future.delayed(const Duration(milliseconds: 400));

      // Load the 16-byte auth key
      Uint8List? authKeyBytes = await _storage.getAuthKeyBytes();
      if (authKeyBytes == null || authKeyBytes.length != 16) {
        _logger.e("Auth key missing or invalid! Expected 16 bytes.");
        _failAuth();
        return;
      }

      final authKeyHex =
          authKeyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
      _logger.d("Auth key (hex): $authKeyHex");
      _logger.d("Auth key length: ${authKeyBytes.length} bytes");

      // STEP 1: Send [0x01, 0x00] + 16-byte key
      // The band must confirm key receipt with [0x10, 0x01, 0x01]
      // before we request the challenge in step 2.
      _logger
          .i("Auth Step 1: Sending [0x01, 0x00] + auth key (18 bytes total)");

      _authTimeoutTimer?.cancel();
      _authTimeoutTimer = Timer(const Duration(seconds: 20), () {
        _logger.e("Auth timeout");
        _isAuthenticating = false;
        _authState = AuthState.failed;
        notifyListeners();
      });

      _authPhase = _AuthPhase.waitingForChallenge;
      final step1Payload = [0x01, 0x00, ...authKeyBytes];
      await safeWrite(step1Payload);
      // Step 2 ([0x02, 0x00]) is triggered in _handleAuthResponse
      // when the band replies [0x10, 0x01, 0x01]
    } catch (e) {
      _logger.e("Auth Handshake Error: $e");
      _isAuthenticating = false;
      _authState = AuthState.failed;
      notifyListeners();
    }
  }

  void _handleAuthResponse(List<int> response) async {
    _logger.d(
      "Received raw bytes: ${response.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}",
    );

    if (response.length >= 3 &&
        response[0] == 0x10 &&
        response[1] == 0x01 &&
        response[2] == 0x01) {
      // STEP 1 SUCCESS: Band accepted our key. Now request the challenge.
      _logger.i(
          "Step 1 OK: Key accepted by band. Sending Step 2: challenge request [0x02, 0x00]...");
      await safeWrite([0x02, 0x00]);
    } else if (response.length >= 3 &&
        response[0] == 0x10 &&
        response[1] == 0x01 &&
        response[2] == 0x04) {
      // STEP 1 FAILED: Band rejected the key
      _authTimeoutTimer?.cancel();
      _logger.e("Step 1 FAILED: Band rejected auth key (0x10, 0x01, 0x04)");
      _failAuth();
    } else if (response.length >= 3 &&
        response[0] == 0x10 &&
        response[1] == 0x02 &&
        response[2] == 0x01) {
      // STEP 2 SUCCESS: Band sent us a 16-byte random challenge
      _logger.i("Step 2 OK: Challenge received. Encrypting with Auth Key...");
      if (response.length < 19) {
        _logger.e(
          "Not enough challenge bytes. Need 19, got: ${response.length}",
        );
        _failAuth();
        return;
      }
      final challenge = response.sublist(3, 19);

      Uint8List? keyBytes = await _storage.getAuthKeyBytes();
      if (keyBytes == null || keyBytes.length != 16) {
        _logger.e("Auth key missing or invalid! Expected 16 bytes.");
        _failAuth();
        return;
      }

      try {
        final encrypted = BLEEncryption.encryptAESECB(
          keyBytes,
          Uint8List.fromList(challenge),
        );
        _logger.d(
            "Challenge encrypted. Sending Step 3: [0x03, 0x00] + encrypted bytes.");
        await safeWrite([0x03, 0x00, ...encrypted]);
      } catch (e) {
        _logger.e("Encryption failed: $e");
        _failAuth();
      }
    } else if (response.length >= 3 &&
        response[0] == 0x10 &&
        response[1] == 0x03 &&
        response[2] == 0x01) {
      // STEP 3 SUCCESS: Auth complete!
      _authTimeoutTimer?.cancel();
      _logger.i("Authentication SUCCESS!");
      _isAuthenticating = false;
      _authState = AuthState.authenticated;
      notifyListeners();
    } else if (response.length >= 3 &&
        response[0] == 0x10 &&
        response[1] == 0x03 &&
        response[2] == 0x04) {
      // STEP 3 FAILED: Encryption mismatch (wrong key)
      _authTimeoutTimer?.cancel();
      _logger.e(
          "Step 3 FAILED: Encryption mismatch. The key is wrong (0x10, 0x03, 0x04)");
      _failAuth();
    } else if (response.every((b) => b == 0xFF)) {
      _authTimeoutTimer?.cancel();
      _logger.e("Band rejected with 0xFF");
      _failAuth();
    } else if (_authPhase == _AuthPhase.waitingForChallenge &&
        response.length >= 16 &&
        response[0] != 0x10 &&
        !response.every((b) => b == 0xFF)) {
      // Mi Band 6 Huami V3: the band sends 32 bytes of challenge data
      // (two AES-ECB blocks) in a 64-byte padded packet.
      // We must encrypt BOTH 16-byte blocks and respond with all 32 encrypted bytes.
      _authPhase = _AuthPhase.waitingForResult; // prevent re-triggering
      _logger.i(
        "Challenge packet received (0x${response[0].toRadixString(16)}, phase=waitingForChallenge). "
        "Extracting full 32-byte challenge (blocks 0–31) and encrypting...",
      );
      // Take the first 32 bytes — two 16-byte AES-ECB blocks
      final challenge = response.sublist(0, 32);

      Uint8List? keyBytes = await _storage.getAuthKeyBytes();
      if (keyBytes == null || keyBytes.length != 16) {
        _logger.e("Auth key missing or invalid! Expected 16 bytes.");
        _failAuth();
        return;
      }

      try {
        final encrypted = BLEEncryption.encryptAESECB(
          keyBytes,
          Uint8List.fromList(challenge),
        );
        _logger.d(
          "Challenge block1 [0..15]: ${challenge.sublist(0, 16).map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}",
        );
        _logger.d(
          "Challenge block2 [16..31]: ${challenge.sublist(16, 32).map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}",
        );
        _logger.d(
          "Encrypted (32 bytes): ${encrypted.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}",
        );
        _logger.i("Sending [0x03, 0x00] + 32 encrypted bytes (34 total)...");
        await safeWrite([0x03, 0x00, ...encrypted]);
      } catch (e) {
        _logger.e("Encryption failed: $e");
        _failAuth();
      }
    } else if (_authPhase == _AuthPhase.waitingForResult) {
      // Any packet arriving after we sent our encrypted response.
      final hex = response
          .sublist(0, response.length < 12 ? response.length : 12)
          .map((e) => e.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      _logger.d("Post-encrypt response: $hex...");

      if (response.every((b) => b == 0xFF)) {
        // Explicit rejection
        _authTimeoutTimer?.cancel();
        _logger.e("Auth FAILED: band rejected with 0xFF.");
        _failAuth();
      } else if (response.length >= 3 &&
          response[0] == 0x10 &&
          response[2] == 0x04) {
        // Encryption mismatch — wrong key
        _authTimeoutTimer?.cancel();
        _logger.e(
          "Auth FAILED: encryption mismatch "
          "(0x10 ${response[1].toRadixString(16)} 0x04). Check auth key.",
        );
        _failAuth();
      } else {
        // Any other response after our encrypted write means the band
        // accepted our key and is now streaming normal BLE data.
        // The band never disconnects on success — it just starts sending data.
        _authTimeoutTimer?.cancel();
        _logger.i(
          "Authentication SUCCESS! "
          "Band accepted encrypted response and is streaming data. "
          "First data byte: 0x${response[0].toRadixString(16)}",
        );
        _authPhase = _AuthPhase.idle;
        _isAuthenticating = false;
        _authState = AuthState.authenticated;
        notifyListeners();
      }
    }
  }

  Future<void> safeWrite(List<int> value) async {
    if (_device == null || !_device!.isConnected) {
      _logger.e("Tried to write but device disconnected");
      return;
    }
    if (_authChar != null) {
      try {
        await _authChar!.write(value, withoutResponse: false);
      } catch (e) {
        _logger.e("Write error: $e");
      }
    }
  }

  void _failAuth() {
    _isAuthenticating = false;
    _authState = AuthState.failed;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _logger.i("Disconnecting manual...");
    await _device?.disconnect();
  }
}
