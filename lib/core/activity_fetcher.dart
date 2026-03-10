import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'activity_sample.dart';
import 'logger.dart';

/// Implements the Huami activity data fetch protocol for Mi Band 6.
class ActivityFetcher {
  final BLELogger _logger;
  final BluetoothDevice _device;

  BluetoothCharacteristic? _activityControl; // fee0/0x0004
  BluetoothCharacteristic? _activityData; // fee0/0x0005

  StreamSubscription<List<int>>? _controlSub;
  StreamSubscription<List<int>>? _dataSub;

  final List<int> _dataBuffer = [];
  DateTime? _fetchStartTime;
  int _expectedSampleSize = 8;
  Completer<List<ActivitySample>>? _fetchCompleter;
  Timer? _fetchTimeout;

  ActivityFetcher(this._logger, this._device);

  Future<bool> init() async {
    try {
      final services = await _device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.str.toLowerCase().contains('fee0')) {
          _logger.d("FEE0 Service found. Characteristics:");
          for (final c in svc.characteristics) {
            final cu = c.uuid.str.toLowerCase();
            _logger.d("  - $cu");
            if (cu.contains('0004')) _activityControl = c;
            if (cu.contains('0005')) _activityData = c;
          }
        }
      }

      if (_activityControl == null || _activityData == null) {
        _logger.e('ActivityFetcher: missing characteristics');
        return false;
      }

      _logger.d('ActivityFetcher: Control properties: '
          'read=${_activityControl!.properties.read}, '
          'write=${_activityControl!.properties.write}, '
          'writeWithoutResponse=${_activityControl!.properties.writeWithoutResponse}, '
          'notify=${_activityControl!.properties.notify}, '
          'indicate=${_activityControl!.properties.indicate}');

      _logger.d('ActivityFetcher: Data properties: '
          'read=${_activityData!.properties.read}, '
          'write=${_activityData!.properties.write}, '
          'writeWithoutResponse=${_activityData!.properties.writeWithoutResponse}, '
          'notify=${_activityData!.properties.notify}, '
          'indicate=${_activityData!.properties.indicate}');

      // Do NOT enable `_activityData` notify yet. Gadgetbridge enables it later!
      _dataSub = _activityData!.onValueReceived.listen(_onDataReceived);

      await _activityControl!.setNotifyValue(true);
      _controlSub =
          _activityControl!.onValueReceived.listen(_onControlReceived);

      // NEW: Send preliminary ACK to clear any stuck state on the band
      _logger.i('ActivityFetcher: sending cleanup ACK (0x03)');
      await _sendAck();

      _logger.i('ActivityFetcher: initialized OK');
      return true;
    } catch (e) {
      _logger.e('ActivityFetcher init failed: $e');
      return false;
    }
  }

  Future<List<ActivitySample>> fetchActivityData(DateTime since) async {
    if (_activityControl == null) return [];

    _dataBuffer.clear();
    _fetchStartTime = since;
    _fetchCompleter = Completer<List<ActivitySample>>();

    // Note: Huami characters 0x0004/0x0005 usually ONLY support WRITE_WITHOUT_RESPONSE
    const writeMode = true;

    _logger.i('ActivityFetcher: requesting data since $since');
    final cmd = _buildFetchCommand(0x01, since);
    _logger.d('ActivityFetcher: cmd = ${_hexStr(cmd)}');

    try {
      await _activityControl!.write(cmd, withoutResponse: writeMode);
      _logger.i('ActivityFetcher: fetch command sent');
    } catch (e) {
      _logger.e('ActivityFetcher: fetch command failed: $e');
      return [];
    }

    _fetchTimeout = Timer(const Duration(seconds: 60), () {
      if (!_fetchCompleter!.isCompleted) {
        _logger
            .e('ActivityFetcher: fetch timed out (60s) waiting for response');
        _sendAck();
        _fetchCompleter!.complete([]);
      }
    });

    return _fetchCompleter!.future;
  }

  Future<List<Spo2Reading>> fetchSpo2(DateTime since) async {
    if (_activityControl == null) return [];
    _dataBuffer.clear();
    _fetchStartTime = since;
    _fetchCompleter = Completer<List<ActivitySample>>();

    final cmd = _buildFetchCommand(0x25, since);
    try {
      await _activityControl!.write(cmd, withoutResponse: true);
    } catch (e) {
      _logger.e('ActivityFetcher: SPO2 fetch command failed: $e');
      return [];
    }

    try {
      await _fetchCompleter!.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      _logger.e('ActivityFetcher: SPO2 fetch timed out');
      await _sendAck();
    }

    return _parseSpo2Data();
  }

  List<int> _buildFetchCommand(int type, DateTime since) {
    final year = since.year;
    final tzQuarters = since.timeZoneOffset.inMinutes ~/ 15;

    return [
      0x01, // COMMAND_ACTIVITY_DATA_START_DATE
      type, // 0x01 for activity, 0x25 for SPO2
      year & 0xFF,
      (year >> 8) & 0xFF,
      since.month,
      since.day,
      since.hour,
      since.minute,
      0x00, // padding/reason
      tzQuarters & 0xFF, // Timezone quarters
    ];
  }

  void _onControlReceived(List<int> data) async {
    if (data.isEmpty) return;
    _logger.i('ActivityFetcher CTRL notified: ${_hexStr(data)}');

    if (data.length >= 3 && data[0] == 0x10) {
      if (data[1] == 0x01) {
        // Step 1 response: Metadata
        if (data[2] == 0x01) {
          _logger.i('ActivityFetcher: band accepted fetch request');
          if (data.length >= 7) {
            // Bytes 3,4,5,6 are the expected data length (number of bytes to receive)
            int expectedLen =
                data[3] | (data[4] << 8) | (data[5] << 16) | (data[6] << 24);
            _logger.i('ActivityFetcher: expected data length = $expectedLen');
            if (expectedLen == 0) {
              _logger.i('ActivityFetcher: No new data to fetch.');
              await _sendAck();
              _completeFetch();
              return;
            }

            _expectedSampleSize = data.length >= 8 ? data[7] : 8;
            _logger.d(
                'ActivityFetcher: sample size from band = $_expectedSampleSize');
          }
          await _sendFetchDataCommand();
        } else {
          _logger.e(
              'ActivityFetcher: band rejected date (code 0x${data[2].toRadixString(16)})');
          await _sendAck();
          if (!_fetchCompleter!.isCompleted) _fetchCompleter!.complete([]);
        }
      } else if (data[1] == 0x02) {
        // Step 2 response: Transfer finished
        if (data[2] == 0x01) {
          _logger.i('ActivityFetcher: band says fetch complete');
          await _sendAck();
          _completeFetch();
        } else {
          _logger.e(
              'ActivityFetcher: fetch ended with error 0x${data[2].toRadixString(16)})');
          _completeFetch();
        }
      }
    } else {
      _logger.d('ActivityFetcher CTRL unexpected: ${_hexStr(data)}');
    }
  }

  Future<void> _sendFetchDataCommand() async {
    try {
      _logger.i(
          'ActivityFetcher: enabling data notify (0x0005) before fetch stream');
      await _activityData!.setNotifyValue(true);

      _logger.i('ActivityFetcher: sending 0x02 (fetch data)');
      await _activityControl!.write([0x02], withoutResponse: true);
    } catch (e) {
      _logger.e('ActivityFetcher: failed to send 0x02: $e');
    }
  }

  Future<void> _sendAck() async {
    if (_activityControl == null) return;
    try {
      _logger.i('ActivityFetcher: sending 0x03 (ACK)');
      await _activityControl!.write([0x03], withoutResponse: true);
    } catch (e) {
      _logger.e('ActivityFetcher: failed to send ACK: $e');
    }
  }

  /*
  Future<void> _sendStopCommand() async {
    if (_activityControl == null) return;
    try {
      await _activityControl!.write([0x03], withoutResponse: true);
    } catch (_) {}
  }
  */

  void _onDataReceived(List<int> data) {
    if (data.isEmpty) return;
    _fetchTimeout?.cancel();
    _fetchTimeout = Timer(const Duration(seconds: 15), () {
      if (_fetchCompleter != null && !_fetchCompleter!.isCompleted) {
        _logger.e('ActivityFetcher: data stream stalled');
        _completeFetch();
      }
    });

    final payload = data.sublist(1);
    _dataBuffer.addAll(payload);
    _logger
        .d('ActivityFetcher DATA: ${data.length} bytes (counter: ${data[0]})');
  }

  void _completeFetch() {
    _fetchTimeout?.cancel();
    final samples = _parseActivityData();
    _logger.i('ActivityFetcher: parsed ${samples.length} activity samples');
    if (_fetchCompleter != null && !_fetchCompleter!.isCompleted) {
      _fetchCompleter!.complete(samples);
    }
  }

  List<ActivitySample> _parseActivityData() {
    if (_dataBuffer.isEmpty || _fetchStartTime == null) return [];
    final sampleSize = _expectedSampleSize;
    if (sampleSize == 0) return [];
    final sampleCount = _dataBuffer.length ~/ sampleSize;
    final samples = <ActivitySample>[];

    for (var i = 0; i < sampleCount; i++) {
      final offset = i * sampleSize;
      if (offset + sampleSize > _dataBuffer.length) break;
      final ts = _fetchStartTime!.add(Duration(minutes: i));
      samples.add(ActivitySample(
        timestamp: ts,
        category: _dataBuffer[offset],
        intensity: _dataBuffer[offset + 1],
        steps: _dataBuffer[offset + 2],
        heartRate: _dataBuffer[offset + 3],
        sleep: sampleSize >= 8 ? _dataBuffer[offset + 5] : null,
        deepSleep: sampleSize >= 8 ? _dataBuffer[offset + 6] : null,
        remSleep: sampleSize >= 8 ? _dataBuffer[offset + 7] : null,
      ));
    }
    return samples;
  }

  List<Spo2Reading> _parseSpo2Data() {
    if (_dataBuffer.isEmpty) return [];
    final readings = <Spo2Reading>[];
    const recordSize = 65;
    int startIdx = (_dataBuffer[0] == 2) ? 1 : 0;
    for (var i = startIdx;
        i + recordSize <= _dataBuffer.length;
        i += recordSize) {
      final tsSec = _dataBuffer[i] |
          (_dataBuffer[i + 1] << 8) |
          (_dataBuffer[i + 2] << 16) |
          (_dataBuffer[i + 3] << 24);
      int valRaw = _dataBuffer[i + 4];
      int spo2 = valRaw > 127 ? valRaw - 128 : valRaw;
      if (spo2 > 0 && spo2 <= 100) {
        readings.add(Spo2Reading(
          timestamp: DateTime.fromMillisecondsSinceEpoch(tsSec * 1000),
          value: spo2,
        ));
      }
    }
    return readings;
  }

  void dispose() {
    _controlSub?.cancel();
    _dataSub?.cancel();
    _fetchTimeout?.cancel();
  }

  String _hexStr(List<int> data) =>
      data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
