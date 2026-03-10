/// Per-minute activity sample fetched from the band's internal storage.
///
/// The Mi Band stores one sample per minute. Each sample has:
///  - category: activity type / sleep stage flag
///  - intensity: movement intensity (0-255)
///  - steps: steps taken in this minute
///  - heartRate: HR reading (0 = not measured)
class ActivitySample {
  final DateTime timestamp;
  final int category;
  final int intensity;
  final int steps;
  final int heartRate;

  // Extended fields for 8-byte samples (Mi Band 6+)
  final int? sleep;
  final int? deepSleep;
  final int? remSleep;

  const ActivitySample({
    required this.timestamp,
    required this.category,
    required this.intensity,
    required this.steps,
    required this.heartRate,
    this.sleep,
    this.deepSleep,
    this.remSleep,
  });

  SleepStage? get sleepStage {
    // If we have explicit sleep bytes (8-byte format), use them
    if (sleep != null) {
      if (sleep! > 0) return SleepStage.light;
      if (deepSleep != null && deepSleep! > 0) return SleepStage.deep;
      if (remSleep != null && remSleep! > 0) return SleepStage.rem;
    }
    // Fallback to category-based detection for 4-byte samples or if explicit bytes are 0
    return SleepStage.fromCategory(category);
  }

  bool get isSleep => sleepStage != null;
  bool get isActive => !isSleep && steps > 0;

  Map<String, dynamic> toJson() => {
        't': timestamp.millisecondsSinceEpoch,
        'c': category,
        'i': intensity,
        's': steps,
        'h': heartRate,
        if (sleep != null) 'sl': sleep,
        if (deepSleep != null) 'ds': deepSleep,
        if (remSleep != null) 'rs': remSleep,
      };

  factory ActivitySample.fromJson(Map<String, dynamic> j) => ActivitySample(
        timestamp: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
        category: j['c'] as int,
        intensity: j['i'] as int,
        steps: j['s'] as int,
        heartRate: j['h'] as int,
        sleep: j['sl'] as int?,
        deepSleep: j['ds'] as int?,
        remSleep: j['rs'] as int?,
      );

  @override
  String toString() =>
      'Sample(${timestamp.toString().substring(11, 16)} cat=$category '
      'int=$intensity steps=$steps hr=$heartRate${sleep != null ? ' s=$sleep ds=$deepSleep rs=$remSleep' : ''})';
}

/// Recognised sleep stages from the band's category byte.
enum SleepStage {
  light,
  deep,
  rem,
  awake;

  static SleepStage? fromCategory(int cat) {
    // Huami category values from Gadgetbridge:
    //  112     = light sleep
    //  121,122 = deep sleep
    //  123     = REM sleep
    //  Others in 1xx range with specific bits = awake-in-bed
    if (cat == 112) return SleepStage.light;
    if (cat == 121 || cat == 122) return SleepStage.deep;
    if (cat == 123) return SleepStage.rem;
    return null;
  }

  String get label {
    switch (this) {
      case SleepStage.light:
        return 'Light';
      case SleepStage.deep:
        return 'Deep';
      case SleepStage.rem:
        return 'REM';
      case SleepStage.awake:
        return 'Awake';
    }
  }
}

/// Summary of a sleep session (one contiguous block).
class SleepSession {
  final DateTime bedtime;
  final DateTime wakeTime;
  final int lightMinutes;
  final int deepMinutes;
  final int remMinutes;
  final int awakeMinutes;
  final List<ActivitySample> samples;

  const SleepSession({
    required this.bedtime,
    required this.wakeTime,
    required this.lightMinutes,
    required this.deepMinutes,
    required this.remMinutes,
    required this.awakeMinutes,
    required this.samples,
  });

  int get totalMinutes => wakeTime.difference(bedtime).inMinutes;

  String get durationString {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '${h}h ${m}m';
  }
}

/// SPO2 reading.
class Spo2Reading {
  final DateTime timestamp;
  final int value; // 0-100 percent

  const Spo2Reading({required this.timestamp, required this.value});

  Map<String, dynamic> toJson() => {
        't': timestamp.millisecondsSinceEpoch,
        'v': value,
      };

  factory Spo2Reading.fromJson(Map<String, dynamic> j) => Spo2Reading(
        timestamp: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
        value: j['v'] as int,
      );
}

/// Hourly step data point.
class HourlySteps {
  final int hour; // 0-23
  final int steps;
  final int calories;

  const HourlySteps({
    required this.hour,
    required this.steps,
    this.calories = 0,
  });
}
