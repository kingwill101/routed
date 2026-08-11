import 'dart:typed_data';

import 'package:pointycastle/api.dart' show KeyParameter, Mac, Digest;
import 'package:pointycastle/digests/md5.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/macs/hmac.dart';

Uint8List sha1Digest(List<int> bytes) => _digest(SHA1Digest(), bytes);

Uint8List sha256Digest(List<int> bytes) => _digest(SHA256Digest(), bytes);

Uint8List md5Digest(List<int> bytes) => _digest(MD5Digest(), bytes);

Uint8List hmacSha256(List<int> key, List<int> message) {
  final mac = HMac(SHA256Digest(), 64) as Mac;
  mac.init(KeyParameter(Uint8List.fromList(key)));
  final msgBytes = Uint8List.fromList(message);
  mac.update(msgBytes, 0, msgBytes.length);
  final out = Uint8List(mac.macSize);
  mac.doFinal(out, 0);
  return out;
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

Uint8List _digest(Digest digest, List<int> bytes) {
  digest.update(Uint8List.fromList(bytes), 0, bytes.length);
  final out = Uint8List(digest.digestSize);
  digest.doFinal(out, 0);
  return out;
}
