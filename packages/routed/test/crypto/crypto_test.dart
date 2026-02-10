import 'dart:convert';
import 'dart:typed_data';

import 'package:routed/src/crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  group('sha1Digest', () {
    test('empty input produces known SHA-1 hash', () {
      // SHA-1("") = da39a3ee5e6b4b0d3255bfef95601890afd80709
      final result = sha1Digest([]);
      expect(hexFromBytes(result), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
    });

    test('known input matches RFC 3174 test vector', () {
      // SHA-1("abc") = a9993e364706816aba3e25717850c26c9cd0d89d
      final result = sha1Digest(utf8.encode('abc'));
      expect(hexFromBytes(result), 'a9993e364706816aba3e25717850c26c9cd0d89d');
    });
  });

  group('sha256Digest', () {
    test('empty input produces known SHA-256 hash', () {
      // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
      final result = sha256Digest([]);
      expect(
        hexFromBytes(result),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('known input matches expected hash', () {
      // SHA-256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
      final result = sha256Digest(utf8.encode('abc'));
      expect(
        hexFromBytes(result),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('md5Digest', () {
    test('empty input produces known MD5 hash', () {
      // MD5("") = d41d8cd98f00b204e9800998ecf8427e
      final result = md5Digest([]);
      expect(hexFromBytes(result), 'd41d8cd98f00b204e9800998ecf8427e');
    });

    test('known input matches expected hash', () {
      // MD5("abc") = 900150983cd24fb0d6963f7d28e17f72
      final result = md5Digest(utf8.encode('abc'));
      expect(hexFromBytes(result), '900150983cd24fb0d6963f7d28e17f72');
    });
  });

  group('hmacSha256', () {
    test('RFC 4231 test case 2', () {
      // Key = "Jefe", Data = "what do ya want for nothing?"
      // HMAC-SHA256 = 5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843
      final key = utf8.encode('Jefe');
      final data = utf8.encode('what do ya want for nothing?');
      final result = hmacSha256(key, data);
      expect(
        hexFromBytes(result),
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );
    });
  });

  group('constantTimeEqualsBytes', () {
    test('equal byte lists return true', () {
      expect(constantTimeEqualsBytes([1, 2, 3], [1, 2, 3]), isTrue);
    });

    test('different byte lists return false', () {
      expect(constantTimeEqualsBytes([1, 2, 3], [1, 2, 4]), isFalse);
    });

    test('different lengths return false', () {
      expect(constantTimeEqualsBytes([1, 2], [1, 2, 3]), isFalse);
    });

    test('empty lists return true', () {
      expect(constantTimeEqualsBytes([], []), isTrue);
    });
  });

  group('hexFromBytes', () {
    test('empty list returns empty string', () {
      expect(hexFromBytes([]), '');
    });

    test('pads single-digit hex values with leading zero', () {
      expect(hexFromBytes([0, 1, 15]), '00010f');
    });

    test('known bytes produce expected hex', () {
      expect(hexFromBytes([0xde, 0xad, 0xbe, 0xef]), 'deadbeef');
    });

    test('Uint8List input works', () {
      final bytes = Uint8List.fromList([0xca, 0xfe]);
      expect(hexFromBytes(bytes), 'cafe');
    });
  });
}
