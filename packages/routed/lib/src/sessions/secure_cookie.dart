import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart' show AEADParameters, KeyParameter;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:routed/routed.dart';
import 'package:routed/src/crypto/crypto.dart';

/// A secure cookie implementation supporting both HMAC signing and AES encryption.
/// Provides three security modes:
/// - HMAC only: Signs data to prevent tampering
/// - AES only: Encrypts data for confidentiality
/// - Both: Combines encryption and signing for maximum security
class SecureCookie {
  final List<int>? _hmacKey;
  final Uint8List? _aesKey;
  final SecurityMode _mode;

  /// Private constructor for SecureCookie.
  SecureCookie._(this._hmacKey, this._aesKey, this._mode);

  /// Factory constructor to create a new SecureCookie with the provided key and security mode.
  ///
  /// [key] - The base64 encoded key (should be at least 32 bytes for AES) or Uint8List
  /// [mode] - The security mode to use (defaults to both encryption and signing)
  factory SecureCookie({
    dynamic key,
    SecurityMode? mode,
    bool useEncryption = false,
    bool useSigning = false,
  }) {
    // Determine mode based on encryption/signing flags
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

    // Ensure key is long enough for selected mode
    if (effectiveMode != SecurityMode.hmacOnly && keyBytes.length < 32) {
      throw ArgumentError('Key must be at least 32 bytes for AES encryption');
    }

    // Create HMAC if needed
    final hmacKey =
        (effectiveMode == SecurityMode.hmacOnly ||
            effectiveMode == SecurityMode.both)
        ? keyBytes
        : null;

    // Create AES encrypter if needed
    final aesKey =
        (effectiveMode == SecurityMode.aesOnly) ||
            (effectiveMode == SecurityMode.both)
        ? Uint8List.fromList(keyBytes.sublist(0, 32))
        : null;

    return SecureCookie._(hmacKey, aesKey, effectiveMode);
  }

  static List<int> _generateKeyFromEnv() {
    final appKey = env['APP_KEY'];
    if (appKey != null) {
      return base64.decode((appKey).replaceFirst('base64:', ''));
    }
    return _generateRandomKeyBytes();
  }

  static String generateKey() {
    return 'base64:${base64.encode(_generateRandomKeyBytes())}';
  }

  static List<int> _generateRandomKeyBytes([int length = 64]) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  /// Encode session values into a secured string based on the security mode.
  String encode(String name, Map<String, dynamic> values) {
    final payload = jsonEncode(values);

    switch (_mode) {
      case SecurityMode.hmacOnly:
        return _encodeHmacOnly(payload);
      case SecurityMode.aesOnly:
        return _encodeAesOnly(payload);
      case SecurityMode.both:
        return _encodeWithBoth(payload);
    }
  }

  /// Decode a secured string back into session values.
  Map<String, dynamic> decode(String name, String cookieValue) {
    try {
      final decodedBytes = base64Url.decode(cookieValue);
      final decodedStr = utf8.decode(decodedBytes);

      switch (_mode) {
        case SecurityMode.hmacOnly:
          return _decodeHmacOnly(decodedStr);
        case SecurityMode.aesOnly:
          return _decodeAesOnly(decodedStr);
        case SecurityMode.both:
          return _decodeWithBoth(decodedStr);
      }
    } catch (e) {
      rethrow;
    }
  }

  String _encodeHmacOnly(String payload) {
    if (_hmacKey == null) throw StateError('HMAC not initialized');
    final signature = _sign(payload);
    return base64Url.encode(utf8.encode('$payload|$signature'));
  }

  String _encodeAesOnly(String payload) {
    if (_aesKey == null) throw StateError('Encrypter not initialized');
    // GCM prefers a 12-byte nonce/IV
    final iv = _secureRandomBytes(12);
    final encryptedBytes = _encryptAesGcm(_aesKey, iv, utf8.encode(payload));
    return base64Url.encode(
      utf8.encode('${base64.encode(encryptedBytes)}|${base64.encode(iv)}'),
    );
  }

  String _encodeWithBoth(String payload) {
    if (_aesKey == null) throw StateError('Encrypter not initialized');
    if (_hmacKey == null) throw StateError('HMAC not initialized');

    // GCM prefers a 12-byte nonce/IV
    final iv = _secureRandomBytes(12);
    final encryptedBytes = _encryptAesGcm(_aesKey, iv, utf8.encode(payload));
    final combined = '${base64.encode(encryptedBytes)}|${base64.encode(iv)}';
    final signature = _sign(combined);

    return base64Url.encode(utf8.encode('$combined|$signature'));
  }

  Map<String, dynamic> _decodeHmacOnly(String decodedStr) {
    if (_hmacKey == null) throw StateError('HMAC not initialized');

    final parts = decodedStr.split('|');
    if (parts.length != 2) {
      throw Exception('Invalid cookie format');
    }

    final payload = parts[0];
    final signature = parts[1];

    if (!_verify(payload, signature)) {
      throw Exception('Signature mismatch');
    }

    final dynamic decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'value': decoded};
  }

  Map<String, dynamic> _decodeAesOnly(String decodedStr) {
    if (_aesKey == null) throw StateError('Encrypter not initialized');

    final parts = decodedStr.split('|');
    if (parts.length != 2) {
      throw Exception('Invalid cookie format');
    }

    final encryptedData = parts[0];
    final ivString = parts[1];

    final iv = base64.decode(ivString);
    final encrypted = base64.decode(encryptedData);
    final decrypted = _decryptAesGcm(_aesKey, iv, encrypted);

    final dynamic decoded = jsonDecode(decrypted);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'value': decoded};
  }

  Map<String, dynamic> _decodeWithBoth(String decodedStr) {
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
    if (!_verify(combined, signature)) {
      throw Exception('Signature mismatch');
    }

    final iv = base64.decode(ivString);
    final encrypted = base64.decode(encryptedData);
    final decrypted = _decryptAesGcm(_aesKey, iv, encrypted);

    final dynamic decoded = jsonDecode(decrypted);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'value': decoded};
  }

  String _sign(String payload) {
    if (_hmacKey == null) throw StateError('HMAC not initialized');
    final bytes = utf8.encode(payload);
    final mac = hmacSha256(_hmacKey, bytes);
    return base64Url.encode(mac);
  }

  bool _verify(String payload, String signature) {
    final expectedSig = _sign(payload);
    return constantTimeEquals(signature, expectedSig);
  }

  bool constantTimeEquals(String a, String b) {
    return constantTimeEqualsBytes(a.codeUnits, b.codeUnits);
  }

  List<int> _secureRandomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  List<int> _encryptAesGcm(Uint8List key, List<int> iv, List<int> plaintext) {
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(key),
      128,
      Uint8List.fromList(iv),
      Uint8List(0),
    );
    cipher.init(true, params);
    return cipher.process(Uint8List.fromList(plaintext));
  }

  String _decryptAesGcm(Uint8List key, List<int> iv, List<int> ciphertext) {
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(key),
      128,
      Uint8List.fromList(iv),
      Uint8List(0),
    );
    cipher.init(false, params);
    final decrypted = cipher.process(Uint8List.fromList(ciphertext));
    return utf8.decode(decrypted);
  }
}

/// The security mode to use for cookie protection
enum SecurityMode {
  /// Only sign the data with HMAC
  hmacOnly,

  /// Only encrypt the data with AES
  aesOnly,

  /// Both encrypt and sign the data (most secure)
  both,
}
