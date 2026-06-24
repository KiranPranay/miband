import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:band/core/ecdh_b163.dart';

/// Validates the B-163 ECDH port via the fundamental DH property:
///   shared(privA, pubB) == shared(privB, pubA)
/// If any field/point arithmetic is wrong, the two shared secrets diverge.
void main() {
  Uint8List priv(int seed) {
    final b = Uint8List(EcdhB163.eccPrvKeySize);
    for (var i = 0; i < b.length; i++) {
      b[i] = (seed * 37 + i * 101 + 7) & 0xff;
    }
    // ensure high degree (>= curveDegree/2) so key generation is accepted
    b[20] = 0xff;
    return b;
  }

  test('public key generation succeeds and is 48 bytes on curve', () {
    final pub = EcdhB163.generatePublic(priv(1));
    expect(pub, isNotNull);
    expect(pub!.length, EcdhB163.eccPubKeySize);
    // a generated public key must itself produce a valid shared secret
    final shared = EcdhB163.generateShared(priv(2), pub);
    expect(shared, isNotNull);
  });

  test('ECDH shared secret agrees both directions', () {
    final a = priv(11);
    final b = priv(29);
    final pubA = EcdhB163.generatePublic(a)!;
    final pubB = EcdhB163.generatePublic(b)!;

    final sAB = EcdhB163.generateShared(a, pubB)!;
    final sBA = EcdhB163.generateShared(b, pubA)!;

    // The shared point (both coordinates, 48 bytes) must match exactly.
    expect(sAB, equals(sBA));
    // sanity: not all zero
    expect(sAB.any((x) => x != 0), isTrue);
  });

  test('different key pairs yield different shared secrets', () {
    final a = priv(3);
    final b = priv(4);
    final c = priv(5);
    final pubB = EcdhB163.generatePublic(b)!;
    final pubC = EcdhB163.generatePublic(c)!;
    expect(EcdhB163.generateShared(a, pubB),
        isNot(equals(EcdhB163.generateShared(a, pubC))));
  });
}
