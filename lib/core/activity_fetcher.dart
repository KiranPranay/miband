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
  Completer<List<int>>? _fetchCompleter;
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

  Future<List<int>> fetchRawData(int type, DateTime since) async {
    if (_activityControl == null) return [];

    _dataBuffer.clear();
    _fetchStartTime = since;
    _fetchCompleter = Completer<List<int>>();

    _logger.i('ActivityFetcher: requesting data type 0x${type.toRadixString(16)} since $since');
    final cmd = _buildFetchCommand(type, since);
    _logger.d('ActivityFetcher: cmd = ${_hexStr(cmd)}');

    try {
      await _activityControl!.write(cmd, withoutResponse: true);
      _logger.i('ActivityFetcher: fetch command sent');
    } catch (e) {
      _logger.e('ActivityFetcher: fetch command failed: $e');
      return [];
    }

    _fetchTimeout = Timer(const Duration(seconds: 60), () {
      if (!_fetchCompleter!.isCompleted) {
        _logger.e('ActivityFetcher: fetch timed out (60s) waiting for response');
        _sendAck();
        _fetchCompleter!.complete([]);
      }
    });

    return _fetchCompleter!.future;
  }

  Future<List<ActivitySample>> fetchActivityData(DateTime since) async {
    await fetchRawData(0x01, since);
    return _parseActivityData();
  }

  Future<List<Spo2Reading>> fetchSpo2(DateTime since) async {
    await fetchRawData(0x12, since);
    return _parseSpo2Data();
  }

  Future<List<HeartRateReading>> fetchHeartRateHistory(DateTime since) async {
    await fetchRawData(0x02, since);
    return _parseHeartRateData();
  }

  List<int> _buildFetchCommand(int type, DateTime since) {
    final tsSec = since.millisecondsSinceEpoch ~/ 1000;
    return [
      0x01,
      type,
      tsSec & 0xFF,
      (tsSec >> 8) & 0xFF,
      (tsSec >> 16) & 0xFF,
      (tsSec >> 24) & 0xFF,
      0x00,
      0x08,
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
      } else if (data[1] == 0x02 || data[1] == 0x0B) {
        // Step 2 response: Transfer finished or Chunks done (0x0B)
        if (data[2] == 0x01) {
          _logger.i('ActivityFetcher: band says fetch complete (0x${data[1].toRadixString(16)})');
          await _sendAck();
          _completeFetch();
        } else {
          _logger.e(
              'ActivityFetcher: fetch ended with error 0x${data[2].toRadixString(16)}');
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

    // ACK packet and request next chunk
    if (_activityControl != null) {
      _activityControl!.write([0x02], withoutResponse: true).catchError((e) {
        _logger.e('ActivityFetcher: failed to send chunk ACK: $e');
      });
    }
  }

  void _completeFetch() {
    _fetchTimeout?.cancel();
    _logger.i('ActivityFetcher: fetch complete, buffer size: ${_dataBuffer.length}');
    if (_fetchCompleter != null && !_fetchCompleter!.isCompleted) {
      _fetchCompleter!.complete(List.from(_dataBuffer));
    }
  }

  List<ActivitySample> _parseActivityData() {
    if (_dataBuffer.isEmpty || _fetchStartTime == null) return [];
    const sampleSize = 4;
    final sampleCount = _dataBuffer.length ~/ sampleSize;
    final samples = <ActivitySample>[];

    for (var i = 0; i < sampleCount; i++) {
      final offset = i * sampleSize;
      if (offset + sampleSize > _dataBuffer.length) break;
      final ts = _fetchStartTime!.add(Duration(minutes: i));
      
      final category = _dataBuffer[offset];
      final intensity = _dataBuffer[offset + 1];
      final steps = _dataBuffer[offset + 2] | (_dataBuffer[offset + 3] << 8);

      samples.add(ActivitySample(
        timestamp: ts,
        category: category,
        intensity: intensity,
        steps: steps,
        heartRate: 0, // HR is fetched separately in this mode
      ));
    }
    return samples;
  }

  List<HeartRateReading> _parseHeartRateData() {
    if (_dataBuffer.isEmpty || _fetchStartTime == null) return [];
    const sampleSize = 2;
    final sampleCount = _dataBuffer.length ~/ sampleSize;
    final readings = <HeartRateReading>[];

    for (var i = 0; i < sampleCount; i++) {
      final offset = i * sampleSize;
      if (offset + sampleSize > _dataBuffer.length) break;
      
      final hrValue = _dataBuffer[offset];
      if (hrValue > 0) {
        final ts = _fetchStartTime!.add(Duration(minutes: i));
        readings.add(HeartRateReading(
          timestamp: ts,
          value: hrValue,
        ));
      }
    }
    return readings;
  }

  List<Spo2Reading> _parseSpo2Data() {
    if (_dataBuffer.isEmpty || _fetchStartTime == null) return [];
    const sampleSize = 2;
    final sampleCount = _dataBuffer.length ~/ sampleSize;
    final readings = <Spo2Reading>[];

    for (var i = 0; i < sampleCount; i++) {
      final offset = i * sampleSize;
      if (offset + sampleSize > _dataBuffer.length) break;
      
      final spo2Value = _dataBuffer[offset];
      if (spo2Value > 0 && spo2Value <= 100) {
        final ts = _fetchStartTime!.add(Duration(minutes: i));
        readings.add(Spo2Reading(
          timestamp: ts,
          value: spo2Value,
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
