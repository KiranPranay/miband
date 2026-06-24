import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:band/core/huami2021_chunked.dart';

void main() {
  group('CRC32', () {
    test('matches known IEEE CRC32 of "123456789"', () {
      // The canonical CRC-32 check value is 0xCBF43926.
      final data = '123456789'.codeUnits;
      expect(crc32(data), 0xCBF43926);
    });
  });

  group('Huami2021 chunked round-trip', () {
    /// Encode [data] for [type] then feed every produced chunk back through a
    /// decoder; return what the decoder dispatched.
    ({int type, Uint8List payload}) roundTrip(
      Uint8List data,
      int type, {
      required bool encrypt,
      int mtu = 247,
      Uint8List? sessionKey,
    }) {
      late int gotType;
      late Uint8List gotPayload;
      final decoder = Huami2021ChunkedDecoder((t, p) {
        gotType = t;
        gotPayload = p;
      }, force2021Protocol: true);
      if (sessionKey != null) decoder.setEncryptionParameters(sessionKey);

      final encoder = Huami2021ChunkedEncoder(mtu);
      if (sessionKey != null) {
        encoder.setEncryptionParameters(0x11223344, sessionKey);
      }

      encoder.write((chunk) => decoder.decode(chunk), type, data, true, encrypt);
      return (type: gotType, payload: gotPayload);
    }

    test('plaintext single chunk', () {
      final data = Uint8List.fromList(List.generate(20, (i) => i + 1));
      final r = roundTrip(data, 0x0082, encrypt: false);
      expect(r.type, 0x0082);
      expect(r.payload, equals(data));
    });

    test('plaintext multi-chunk (small MTU forces fragmentation)', () {
      final data = Uint8List.fromList(List.generate(200, (i) => (i * 7) & 0xff));
      final r = roundTrip(data, 0x0011, encrypt: false, mtu: 30);
      expect(r.type, 0x0011);
      expect(r.payload, equals(data));
    });

    test('encrypted round-trip recovers original payload + type', () {
      final key = Uint8List.fromList(List.generate(16, (i) => (i * 9 + 1) & 0xff));
      final data = Uint8List.fromList(List.generate(40, (i) => (i * 3) & 0xff));
      final r = roundTrip(data, 0x0008, encrypt: true, sessionKey: key);
      expect(r.type, 0x0008);
      expect(r.payload, equals(data));
    });

    test('encrypted multi-chunk round-trip', () {
      final key = Uint8List.fromList(List.generate(16, (i) => (i * 13 + 5) & 0xff));
      final data = Uint8List.fromList(List.generate(150, (i) => (i * 5) & 0xff));
      final r = roundTrip(data, 0x0008, encrypt: true, sessionKey: key, mtu: 40);
      expect(r.type, 0x0008);
      expect(r.payload, equals(data));
    });
  });
}
