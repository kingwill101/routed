import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/api.dart' show AEADParameters, KeyParameter;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';

/// Protects cookie payloads with HMAC signing, AES encryption, or both.
///
/// HMAC prevents tampering, AES provides confidentiality, and [SecurityMode.both]
/// combines the protections. Cookie names are authenticated as part of the
/// payload protection.
class SecureCookie {
  final List<int>? _hmacKey;
  final Uint8List? _aesKey;
  final SecurityMode _mode;

  /// Private constructor for SecureCookie.
  SecureCookie._(this._hmacKey, this._aesKey, this._mode);

  /// Creates a cookie protector with the supplied key and security mode.
  ///
  /// [key] may be a base64 string (optionally prefixed with `base64:`) or a
  /// [Uint8List]. When omitted, `APP_KEY` is used when available; otherwise a
  /// random key is generated. AES modes require at least 32 key bytes. When
  /// [mode] is omitted, [useEncryption] and [useSigning] select the mode, or
  /// both protections are enabled when neither flag is set.
  factory SecureCookie({
    dynamic key,
    SecurityMode? mode,
    bool useEncryption = false,
    bool useSigning = false,
  }) {
    final effectiveMode =
        mode ??
        (useEncryption && useSigning
            ? SecurityMode.both
            : useEncryption
            ? SecurityMode.aesOnly
            : useSigning
            ? SecurityMode.hmacOnly
            : SecurityMode.both);

    final keyBytes = key != null
        ? (key is String
              ? base64.decode(key.replaceFirst('base64:', ''))
              : key as Uint8List)
        : _generateKeyFromEnv();

    if (effectiveMode != SecurityMode.hmacOnly && keyBytes.length < 32) {
      throw ArgumentError('Key must be at least 32 bytes for AES encryption');
    }

    final hmacKey =
        (effectiveMode == SecurityMode.hmacOnly ||
            effectiveMode == SecurityMode.both)
        ? keyBytes
        : null;

    final aesKey =
        (effectiveMode == SecurityMode.aesOnly) ||
            (effectiveMode == SecurityMode.both)
        ? Uint8List.fromList(keyBytes.sublist(0, 32))
        : null;

    return SecureCookie._(hmacKey, aesKey, effectiveMode);
  }

  static List<int> _generateKeyFromEnv() {
    final appKey = Platform.environment['APP_KEY'];
    if (appKey != null && appKey.isNotEmpty) {
      return base64.decode(appKey.replaceFirst('base64:', ''));
    }
    return _generateRandomKeyBytes();
  }

  /// Generates a base64-prefixed, cryptographically random key.
  ///
  /// The result is suitable for passing as [SecureCookie.key].
  static String generateKey() {
    return 'base64:${base64.encode(_generateRandomKeyBytes())}';
  }

  static List<int> _generateRandomKeyBytes([int length = 64]) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  /// Encodes [values] for the cookie named [name].
  ///
  /// The output is URL-safe base64. The cookie name is bound to the
  /// authentication or encryption operation, so it must be unchanged when
  /// [decode] is called.
  String encode(String name, Map<String, dynamic> values) {
    final payload = jsonEncode(values);

    switch (_mode) {
      case SecurityMode.hmacOnly:
        return _encodeHmacOnly(payload, name);
      case SecurityMode.aesOnly:
        return _encodeAesOnly(payload, name);
      case SecurityMode.both:
        return _encodeWithBoth(payload, name);
    }
  }

  /// Decodes a protected cookie value for [name].
  ///
  /// Throws when [cookieValue] is malformed, tampered with, encrypted with a
  /// different key, or bound to another cookie name.
  Map<String, dynamic> decode(String name, String cookieValue) {
    final decodedBytes = base64Url.decode(cookieValue);
    final decodedStr = utf8.decode(decodedBytes);

    switch (_mode) {
      case SecurityMode.hmacOnly:
        return _decodeHmacOnly(decodedStr, name);
      case SecurityMode.aesOnly:
        return _decodeAesOnly(decodedStr, name);
      case SecurityMode.both:
        return _decodeWithBoth(decodedStr, name);
    }
  }

  String _encodeHmacOnly(String payload, String name) {
    if (_hmacKey == null) throw StateError('HMAC not initialized');
    final signature = _sign(payload, name);
    return base64Url.encode(utf8.encode('$payload|$signature'));
  }

  String _encodeAesOnly(String payload, String name) {
    if (_aesKey == null) throw StateError('Encrypter not initialized');
    final iv = _secureRandomBytes(12);
    final encryptedBytes = _encryptAesGcm(
      _aesKey,
      iv,
      utf8.encode(payload),
      name,
    );
    return base64Url.encode(
      utf8.encode('${base64.encode(encryptedBytes)}|${base64.encode(iv)}'),
    );
  }

  String _encodeWithBoth(String payload, String name) {
    if (_aesKey == null) throw StateError('Encrypter not initialized');
    if (_hmacKey == null) throw StateError('HMAC not initialized');

    final iv = _secureRandomBytes(12);
    final encryptedBytes = _encryptAesGcm(
      _aesKey,
      iv,
      utf8.encode(payload),
      name,
    );
    final combined = '${base64.encode(encryptedBytes)}|${base64.encode(iv)}';
    final signature = _sign(combined, name);

    return base64Url.encode(utf8.encode('$combined|$signature'));
  }

  Map<String, dynamic> _decodeHmacOnly(String decodedStr, String name) {
    if (_hmacKey == null) throw StateError('HMAC not initialized');

    final parts = decodedStr.split('|');
    if (parts.length != 2) {
      throw Exception('Invalid cookie format');
    }

    final payload = parts[0];
    final signature = parts[1];

    if (!_verify(payload, signature, name)) {
      throw Exception('Signature mismatch');
    }

    final dynamic decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'value': decoded};
  }

  Map<String, dynamic> _decodeAesOnly(String decodedStr, String name) {
    if (_aesKey == null) throw StateError('Encrypter not initialized');

    final parts = decodedStr.split('|');
    if (parts.length != 2) {
      throw Exception('Invalid cookie format');
    }

    final encryptedData = parts[0];
    final ivString = parts[1];

    final iv = base64.decode(ivString);
    final encrypted = base64.decode(encryptedData);
    final decrypted = _decryptAesGcm(_aesKey, iv, encrypted, name);

    final dynamic decoded = jsonDecode(decrypted);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'value': decoded};
  }

  Map<String, dynamic> _decodeWithBoth(String decodedStr, String name) {
    if (_aesKey == null) throw StateError('Encrypter not initialized');
    if (_hmacKey == null) throw StateError('HMAC not initialized');

    final parts = decodedStr.split('|');
    if (parts.length != 3) {
      throw Exception('Invalid cookie format');
    }

    final encryptedData = parts[0];
    final ivString = parts[1];
    final signature = parts[2];

    final combined = '$encryptedData|$ivString';
    if (!_verify(combined, signature, name)) {
      throw Exception('Signature mismatch');
    }

    final iv = base64.decode(ivString);
    final encrypted = base64.decode(encryptedData);
    final decrypted = _decryptAesGcm(_aesKey, iv, encrypted, name);

    final dynamic decoded = jsonDecode(decrypted);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'value': decoded};
  }

  /// Signs the [payload] bound to the [name] of the cookie so a value produced
  /// for one cookie name is never accepted under a different name.
  String _sign(String payload, String name) {
    if (_hmacKey == null) throw StateError('HMAC not initialized');
    final bytes = utf8.encode('$name|$payload');
    final mac = crypto.Hmac(crypto.sha256, _hmacKey).convert(bytes);
    return base64Url.encode(mac.bytes);
  }

  bool _verify(String payload, String signature, String name) {
    final expectedSig = _sign(payload, name);
    return _constantTimeEquals(signature, expectedSig);
  }

  bool _constantTimeEquals(String a, String b) {
    final aBytes = a.codeUnits;
    final bBytes = b.codeUnits;
    if (aBytes.length != bBytes.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < aBytes.length; i++) {
      diff |= aBytes[i] ^ bBytes[i];
    }
    return diff == 0;
  }

  List<int> _secureRandomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  List<int> _encryptAesGcm(
    Uint8List key,
    List<int> iv,
    List<int> plaintext,
    String name,
  ) {
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(key),
      128,
      Uint8List.fromList(iv),
      // Bind the cookie name as associated (authenticated) data so ciphertext
      // produced for one cookie name is rejected under another.
      Uint8List.fromList(utf8.encode(name)),
    );
    cipher.init(true, params);
    return cipher.process(Uint8List.fromList(plaintext));
  }

  String _decryptAesGcm(
    Uint8List key,
    List<int> iv,
    List<int> ciphertext,
    String name,
  ) {
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(key),
      128,
      Uint8List.fromList(iv),
      Uint8List.fromList(utf8.encode(name)),
    );
    cipher.init(false, params);
    final decrypted = cipher.process(Uint8List.fromList(ciphertext));
    return utf8.decode(decrypted);
  }
}

/// The security mode to use for cookie protection.
enum SecurityMode {
  /// Only sign the data with HMAC.
  hmacOnly,

  /// Only encrypt the data with AES.
  aesOnly,

  /// Both encrypt and sign the data (most secure).
  both,
}
