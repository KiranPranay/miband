import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../core/activity_sample.dart';

/// Simple JSON-file persistence for activity samples.
///
/// Stores raw activity samples per day, and provides query methods
/// to compute hourly steps, sleep sessions, and SPO2 readings.
class ActivityStore {
  static const _activityFile = 'activity_data.json';
  static const _spo2File = 'spo2_data.json';
  static const _lastSyncFile = 'last_activity_sync.txt';

  List<ActivitySample> _samples = [];
  List<Spo2Reading> _spo2Readings = [];
  DateTime? _lastSyncTimestamp;

  List<ActivitySample> get samples => _samples;
  List<Spo2Reading> get spo2Readings => _spo2Readings;
  DateTime? get lastSyncTimestamp => _lastSyncTimestamp;

  // ── File paths ──────────────────────────────────────────────────────────

  Future<File> _getFile(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  // ── Load / Save ─────────────────────────────────────────────────────────

  Future<void> load() async {
    try {
      final f = await _getFile(_activityFile);
      if (await f.exists()) {
        final json = jsonDecode(await f.readAsString()) as List;
        _samples = json
            .map((e) => ActivitySample.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    try {
      final f = await _getFile(_spo2File);
      if (await f.exists()) {
        final json = jsonDecode(await f.readAsString()) as List;
        _spo2Readings = json
            .map((e) => Spo2Reading.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    try {
      final f = await _getFile(_lastSyncFile);
      if (await f.exists()) {
        final ms = int.tryParse(await f.readAsString());
        if (ms != null) {
          _lastSyncTimestamp = DateTime.fromMillisecondsSinceEpoch(ms);
        }
      }
    } catch (_) {}
  }

  Future<void> save() async {
    final f1 = await _getFile(_activityFile);
    await f1
        .writeAsString(jsonEncode(_samples.map((s) => s.toJson()).toList()));

    final f2 = await _getFile(_spo2File);
    await f2.writeAsString(
        jsonEncode(_spo2Readings.map((s) => s.toJson()).toList()));

    if (_lastSyncTimestamp != null) {
      final f3 = await _getFile(_lastSyncFile);
      await f3
          .writeAsString(_lastSyncTimestamp!.millisecondsSinceEpoch.toString());
    }
  }

  // ── Add data ────────────────────────────────────────────────────────────

  void addSamples(List<ActivitySample> newSamples) {
    // De-duplicate by timestamp
    final existing =
        _samples.map((s) => s.timestamp.millisecondsSinceEpoch).toSet();
    for (final s in newSamples) {
      if (!existing.contains(s.timestamp.millisecondsSinceEpoch)) {
        _samples.add(s);
      }
    }
    _samples.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (newSamples.isNotEmpty) {
      _lastSyncTimestamp = DateTime.now();
    }
  }

  void addSpo2Readings(List<Spo2Reading> readings) {
    final existing =
        _spo2Readings.map((r) => r.timestamp.millisecondsSinceEpoch).toSet();
    for (final r in readings) {
      if (!existing.contains(r.timestamp.millisecondsSinceEpoch)) {
        _spo2Readings.add(r);
      }
    }
    _spo2Readings.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  // ── Queries ─────────────────────────────────────────────────────────────

  /// Get samples for a specific date.
  List<ActivitySample> samplesForDate(DateTime date) {
    return _samples.where((s) {
      return s.timestamp.year == date.year &&
          s.timestamp.month == date.month &&
          s.timestamp.day == date.day;
    }).toList();
  }

  /// Get step count per hour for a given date.
  List<HourlySteps> getStepsByHour(DateTime date) {
    final daySamples = samplesForDate(date);
    final byHour = <int, int>{};
    for (final s in daySamples) {
      final h = s.timestamp.hour;
      byHour[h] = (byHour[h] ?? 0) + s.steps;
    }
    return List.generate(
        24, (h) => HourlySteps(hour: h, steps: byHour[h] ?? 0));
  }

  /// Total steps for a given date.
  int totalStepsForDate(DateTime date) {
    return samplesForDate(date).fold(0, (sum, s) => sum + s.steps);
  }

  /// Detect sleep sessions from activity samples.
  ///
  /// Looks for contiguous blocks of sleep-category samples.
  /// A sleep session must be at least 30 minutes.
  List<SleepSession> getSleepSessions(DateTime date) {
    // Include previous evening (from 8pm previous day to noon today)
    final windowStart = DateTime(date.year, date.month, date.day - 1, 20);
    final windowEnd = DateTime(date.year, date.month, date.day, 12);

    final sleepSamples = _samples
        .where((s) =>
            s.timestamp.isAfter(windowStart) &&
            s.timestamp.isBefore(windowEnd) &&
            s.isSleep)
        .toList();

    if (sleepSamples.isEmpty) return [];

    // Group into contiguous blocks (gap > 30 min = new session)
    final sessions = <SleepSession>[];
    var sessionStart = 0;

    for (var i = 1; i <= sleepSamples.length; i++) {
      final isEnd = i == sleepSamples.length ||
          sleepSamples[i]
                  .timestamp
                  .difference(sleepSamples[i - 1].timestamp)
                  .inMinutes >
              30;

      if (isEnd) {
        final block = sleepSamples.sublist(sessionStart, i);
        if (block.length >= 30) {
          // Count stages
          int light = 0, deep = 0, rem = 0, awake = 0;
          for (final s in block) {
            switch (s.sleepStage) {
              case SleepStage.light:
                light++;
                break;
              case SleepStage.deep:
                deep++;
                break;
              case SleepStage.rem:
                rem++;
                break;
              case SleepStage.awake:
                awake++;
                break;
              case null:
                break;
            }
          }

          sessions.add(SleepSession(
            bedtime: block.first.timestamp,
            wakeTime: block.last.timestamp.add(const Duration(minutes: 1)),
            lightMinutes: light,
            deepMinutes: deep,
            remMinutes: rem,
            awakeMinutes: awake,
            samples: block,
          ));
        }
        sessionStart = i;
      }
    }

    return sessions;
  }

  /// Get SPO2 readings for a specific date.
  List<Spo2Reading> getSpo2ForDate(DateTime date) {
    return _spo2Readings.where((r) {
      return r.timestamp.year == date.year &&
          r.timestamp.month == date.month &&
          r.timestamp.day == date.day;
    }).toList();
  }

  /// Purge data older than N days to keep storage bounded.
  void purgeOlderThan(int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    _samples.removeWhere((s) => s.timestamp.isBefore(cutoff));
    _spo2Readings.removeWhere((r) => r.timestamp.isBefore(cutoff));
  }
}
