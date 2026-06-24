import 'package:flutter_test/flutter_test.dart';
import 'package:band/core/activity_fetcher.dart';
import 'package:band/core/activity_sample.dart';
import 'package:band/core/band_metrics.dart';

/// Unit tests for the Mi Band 6 byte-layout parsing reconstructed from the
/// decompiled Notify app + Gadgetbridge (see docs/reverse-engineering/).
void main() {
  group('MB6 8-byte activity sample parsing', () {
    final start = DateTime(2026, 6, 24, 8, 0, 0);

    test('parses two 8-byte samples with correct field mapping', () {
      // sample 0: kind=0x70(sleep light), intensity=5, steps=10, hr=72,
      //           unknown=0, sleep=3, deep=1, rem=0
      // sample 1: kind=1, intensity=20, steps=200, hr=0(no reading),
      //           unknown=0, sleep=0, deep=0, rem=0
      final data = <int>[
        0x70, 5, 10, 72, 0, 3, 1, 0, //
        0x01, 20, 200, 0, 0, 0, 0, 0,
      ];

      final samples = ActivityFetcher.parseActivitySamples(data, start);
      expect(samples.length, 2);

      expect(samples[0].timestamp, start);
      expect(samples[0].category, 0x70);
      expect(samples[0].intensity, 5);
      expect(samples[0].steps, 10);
      expect(samples[0].heartRate, 72);
      expect(samples[0].sleep, 3);
      expect(samples[0].deepSleep, 1);
      expect(samples[0].remSleep, 0);

      // each sample is +1 minute
      expect(samples[1].timestamp, start.add(const Duration(minutes: 1)));
      expect(samples[1].steps, 200); // single-byte step count up to 255
      expect(samples[1].heartRate, 0); // hr==0 treated as no-reading
    });

    test('clamps out-of-range HR (0/255) to 0 but keeps valid values', () {
      final data = <int>[
        0, 0, 0, 255, 0, 0, 0, 0, // hr=255 -> 0
        0, 0, 0, 6, 0, 0, 0, 0, //   hr=6   -> 0 (below 7)
        0, 0, 0, 7, 0, 0, 0, 0, //   hr=7   -> 7 (min valid)
        0, 0, 0, 249, 0, 0, 0, 0, // hr=249 -> 249 (max valid)
      ];
      final samples = ActivityFetcher.parseActivitySamples(data, start);
      expect(samples.map((s) => s.heartRate).toList(), [0, 0, 7, 249]);
    });

    test('HR history is derived from activity samples (byte 3)', () {
      final data = <int>[
        0, 0, 0, 60, 0, 0, 0, 0, //
        0, 0, 0, 0, 0, 0, 0, 0, // no reading -> excluded
        0, 0, 0, 80, 0, 0, 0, 0,
      ];
      final samples = ActivityFetcher.parseActivitySamples(data, start);
      final hr = ActivityFetcher.heartRatesFromSamples(samples);
      expect(hr.length, 2);
      expect(hr.map((r) => r.value).toList(), [60, 80]);
      expect(hr[0].timestamp, start);
      expect(hr[1].timestamp, start.add(const Duration(minutes: 2)));
    });

    test('ignores a trailing partial sample', () {
      final data = <int>[0x01, 1, 5, 70, 0, 0, 0, 0, 0x01, 1, 5]; // 8 + 3
      final samples = ActivityFetcher.parseActivitySamples(data, start);
      expect(samples.length, 1);
    });
  });

  group('Realtime steps packet parsing (fee0/0x0007)', () {
    test('parses steps, distance, calories little-endian', () {
      // [sub, steps_lo, steps_hi, 0,0, dist_b0..b3, kcal]
      final data = <int>[0x00, 0x10, 0x27, 0, 0, 0xA0, 0x86, 0x01, 0x00, 0x32];
      final m = BandMetrics.fromStepsPacket(data);
      expect(m, isNotNull);
      expect(m!.steps, 0x2710); // 10000
      expect(m.distanceMeters, 1000); // 100000 cm / 100
      expect(m.calories, 50);
    });

    test('returns null for short packets', () {
      expect(BandMetrics.fromStepsPacket([0, 1, 2]), isNull);
    });
  });

  group('SleepStage classification', () {
    test('explicit sleep bytes win over category', () {
      final s = ActivitySample(
        timestamp: DateTime(2026, 6, 24),
        category: 0,
        intensity: 0,
        steps: 0,
        heartRate: 0,
        sleep: 5,
      );
      expect(s.sleepStage, SleepStage.light);
    });
  });
}
