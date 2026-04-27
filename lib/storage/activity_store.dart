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
  static const _hrFile = 'hr_data.json';
  static const _lastActivitySyncFile = 'last_activity_sync.txt';
  static const _lastSpo2SyncFile = 'last_spo2_sync.txt';
  static const _lastHrSyncFile = 'last_hr_sync.txt';

  List<ActivitySample> _samples = [];
  List<Spo2Reading> _spo2Readings = [];
  List<HeartRateReading> _hrReadings = [];
  DateTime? _lastActivitySync;
  DateTime? _lastSpo2Sync;
  DateTime? _lastHrSync;

  List<ActivitySample> get samples => _samples;
  List<Spo2Reading> get spo2Readings => _spo2Readings;
  List<HeartRateReading> get hrReadings => _hrReadings;
  DateTime? get lastActivitySync => _lastActivitySync;
  DateTime? get lastSpo2Sync => _lastSpo2Sync;
  DateTime? get lastHrSync => _lastHrSync;
  @Deprecated('Use lastActivitySync')
  DateTime? get lastSyncTimestamp => _lastActivitySync;

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
      final f = await _getFile(_hrFile);
      if (await f.exists()) {
        final json = jsonDecode(await f.readAsString()) as List;
        _hrReadings = json
            .map((e) => HeartRateReading.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    try {
      final f = await _getFile(_lastActivitySyncFile);
      if (await f.exists()) {
        final ms = int.tryParse(await f.readAsString());
        if (ms != null) _lastActivitySync = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    } catch (_) {}

    try {
      final f = await _getFile(_lastSpo2SyncFile);
      if (await f.exists()) {
        final ms = int.tryParse(await f.readAsString());
        if (ms != null) _lastSpo2Sync = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    } catch (_) {}

    try {
      final f = await _getFile(_lastHrSyncFile);
      if (await f.exists()) {
        final ms = int.tryParse(await f.readAsString());
        if (ms != null) _lastHrSync = DateTime.fromMillisecondsSinceEpoch(ms);
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

    final f_hr = await _getFile(_hrFile);
    await f_hr.writeAsString(
        jsonEncode(_hrReadings.map((s) => s.toJson()).toList()));

    if (_lastActivitySync != null) {
      final f = await _getFile(_lastActivitySyncFile);
      await f.writeAsString(_lastActivitySync!.millisecondsSinceEpoch.toString());
    }
    if (_lastSpo2Sync != null) {
      final f = await _getFile(_lastSpo2SyncFile);
      await f.writeAsString(_lastSpo2Sync!.millisecondsSinceEpoch.toString());
    }
    if (_lastHrSync != null) {
      final f = await _getFile(_lastHrSyncFile);
      await f.writeAsString(_lastHrSync!.millisecondsSinceEpoch.toString());
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
      _lastActivitySync = DateTime.now();
    }
  }

  void updateActivitySync(DateTime ts) {
    _lastActivitySync = ts;
  }

  void updateSpo2Sync(DateTime ts) {
    _lastSpo2Sync = ts;
  }

  void updateHrSync(DateTime ts) {
    _lastHrSync = ts;
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

  void addHeartRateReadings(List<HeartRateReading> readings) {
    final existing =
        _hrReadings.map((r) => r.timestamp.millisecondsSinceEpoch).toSet();
    for (final r in readings) {
      if (!existing.contains(r.timestamp.millisecondsSinceEpoch)) {
        _hrReadings.add(r);
      }
    }
    _hrReadings.sort((a, b) => a.timestamp.compareTo(b.timestamp));
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

  List<SleepInterval> _extractSleepIntervals(List<ActivitySample> samples) {
    final intervals = <SleepInterval>[];
    if (samples.isEmpty) return intervals;

    SleepStage? currentStage;
    DateTime? intervalStart;
    int duration = 0;

    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      final stage = s.sleepStage;

      if (stage != null) {
        if (currentStage == stage) {
          duration++;
        } else {
          if (currentStage != null && intervalStart != null) {
            intervals.add(SleepInterval(
              startTime: intervalStart,
              endTime: intervalStart.add(Duration(minutes: duration)),
              stage: currentStage,
              durationMinutes: duration,
            ));
          }
          currentStage = stage;
          intervalStart = s.timestamp;
          duration = 1;
        }
      } else {
        if (currentStage != null && intervalStart != null) {
          intervals.add(SleepInterval(
            startTime: intervalStart,
            endTime: intervalStart.add(Duration(minutes: duration)),
            stage: currentStage,
            durationMinutes: duration,
          ));
        }
        currentStage = null;
        intervalStart = null;
        duration = 0;
      }
    }

    if (currentStage != null && intervalStart != null) {
      intervals.add(SleepInterval(
        startTime: intervalStart,
        endTime: intervalStart.add(Duration(minutes: duration)),
        stage: currentStage,
        durationMinutes: duration,
      ));
    }

    return intervals;
  }

  List<SleepDay> computeSleepDays() {
    final intervals = _extractSleepIntervals(_samples);
    if (intervals.isEmpty) return [];

    final days = <SleepDay>[];
    var currentGroup = <SleepInterval>[intervals.first];

    for (var i = 1; i < intervals.length; i++) {
      final current = intervals[i];
      final previous = currentGroup.last;

      final gap = current.startTime.difference(previous.endTime).inMinutes;
      if (gap <= 240) { // 4 hours overlap/gap
        currentGroup.add(current);
      } else {
        days.add(_buildSleepDay(currentGroup));
        currentGroup = [current];
      }
    }

    if (currentGroup.isNotEmpty) {
      days.add(_buildSleepDay(currentGroup));
    }

    return days;
  }

  SleepDay _buildSleepDay(List<SleepInterval> group) {
    int light = 0, deep = 0, rem = 0, awake = 0, nap = 0;
    for (final interval in group) {
      switch (interval.stage) {
        case SleepStage.light: light += interval.durationMinutes; break;
        case SleepStage.deep: deep += interval.durationMinutes; break;
        case SleepStage.rem: rem += interval.durationMinutes; break;
        case SleepStage.awake: awake += interval.durationMinutes; break;
        case SleepStage.nap: nap += interval.durationMinutes; break;
      }
    }

    // Use the date of the last interval's end to represent the sleep day
    final lastTime = group.last.endTime;
    final date = DateTime(lastTime.year, lastTime.month, lastTime.day);

    return SleepDay(
      date: date,
      intervals: group,
      totalLightMinutes: light,
      totalDeepMinutes: deep,
      totalRemMinutes: rem,
      totalAwakeMinutes: awake,
      totalNapMinutes: nap,
    );
  }

  /// Get the computed sleep day record for a specific date.
  SleepDay? getSleepForDate(DateTime date) {
    final days = computeSleepDays();
    try {
      return days.firstWhere((d) => 
        d.date.year == date.year && 
        d.date.month == date.month && 
        d.date.day == date.day);
    } catch (_) {
      return null;
    }
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
