import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class BLEEncryption {
  /// Encrypts the payload using AES ECB mode, without padding.
  /// Supports any payload length that is a multiple of 16 bytes.
  static Uint8List encryptAESECB(Uint8List key, Uint8List payload) {
    if (key.length != 16) {
      throw Exception(
        'Key must be exactly 16 bytes. Current length: ${key.length}',
      );
    }
    if (payload.isEmpty || payload.length % 16 != 0) {
      throw Exception(
        'Payload must be a non-empty multiple of 16 bytes. Length: ${payload.length}',
      );
    }

    final cipher = BlockCipher('AES/ECB')
      ..init(
        true, // encrypt
        KeyParameter(key),
      );

    final enc = Uint8List(payload.length);
    for (int offset = 0; offset < payload.length; offset += 16) {
      cipher.processBlock(payload, offset, enc, offset);
    }

    return enc;
  }
}
