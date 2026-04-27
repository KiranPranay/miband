import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'logger.dart';
import 'encryption.dart';
import '../storage/secure_storage.dart';
import 'dart:typed_data';
import 'band_metrics.dart';
import 'activity_fetcher.dart';
import '../storage/activity_store.dart';
import 'alert_manager.dart';

// Top-level callback required by flutter_foreground_task
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

enum AuthState { notAuthenticated, authenticating, authenticated, failed }

enum _AuthPhase { idle, waitingForChallenge, waitingForResult }

class BLEManager extends ChangeNotifier {
  final BLELogger _logger;
  final StorageManager _storage;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _authChar;
  BluetoothCharacteristic? _stepsChar;
  BluetoothCharacteristic? _alertChar;

  StreamSubscription<BluetoothConnectionState>? _connSubscription;
  StreamSubscription<List<int>>? _charSubscription;
  StreamSubscription<List<int>>? _stepsSubscription;
  Timer? _authTimeoutTimer;
  Timer? _reconnectTimer;

  bool _isReconnecting = false;
  bool _userDisconnected = false;

  BandMetrics _metrics = const BandMetrics();
  int? _batteryLevel;
  int? _heartRate;
  DateTime? _lastSyncTime;

  ActivityFetcher? _activityFetcher;
  final ActivityStore activityStore = ActivityStore();
  final AlertManager alertManager = AlertManager();
  bool _isFetchingActivity = false;

  bool get isConnected => _device != null && _device!.isConnected;
  bool _isAuthenticating = false;
  AuthState _authState = AuthState.notAuthenticated;
  _AuthPhase _authPhase = _AuthPhase.idle;

  BLEManager(this._logger, this._storage) {
    _loadPersistedData();
    activityStore.load();
  }

  BluetoothDevice? get device => _device;
  AuthState get authState => _authState;
  bool get isAuthenticating => _isAuthenticating;
  bool get isReconnecting => _isReconnecting;
  BandMetrics get metrics => _metrics;
  int? get batteryLevel => _batteryLevel;
  int? get heartRate => _heartRate;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isFetchingActivity => _isFetchingActivity;

  // ---------------------------------------------------------------------------
  // Persistent data
  // ---------------------------------------------------------------------------

  Future<void> _loadPersistedData() async {
    await activityStore.load();
    _lastSyncTime = activityStore.lastActivitySync;
    notifyListeners();
  }

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
    _reconnectTimer?.cancel();
    _isReconnecting = false;
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
    // NOTE: _metrics is intentionally NOT reset — we keep the last known values
    // so the UI can still display historical data while disconnected.
    _batteryLevel = null;
    _heartRate = null;
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
    _reconnectTimer?.cancel();
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
      
      // Discover Custom Alert Service (fee0)
      if (uuid.contains("fee0")) {
        for (var char in svc.characteristics) {
          if (char.uuid.str.toLowerCase() == "00000020-0000-3512-2118-0009af100700") {
            _alertChar = char;
            alertManager.setCharacteristic(_alertChar);
            _logger.i("Found Custom Alert Characteristic (0x0020)");
          }
        }
      }

      if (uuid.contains("fee1")) {
        _logger.i("FEE1 FOUND");
        authService = svc;
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

    // Proactively subscribe to status/init chars before auth success
    await _subscribeToMissingNotifications();

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

  void _onAuthSuccess() async {
    _updateForegroundNotification('Connected & authenticated');

    // Step 1: Sync time (critical for some bands to enable other features)
    await _syncTime();
    await Future.delayed(const Duration(milliseconds: 300));

    // Step 2: Initialize display & settings
    await _setDateDisplay();
    await _setTimeFormat();
    await _setUserInfo();
    await _setFitnessGoal(10000); // 10k steps default

    // Step 3: Subscriptions
    await _subscribeToSteps();
    await _readBattery();
    await _subscribeToHeartRate();

    await Future.delayed(const Duration(seconds: 2));

    // Step 4: Initial fetch
    _fetchActivityData();
  }

  Future<void> _syncTime() async {
    if (_device == null || !_device!.isConnected) return;

    // Find the current time characteristic (0x2A2B in fee0)
    BluetoothCharacteristic? timeChar;
    try {
      final services = await _device!.discoverServices();
      for (final svc in services) {
        if (svc.uuid.str.toLowerCase().contains('fee0')) {
          for (final c in svc.characteristics) {
            if (c.uuid.str.toLowerCase().contains('2a2b')) {
              timeChar = c;
              break;
            }
          }
        }
      }
    } catch (e) {
      _logger.e("TimeSync discovery failed: $e");
    }

    if (timeChar == null) {
      _logger.d("TimeSync: characteristic 0x2A2B not found, skipping.");
      return;
    }

    final now = DateTime.now();
    final dayOfWeek = now.weekday == 7 ? 7 : now.weekday; // matches GB logic

    // Gadgetbridge format for Huami (11 bytes total)
    // year_lo, year_hi, month, day, hour, minute, second, dayOfWeek, fractions256, adjustReason, tzQuarters
    final tzOffsetMinutes = now.timeZoneOffset.inMinutes;
    final tzQuarters = (tzOffsetMinutes / 15).floor();

    final cmd = [
      now.year & 0xFF,
      (now.year >> 8) & 0xFF,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
      dayOfWeek,
      0x00, // fractions256
      0x00, // adjust reason
      tzQuarters & 0xFF,
    ];

    try {
      _logger.i(
          "TimeSync: syncing band clock to $now (0x2A2B) with ${cmd.length} bytes");
      await timeChar.write(cmd, withoutResponse: false);
    } catch (e) {
      _logger.e("TimeSync failed: $e");
    }
  }

  Future<void> _setFitnessGoal(int steps) async {
    if (_device == null || !_device!.isConnected) return;
    try {
      BluetoothCharacteristic? configChar;
      final services = await _device!.discoverServices();
      for (final svc in services) {
        if (svc.uuid.str.toLowerCase().contains('fee0')) {
          for (final c in svc.characteristics) {
            if (c.uuid.str.toLowerCase().contains('0003')) {
              configChar = c;
              break;
            }
          }
        }
      }
      if (configChar != null) {
        _logger.i("Setting fitness goal: $steps steps...");
        // Command: 0x10, 0x0, 0x0, steps_lo, steps_hi, 0, 0
        final cmd = [
          0x10,
          0x00,
          0x00,
          steps & 0xff,
          (steps >> 8) & 0xff,
          0x00,
          0x00
        ];
        await configChar.write(cmd, withoutResponse: true);
      }
    } catch (e) {
      _logger.e("Failed to set fitness goal: $e");
    }
  }

  Future<void> _fetchActivityData() async {
    if (_device == null || !_device!.isConnected) return;

    _isFetchingActivity = true;
    notifyListeners();

    try {
      _activityFetcher = ActivityFetcher(_logger, _device!);
      final ok = await _activityFetcher!.init();
      if (!ok) {
        _logger.e('Activity fetch: init failed');
        return;
      }

      // Fetch last 24h of activity data (or since last sync)
      final since = DateTime.now().subtract(const Duration(days: 1));
      
      _logger.i('Fetching Heart Rate History since $since');
      final hrReadings = await _activityFetcher!.fetchHeartRateHistory(since);
      if (hrReadings.isNotEmpty) {
        activityStore.addHeartRateReadings(hrReadings);
        activityStore.updateHrSync(DateTime.now());
        _logger.i('HR fetch: got ${hrReadings.length} readings');
      } else {
        _logger.i('HR fetch: no new data');
      }

      _logger.i('Fetching SPO2 History since $since');
      final spo2 = await _activityFetcher!.fetchSpo2(since);
      if (spo2.isNotEmpty) {
        activityStore.addSpo2Readings(spo2);
        activityStore.updateSpo2Sync(DateTime.now());
        _logger.i('SPO2 fetch: got ${spo2.length} readings');
      } else {
        _logger.i('SPO2 fetch: no new data');
      }

      _logger.i('Fetching Activity/Sleep Data since $since');
      final samples = await _activityFetcher!.fetchActivityData(since);
      if (samples.isNotEmpty) {
        activityStore.addSamples(samples);
        activityStore.updateActivitySync(DateTime.now());
        _logger.i('Activity fetch: got ${samples.length} samples');
      } else {
        _logger.i('Activity fetch: no new samples');
      }

      // Persist
      await activityStore.save();
    } catch (e) {
      _logger.e('Activity fetch error: $e');
    } finally {
      _isFetchingActivity = false;
      notifyListeners();
    }
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
          _lastSyncTime = DateTime.now();
          _logger.d("Steps: ${parsed.steps}, ${parsed.distanceMeters} m, "
              "${parsed.calories} kcal");
          // Persist every update so data survives disconnects
          _storage.saveMetrics(_metrics);
          _storage.saveLastSyncTime(_lastSyncTime!);
          notifyListeners();
        }
      });

      // Note: 0x0007 is often notify-only on Mi Band 6.
      // We rely on the listener above for updates.
    } catch (e) {
      _logger.e("Steps subscription error: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Missing Notifications from Gadgetbridge Phase2/3
  // ---------------------------------------------------------------------------

  Future<void> _subscribeToMissingNotifications() async {
    if (_device == null || !_device!.isConnected) return;
    try {
      final services = await _device!.discoverServices();
      for (final svc in services) {
        if (svc.uuid.str.toLowerCase().contains('fee0')) {
          for (final char in svc.characteristics) {
            final cu = char.uuid.str.toLowerCase();
            // Subscribing to 0x0003 (config), 0x0010 (device events), 0x000F (notifs)
            if (cu.contains('0003') ||
                cu.contains('000f') ||
                cu.contains('0010')) {
              _logger.i("Subscribing to init characteristic $cu...");
              await char.setNotifyValue(true);
              char.onValueReceived.listen((data) {
                _logger.d(
                    "Init Char $cu data: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}");
              });
            }
          }
        }
      }
    } catch (e) {
      _logger.e("Init chars subscription failed: $e");
    }
  }

  Future<void> _setDateDisplay() async {
    await _writeConfig([0x06, 0x0a, 0x00, 0x03], "date display");
  }

  Future<void> _setTimeFormat() async {
    // 24h format: 0x06, 0x02, 0x00, 0x01
    await _writeConfig([0x06, 0x02, 0x00, 0x01], "24h time format");
  }

  Future<void> _writeConfig(List<int> cmd, String label) async {
    if (_device == null || !_device!.isConnected) return;
    try {
      BluetoothCharacteristic? configChar;
      final services = await _device!.discoverServices();
      for (final svc in services) {
        if (svc.uuid.str.toLowerCase().contains('fee0')) {
          for (final c in svc.characteristics) {
            if (c.uuid.str.toLowerCase().contains('0003')) {
              configChar = c;
              break;
            }
          }
        }
      }
      if (configChar != null) {
        _logger.i("Setting $label via 0003...");
        await configChar.write(cmd, withoutResponse: false);
      }
    } catch (e) {
      _logger.e("Failed to set $label: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Set User Info (0x4f to 0x0008)
  // ---------------------------------------------------------------------------

  Future<void> _setUserInfo() async {
    if (_device == null || !_device!.isConnected) return;
    try {
      BluetoothCharacteristic? userChar;
      final services = await _device!.discoverServices();
      for (final svc in services) {
        if (svc.uuid.str.toLowerCase().contains('fee0')) {
          for (final char in svc.characteristics) {
            if (char.uuid.str.toLowerCase().contains('0008')) {
              userChar = char;
              break;
            }
          }
        }
      }
      if (userChar != null) {
        _logger.i("Sending user info to 0x0008...");
        final year = 1990;
        final month = 1;
        final day = 1;
        final sex = 0; // 0=male, 1=female, 2=other
        final height = 175;
        final weight200 = 70 * 200;
        final userid = 12345678;

        final bytes = [
          0x4f,
          0x00,
          0x00,
          year & 0xff,
          (year >> 8) & 0xff,
          month,
          day,
          sex,
          height & 0xff,
          (height >> 8) & 0xff,
          weight200 & 0xff,
          (weight200 >> 8) & 0xff,
          userid & 0xff,
          (userid >> 8) & 0xff,
          (userid >> 16) & 0xff,
          (userid >> 24) & 0xff
        ];
        // Send without response for configuration
        await userChar.write(bytes, withoutResponse: false);
      }
    } catch (e) {
      _logger.e("Failed to set user info: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Heart rate — TODO: Mi Band 6 firmware blocks 0x2A37 CCCD writes
  //
  // What we confirmed works:
  //   ✓ Auth V3 handshake via fee1/FEC1
  //   ✓ fee0/0x0008 accepts all HR commands (GATT_SUCCESS):
  //     - [0x06, 0x1f, 0x00, 0x01]  Enable HR connection
  //     - [0x14, 0x01]              Set periodic interval
  //     - [0x15, 0x00, 0x01]        Enable HR sleep measurement
  //   ✓ BLE bonding (createBond) succeeds
  //
  // What's blocked:
  //   ✗ 0x180D/0x2A37 setNotifyValue → GATT_WRITE_NOT_PERMITTED (3)
  //     Even after: auth + bonding + HR commands + Zepp "discoverable" ON
  //
  // Possible next steps:
  //   1. Study how Gadgetbridge reads HR — it may use the Huami 2021
  //      chunked protocol (chars 0x0016/0x0017 which our band doesn't expose)
  //      or parse HR from activity data fetches, not realtime 0x2A37.
  //   2. Try a native Android BLE implementation (bypassing flutter_blue_plus)
  //      to rule out library-level descriptor handling issues.
  //   3. Check if Notify for Mi Band uses a different approach entirely.
  // ---------------------------------------------------------------------------

  Future<void> _subscribeToHeartRate() async {
    // TODO: HR monitoring not yet working — see notes above.
    _logger.d("HR: skipped (0x2A37 CCCD blocked by firmware).");
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
