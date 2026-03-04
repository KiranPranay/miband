import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'logger.dart';
import 'encryption.dart';
import 'foreground_task_handler.dart';
import '../storage/secure_storage.dart';
import 'dart:typed_data';
import 'band_metrics.dart';

enum AuthState { notAuthenticated, authenticating, authenticated, failed }

enum _AuthPhase { idle, waitingForChallenge, waitingForResult }

class BLEManager extends ChangeNotifier {
  final BLELogger _logger;
  final StorageManager _storage;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _authChar;
  BluetoothCharacteristic? _stepsChar;

  StreamSubscription<BluetoothConnectionState>? _connSubscription;
  StreamSubscription<List<int>>? _charSubscription;
  StreamSubscription<List<int>>? _stepsSubscription;
  Timer? _authTimeoutTimer;
  Timer? _reconnectTimer;

  bool _isReconnecting = false;
  bool _userDisconnected = false;

  BandMetrics _metrics = const BandMetrics();
  int? _batteryLevel;

  bool get isConnected => _device != null && _device!.isConnected;
  bool _isAuthenticating = false;
  AuthState _authState = AuthState.notAuthenticated;
  _AuthPhase _authPhase = _AuthPhase.idle;

  BLEManager(this._logger, this._storage);

  BluetoothDevice? get device => _device;
  AuthState get authState => _authState;
  bool get isAuthenticating => _isAuthenticating;
  bool get isReconnecting => _isReconnecting;
  BandMetrics get metrics => _metrics;
  int? get batteryLevel => _batteryLevel;

  // ---------------------------------------------------------------------------
  // Foreground Service helpers
  // ---------------------------------------------------------------------------

  static void _initForegroundTaskConfig() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'mi_band_ble',
        channelName: 'Mi Band Connection',
        channelDescription: 'Keeps your Mi Band connected in the background.',
        onlyAlertOnce: true,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(10000),
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );
  }

  Future<void> _startForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) return;
    _initForegroundTaskConfig();
    await FlutterForegroundTask.startService(
      serviceId: 1001,
      notificationTitle: 'Mi Band',
      notificationText: 'Connected — keeping band alive',
      callback: startCallback,
    );
  }

  Future<void> _stopForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  Future<void> _updateForegroundNotification(String text) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Mi Band',
        notificationText: text,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Auto-connect on app startup
  // ---------------------------------------------------------------------------

  /// Call this once at app startup. Reads the saved device MAC and connects
  /// automatically — no user action needed.
  Future<void> tryAutoConnect() async {
    final savedId = await _storage.getLastDeviceId();
    if (savedId == null || savedId.isEmpty) {
      _logger.d("No saved device ID — skipping auto-connect.");
      return;
    }
    _logger.i("Auto-connect: found saved device $savedId. Connecting...");
    final device = BluetoothDevice.fromId(savedId);
    await connect(device);
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  Future<void> connect(BluetoothDevice target) async {
    _userDisconnected = false;
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
    _stepsChar = null;
    _charSubscription?.cancel();
    _stepsSubscription?.cancel();
    _metrics = const BandMetrics();
    _batteryLevel = null;
    _logger.e("Device disconnected.");

    _stopForegroundService();

    if (!_userDisconnected && _device != null) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _isReconnecting = true;
    notifyListeners();
    _logger.i("Will attempt reconnect in 3 s...");
    _reconnectTimer = Timer(const Duration(seconds: 3), () async {
      if (_userDisconnected || _device == null) {
        _isReconnecting = false;
        notifyListeners();
        return;
      }
      _logger.i("Reconnecting to ${_device!.remoteId}...");
      try {
        await _device!.connect(autoConnect: false);
      } catch (e) {
        _logger.e("Reconnect error: $e — retrying in 5 s");
        _reconnectTimer = Timer(const Duration(seconds: 5), _scheduleReconnect);
      }
    });
  }

  Future<void> _handleConnected() async {
    _isReconnecting = false;
    _logger.i("Connected successfully.");
    if (_device == null) return;

    // Save MAC so we can auto-connect on next app launch
    await _storage.saveLastDeviceId(_device!.remoteId.str);

    // Start foreground service to keep process alive in background
    await _startForegroundService();

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

    _logger.i("Found FEC1 characteristic. Starting auth handshake...");
    await _startAuthHandshake();
  }

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

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
        if (value.isNotEmpty) _handleAuthResponse(value);
      });

      await Future.delayed(const Duration(milliseconds: 400));

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

      _authTimeoutTimer?.cancel();
      _authTimeoutTimer = Timer(const Duration(seconds: 20), () {
        _logger.e("Auth timeout");
        _isAuthenticating = false;
        _authState = AuthState.failed;
        notifyListeners();
      });

      _authPhase = _AuthPhase.waitingForChallenge;
      _logger
          .i("Auth Step 1: Sending [0x01, 0x00] + auth key (18 bytes total)");
      await safeWrite([0x01, 0x00, ...authKeyBytes]);
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
      _logger.i("Step 1 OK: sending challenge request [0x02, 0x00]...");
      await safeWrite([0x02, 0x00]);
    } else if (response.length >= 3 &&
        response[0] == 0x10 &&
        response[1] == 0x01 &&
        response[2] == 0x04) {
      _authTimeoutTimer?.cancel();
      _logger.e("Step 1 FAILED: Band rejected auth key");
      _failAuth();
    } else if (response.length >= 3 &&
        response[0] == 0x10 &&
        response[1] == 0x02 &&
        response[2] == 0x01) {
      _logger.i("Step 2 OK: Challenge received. Encrypting...");
      if (response.length < 19) {
        _logger.e("Not enough challenge bytes: ${response.length}");
        _failAuth();
        return;
      }
      await _encryptAndSendStep3(response.sublist(3, 19));
    } else if (response.length >= 3 &&
        response[0] == 0x10 &&
        response[1] == 0x03 &&
        response[2] == 0x01) {
      _authTimeoutTimer?.cancel();
      _logger.i("Authentication SUCCESS! (standard V2)");
      _isAuthenticating = false;
      _authState = AuthState.authenticated;
      notifyListeners();
      _onAuthSuccess();
    } else if (response.length >= 3 &&
        response[0] == 0x10 &&
        response[1] == 0x03 &&
        response[2] == 0x04) {
      _authTimeoutTimer?.cancel();
      _logger.e("Step 3 FAILED: Encryption mismatch — wrong key");
      _failAuth();
    } else if (response.every((b) => b == 0xFF)) {
      _authTimeoutTimer?.cancel();
      _logger.e("Band rejected with 0xFF");
      _failAuth();
    } else if (_authPhase == _AuthPhase.waitingForChallenge &&
        response.length >= 16 &&
        response[0] != 0x10 &&
        !response.every((b) => b == 0xFF)) {
      // Huami V3: raw 32-byte challenge without 0x10 header
      _authPhase = _AuthPhase.waitingForResult;
      _logger.i("V3 challenge received. Encrypting 32 bytes...");
      await _encryptAndSendStep3(response.sublist(0, 32));
    } else if (_authPhase == _AuthPhase.waitingForResult) {
      final hex = response
          .sublist(0, response.length < 12 ? response.length : 12)
          .map((e) => e.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      _logger.d("Post-encrypt response: $hex...");

      if (response.every((b) => b == 0xFF) ||
          (response.length >= 3 &&
              response[0] == 0x10 &&
              response[2] == 0x04)) {
        _authTimeoutTimer?.cancel();
        _logger.e("Auth FAILED (post-encrypt rejection).");
        _failAuth();
      } else {
        _authTimeoutTimer?.cancel();
        _logger.i(
          "Authentication SUCCESS! Band streaming data. "
          "First byte: 0x${response[0].toRadixString(16)}",
        );
        _authPhase = _AuthPhase.idle;
        _isAuthenticating = false;
        _authState = AuthState.authenticated;
        notifyListeners();
        _onAuthSuccess();
      }
    }
  }

  Future<void> _encryptAndSendStep3(List<int> challenge) async {
    Uint8List? keyBytes = await _storage.getAuthKeyBytes();
    if (keyBytes == null || keyBytes.length != 16) {
      _logger.e("Auth key missing or invalid during encryption.");
      _failAuth();
      return;
    }
    try {
      final encrypted = BLEEncryption.encryptAESECB(
        keyBytes,
        Uint8List.fromList(challenge),
      );
      _logger.d(
        "Encrypted (${encrypted.length} bytes): "
        "${encrypted.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}",
      );
      _logger.i("Sending [0x03, 0x00] + encrypted bytes...");
      await safeWrite([0x03, 0x00, ...encrypted]);
    } catch (e) {
      _logger.e("Encryption failed: $e");
      _failAuth();
    }
  }

  void _onAuthSuccess() {
    _updateForegroundNotification('Connected & authenticated');
    _subscribeToSteps();
    _readBattery();
  }

  // ---------------------------------------------------------------------------
  // Real-time steps  (fee0 / 0x0007)
  // ---------------------------------------------------------------------------

  Future<void> _subscribeToSteps() async {
    if (_device == null || !_device!.isConnected) return;

    try {
      final services = await _device!.discoverServices();
      BluetoothService? fee0;
      for (final svc in services) {
        if (svc.uuid.str.toLowerCase().contains('fee0')) {
          fee0 = svc;
          break;
        }
      }
      if (fee0 == null) {
        _logger.e("Steps: fee0 service not found.");
        return;
      }

      for (final char in fee0.characteristics) {
        if (char.uuid.str.toLowerCase().contains('0007')) {
          _stepsChar = char;
          break;
        }
      }
      if (_stepsChar == null) {
        _logger.e("Steps: 0x0007 not found in fee0.");
        return;
      }

      _logger.i("Steps: subscribing to 0x0007...");
      await _stepsChar!.setNotifyValue(true);
      _stepsSubscription?.cancel();
      _stepsSubscription = _stepsChar!.onValueReceived.listen((data) {
        final parsed = BandMetrics.fromStepsPacket(data);
        if (parsed != null) {
          _metrics = parsed;
          _logger.d("Steps: ${parsed.steps}, ${parsed.distanceMeters} m, "
              "${parsed.calories} kcal");
          notifyListeners();
        }
      });

      try {
        final current = await _stepsChar!.read();
        final parsed = BandMetrics.fromStepsPacket(current);
        if (parsed != null) {
          _metrics = parsed;
          notifyListeners();
        }
      } catch (_) {}
    } catch (e) {
      _logger.e("Steps subscription error: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Battery level  (0x180f / 0x2a19)
  // ---------------------------------------------------------------------------

  Future<void> _readBattery() async {
    if (_device == null || !_device!.isConnected) return;

    try {
      final services = await _device!.discoverServices();
      BluetoothCharacteristic? battChar;

      for (final svc in services) {
        if (svc.uuid.str.toLowerCase().contains('180f')) {
          for (final char in svc.characteristics) {
            if (char.uuid.str.toLowerCase().contains('2a19')) {
              battChar = char;
              break;
            }
          }
          break;
        }
      }

      if (battChar == null) {
        _logger.e("Battery: 0x2a19 not found.");
        return;
      }

      final raw = await battChar.read();
      if (raw.isNotEmpty) {
        _batteryLevel = raw[0].clamp(0, 100);
        _logger.i("Battery: $_batteryLevel%");
        notifyListeners();
      }

      try {
        await battChar.setNotifyValue(true);
        battChar.onValueReceived.listen((data) {
          if (data.isNotEmpty) {
            _batteryLevel = data[0].clamp(0, 100);
            _logger.d("Battery update: $_batteryLevel%");
            notifyListeners();
          }
        });
      } catch (_) {}
    } catch (e) {
      _logger.e("Battery read error: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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

  /// Explicit user-initiated disconnect. Clears the saved device so the next
  /// app launch does NOT auto-reconnect.
  Future<void> disconnect() async {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _isReconnecting = false;
    await _storage.clearLastDeviceId();
    await _stopForegroundService();
    _logger.i("Disconnecting (user initiated) — saved device cleared.");
    await _device?.disconnect();
    _device = null;
    notifyListeners();
  }
}
