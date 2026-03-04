import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

Uint8List sha1Digest(List<int> bytes) {
  return Uint8List.fromList(crypto.sha1.convert(bytes).bytes);
}

Uint8List sha256Digest(List<int> bytes) {
  return Uint8List.fromList(crypto.sha256.convert(bytes).bytes);
}

Uint8List md5Digest(List<int> bytes) {
  return Uint8List.fromList(crypto.md5.convert(bytes).bytes);
}

Uint8List hmacSha256(List<int> key, List<int> message) {
  final hmac = crypto.Hmac(crypto.sha256, key);
  return Uint8List.fromList(hmac.convert(message).bytes);
}

bool constantTimeEqualsBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= (a[i] ^ b[i]);
  }
  return result == 0;
}

String hexFromBytes(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
