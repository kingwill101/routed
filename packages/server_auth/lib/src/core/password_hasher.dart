import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/key_derivators/argon2.dart';
import 'package:pointycastle/key_derivators/api.dart';

/// Result of verifying a password against a stored password hash.
class PasswordVerification {
  const PasswordVerification({
    required this.matches,
    required this.needsRehash,
  });

  /// Whether the supplied password matches the stored hash.
  final bool matches;

  /// Whether the matching hash uses parameters older than the current policy.
  final bool needsRehash;
}

/// Contract for password hashing and verification policies.
///
/// Implementations must return a self-contained encoded hash from [hash]. The
/// encoded value must include the algorithm/version and parameters required to
/// verify it later. Implementations must not return or persist plaintext
/// passwords.
abstract interface class PasswordHasher {
  String hash(String password);

  PasswordVerification verify(String password, String encodedHash);
}

/// Argon2id password hashing policy backed by PointyCastle.
///
/// The encoded format is:
///
/// `routed-argon2id$v=1$i=2$m=19456$p=1$l=32$s=<salt>$h=<derived-key>`
///
/// Salt and derived-key values use unpadded base64url encoding. The format is
/// self-describing so parameter upgrades can be detected during login.
class Argon2idPasswordHasher implements PasswordHasher {
  Argon2idPasswordHasher({
    this.iterations = 2,
    this.memoryKiB = 19456,
    this.parallelism = 1,
    this.saltLength = 16,
    this.derivedKeyLength = 32,
    List<int> Function(int length)? saltGenerator,
  }) : _saltGenerator = saltGenerator ?? _secureRandomBytes {
    if (iterations < 1 || iterations > 100) {
      throw ArgumentError.value(iterations, 'iterations');
    }
    if (memoryKiB < 8 || memoryKiB > 1024 * 1024) {
      throw ArgumentError.value(memoryKiB, 'memoryKiB');
    }
    if (parallelism < 1 || parallelism > 32) {
      throw ArgumentError.value(parallelism, 'parallelism');
    }
    if (memoryKiB < parallelism * 8) {
      throw ArgumentError.value(
        memoryKiB,
        'memoryKiB',
        'must be at least eight KiB per lane',
      );
    }
    if (saltLength < 16 || saltLength > 1024) {
      throw ArgumentError.value(saltLength, 'saltLength');
    }
    if (derivedKeyLength < 16 || derivedKeyLength > 1024) {
      throw ArgumentError.value(derivedKeyLength, 'derivedKeyLength');
    }
  }

  /// Argon2 passes used for newly created hashes.
  final int iterations;

  /// Argon2 memory cost in KiB for newly created hashes.
  final int memoryKiB;

  /// Argon2 lanes used for newly created hashes.
  final int parallelism;

  /// Number of random salt bytes used for newly created hashes.
  final int saltLength;

  /// Number of derived-key bytes stored in newly created hashes.
  final int derivedKeyLength;

  final List<int> Function(int length) _saltGenerator;

  @override
  String hash(String password) {
    final salt = _saltGenerator(saltLength);
    if (salt.length != saltLength) {
      throw StateError('The password salt generator returned an invalid size');
    }
    final derivedKey = _deriveKey(password, salt);
    return [
      'routed-argon2id',
      'v=1',
      'i=$iterations',
      'm=$memoryKiB',
      'p=$parallelism',
      'l=$derivedKeyLength',
      's=${_base64UrlEncode(salt)}',
      'h=${_base64UrlEncode(derivedKey)}',
    ].join(r'$');
  }

  @override
  PasswordVerification verify(String password, String encodedHash) {
    final parsed = _ParsedArgon2idHash.tryParse(encodedHash);
    if (parsed == null) {
      return const PasswordVerification(matches: false, needsRehash: false);
    }
    final derivedKey = _deriveKey(
      password,
      parsed.salt,
      iterations: parsed.iterations,
      memoryKiB: parsed.memoryKiB,
      parallelism: parsed.parallelism,
      length: parsed.length,
    );
    final matches = _constantTimeEquals(derivedKey, parsed.derivedKey);
    return PasswordVerification(
      matches: matches,
      needsRehash:
          matches &&
          (parsed.iterations != iterations ||
              parsed.memoryKiB != memoryKiB ||
              parsed.parallelism != parallelism ||
              parsed.length != derivedKeyLength ||
              parsed.salt.length != saltLength),
    );
  }

  List<int> _deriveKey(
    String password,
    List<int> salt, {
    int? iterations,
    int? memoryKiB,
    int? parallelism,
    int? length,
  }) {
    final parameters = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      Uint8List.fromList(salt),
      iterations: iterations ?? this.iterations,
      memory: memoryKiB ?? this.memoryKiB,
      lanes: parallelism ?? this.parallelism,
      desiredKeyLength: length ?? derivedKeyLength,
      version: Argon2Parameters.ARGON2_VERSION_13,
    );
    final input = Uint8List.fromList(utf8.encode(password));
    final output = Uint8List(length ?? derivedKeyLength);
    final generator = Argon2BytesGenerator();
    try {
      generator.init(parameters);
      generator.deriveKey(input, 0, output, 0);
      return output;
    } finally {
      input.fillRange(0, input.length, 0);
      // PointyCastle's Argon2Parameters.clear() calls List.clear(), which is
      // unsupported by Uint8List. Zero the fixed-length salt in place instead.
      parameters.salt.fillRange(0, parameters.salt.length, 0);
    }
  }
}

class _ParsedArgon2idHash {
  const _ParsedArgon2idHash({
    required this.iterations,
    required this.memoryKiB,
    required this.parallelism,
    required this.length,
    required this.salt,
    required this.derivedKey,
  });

  final int iterations;
  final int memoryKiB;
  final int parallelism;
  final int length;
  final List<int> salt;
  final List<int> derivedKey;

  static _ParsedArgon2idHash? tryParse(String encoded) {
    final parts = encoded.split(r'$');
    if (parts.length != 8 || parts[0] != 'routed-argon2id') {
      return null;
    }
    final values = <String, String>{};
    for (final part in parts.skip(1)) {
      final separator = part.indexOf('=');
      if (separator <= 0 || values.containsKey(part.substring(0, separator))) {
        return null;
      }
      values[part.substring(0, separator)] = part.substring(separator + 1);
    }
    if (values.length != 7 || values['v'] != '1') {
      return null;
    }
    final iterations = int.tryParse(values['i'] ?? '');
    final memoryKiB = int.tryParse(values['m'] ?? '');
    final parallelism = int.tryParse(values['p'] ?? '');
    final length = int.tryParse(values['l'] ?? '');
    if (iterations == null ||
        iterations < 1 ||
        iterations > 100 ||
        memoryKiB == null ||
        memoryKiB < 8 ||
        memoryKiB > 1024 * 1024 ||
        parallelism == null ||
        parallelism < 1 ||
        parallelism > 32 ||
        memoryKiB < parallelism * 8 ||
        length == null ||
        length < 16 ||
        length > 1024) {
      return null;
    }
    try {
      final salt = _base64UrlDecode(values['s'] ?? '');
      final derivedKey = _base64UrlDecode(values['h'] ?? '');
      if (salt.length < 16 ||
          salt.length > 1024 ||
          derivedKey.length != length) {
        return null;
      }
      return _ParsedArgon2idHash(
        iterations: iterations,
        memoryKiB: memoryKiB,
        parallelism: parallelism,
        length: length,
        salt: salt,
        derivedKey: derivedKey,
      );
    } on FormatException {
      return null;
    }
  }
}

String _base64UrlEncode(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

List<int> _base64UrlDecode(String value) {
  final padding = (4 - value.length % 4) % 4;
  return base64Url.decode('$value${'=' * padding}');
}

List<int> _secureRandomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(
    length,
    (_) => random.nextInt(256),
    growable: false,
  );
}

bool _constantTimeEquals(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final length = min(left.length, right.length);
  for (var i = 0; i < length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}
