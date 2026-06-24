// Smoke test. The original Flutter counter-app template that shipped here
// referenced a non-existent `MyApp`/counter UI and failed to compile; it was
// replaced with a minimal valid test. App-protocol logic is covered by
// mb6_protocol_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:band/core/logger.dart';

void main() {
  test('BLELogger records messages and clears them', () {
    final logger = BLELogger();
    expect(logger.logs, isEmpty);

    logger.i('hello');
    logger.e('boom');
    expect(logger.logs.length, 2);
    expect(logger.logs.first, contains('hello'));

    logger.clearLogs();
    expect(logger.logs, isEmpty);
  });
}
