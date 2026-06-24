class BandMetrics {
  final int steps;
  final int distanceMeters; // stored as metres (cm ÷ 100)
  final int calories;

  const BandMetrics({
    this.steps = 0,
    this.distanceMeters = 0,
    this.calories = 0,
  });

  /// Parse a real-time steps notification packet from the Mi Band.
  ///
  /// Mi Band 6 sends a 13-byte packet on fee0/0x0007 (confirmed on-device, e.g.
  /// `0c 13 00 00 00 0d 00 00 00 01 00 00 00` = 19 steps, 13 m, 1 kcal):
  ///   [0]       – category/flag byte (ignored)
  ///   [1..2]    – steps (uint16 little-endian) — the running daily total
  ///   [3..4]    – unknown / 0
  ///   [5..8]    – distance in **metres** (uint32 little-endian)
  ///   [9..12]   – calories (uint32 little-endian)
  /// Shorter packets carry just the step total.
  static BandMetrics? fromStepsPacket(List<int> data) {
    if (data.length < 3) return null;

    final steps = data[1] | (data[2] << 8);
    int distanceMeters = 0;
    int calories = 0;
    if (data.length >= 13) {
      distanceMeters =
          data[5] | (data[6] << 8) | (data[7] << 16) | (data[8] << 24);
      calories = data[9] | (data[10] << 8) | (data[11] << 16) | (data[12] << 24);
    }

    return BandMetrics(
      steps: steps,
      distanceMeters: distanceMeters,
      calories: calories,
    );
  }

  BandMetrics copyWith({int? steps, int? distanceMeters, int? calories}) {
    return BandMetrics(
      steps: steps ?? this.steps,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      calories: calories ?? this.calories,
    );
  }
}
