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
  /// Packet layout (fee0 / characteristic 0x0007):
  ///   [0]       – sub-command byte (ignored)
  ///   [1..2]    – steps (uint16 little-endian)
  ///   [3..4]    – unknown / always 0
  ///   [5..8]    – distance in cm (uint32 little-endian)
  ///   [9]       – calories
  static BandMetrics? fromStepsPacket(List<int> data) {
    if (data.length < 10) return null;

    final steps = data[1] | (data[2] << 8);
    final distanceCm =
        data[5] | (data[6] << 8) | (data[7] << 16) | (data[8] << 24);
    final calories = data[9];

    return BandMetrics(
      steps: steps,
      distanceMeters: distanceCm ~/ 100,
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
