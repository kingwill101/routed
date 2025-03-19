import 'dart:math';
import 'property_test.dart';

/// A utility class that provides convenient generators for common data types.
class Any {
  /// Generates random integer values between [min] (inclusive) and [max] (exclusive).
  ///
  /// The generated values can be shrunk towards [min] and [value/2].
  static Generator<int> integer({int min = 0, int max = 100}) {
    return (Random random, int size) {
      final value = min + random.nextInt(max - min);
      return DataShape(value, shrinkValues: [min, value ~/ 2]);
    };
  }

  /// Generates random double values between [min] (inclusive) and [max] (exclusive).
  ///
  /// The value can be shrunk towards [min] and half its size.
  static Generator<double> doubleVal({double min = 0, double max = 100}) {
    return (Random random, int size) {
      final value = min + random.nextDouble() * (max - min);
      return DataShape(value, shrinkValues: [min, value / 2]);
    };
  }

  /// Generates random booleans.
  static Generator<bool> boolean() {
    return (Random random, int size) {
      final value = random.nextBool();
      return DataShape(value);
    };
  }

  /// Generates random strings of length up to [maxLength].
  ///
  /// The strings contain only uppercase ASCII letters by default. Generated values can be
  /// shrunk to empty string or half length.
  static Generator<String> string({
    int maxLength = 10,
    String charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
  }) {
    return (Random random, int size) {
      final length = random.nextInt(maxLength);
      final chars = List.generate(
          length, (_) => charset[random.nextInt(charset.length)]);
      return DataShape(chars.join(),
          shrinkValues: ['', chars.take(length ~/ 2).join()]);
    };
  }

  /// Generates random phone numbers in the format "XXX-XXX-XXXX".
  ///
  /// Area codes range from 100-999, prefixes from 100-999, and line numbers from 1000-9999.
  static Generator<String> phone() {
    return (random, size) {
      final areaCode = random.nextInt(900) + 100;
      final prefix = random.nextInt(900) + 100;
      final line = random.nextInt(9000) + 1000;
      return DataShape('$areaCode-$prefix-$line');
    };
  }

  /// Generates random digits between [min] (inclusive) and [max] (exclusive).
  static Generator<int> randomDigit({int min = 0, int max = 100}) {
    return (random, size) {
      return DataShape(min + random.nextInt(max - min));
    };
  }

  /// Generates a potentially valid (but randomized) email address.
  static Generator<String> email() {
    return (random, size) {
      final domains = ['gmail.com', 'yahoo.com', 'example.com', 'test.org', 'company.co'];
      final usernameLength = 3 + random.nextInt(10);
      final username = string(
        maxLength: usernameLength,
        charset: 'abcdefghijklmnopqrstuvwxyz0123456789._',
      )(random, size).value;
      final domain = domains[random.nextInt(domains.length)];
      return DataShape('$username@$domain');
    };
  }

  /// Generates a random UUID v4 string.
  static Generator<String> uuid() {
    return (random, size) {
      final char = '0123456789abcdef';
      final sections = [8, 4, 4, 4, 12]; // UUID format sections
      final uuid = sections
          .map((length) => List.generate(
          length, (_) => char[random.nextInt(char.length)]).join())
          .join('-');
      return DataShape(uuid);
    };
  }

  /// Generates a random IPv4 address.
  static Generator<String> ipv4() {
    return (random, size) {
      final segments = List.generate(4, (_) => random.nextInt(256)).join('.');
      return DataShape(segments);
    };
  }

  /// Generates a random IPv6 address.
  static Generator<String> ipv6() {
    return (random, size) {
      final segments = List.generate(
          8, (_) => random.nextInt(0x10000).toRadixString(16).padLeft(1, '0'));
      return DataShape(segments.join(':'));
    };
  }

  /// Generates a random MAC address.
  static Generator<String> macAddress() {
    return (random, size) {
      final segments = List.generate(
          6,
              (_) => random.nextInt(256)
              .toRadixString(16)
              .padLeft(2, '0'));
      return DataShape(segments.join(':'));
    };
  }

  /// Generates a random JSON object with [numFields] properties.
  static Generator<Map<String, dynamic>> jsonObject({int numFields = 5}) {
    return (random, size) {
      final result = <String, dynamic>{};
      for (var i = 0; i < numFields; i++) {
        final key = string(maxLength: 10)(random, size).value;
        // Randomly choose a value type
        final valueType = random.nextInt(4);
        dynamic value;
        switch (valueType) {
          case 0:
            value = string()(random, size).value;
            break;
          case 1:
            value = integer()(random, size).value;
            break;
          case 2:
            value = random.nextBool();
            break;
          case 3:
            value = null;
            break;
        }
        result[key] = value;
      }
      return DataShape(result);
    };
  }

  /// Generates a random URL.
  static Generator<String> url({bool includeParams = true}) {
    return (random, size) {
      final protocols = ['http', 'https'];
      final domains = ['example.com', 'test.org', 'api.site.io'];
      final paths = ['', 'users', 'api/v1', 'products', 'search'];

      final protocol = protocols[random.nextInt(protocols.length)];
      final domain = domains[random.nextInt(domains.length)];
      final path = paths[random.nextInt(paths.length)];

      String url = '$protocol://$domain/$path';

      if (includeParams && random.nextBool()) {
        final params = <String>[];
        final numParams = 1 + random.nextInt(3);
        for (var i = 0; i < numParams; i++) {
          final key = string(maxLength: 8)(random, size).value.toLowerCase();
          final value = string(maxLength: 10)(random, size).value;
          params.add('$key=$value');
        }
        url += '?${params.join('&')}';
      }

      return DataShape(url);
    };
  }

  /// Generates a random file path.
  static Generator<String> filePath() {
    return (random, size) {
      final segments = ['usr', 'bin', 'lib', 'var', 'home', 'temp'];
      final pathSegments = List.generate(random.nextInt(5) + 1,
              (_) => segments[random.nextInt(segments.length)]);
      return DataShape('/${pathSegments.join('/')}');
    };
  }

  /// Generates a random DateTime between [start] and [end].
  static Generator<DateTime> dateTime({DateTime? start, DateTime? end}) {
    return (random, size) {
      start ??= DateTime(1970);
      end ??= DateTime.now();
      final diff = end?.difference(start!).inMilliseconds;
      final offset = random.nextInt(diff!);
      final dt = start?.add(Duration(milliseconds: offset));
      return DataShape(dt!);
    };
  }

  /// Generates a random password with a mix of letters, digits, and symbols.
  static Generator<String> password({int length = 12}) {
    return (random, size) {
      const charset =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()_+-=[]{}|;';
      final pwd = List.generate(
          length, (_) => charset[random.nextInt(charset.length)])
          .join();
      return DataShape(pwd);
    };
  }

  /// Generates a random credit card number (16 digits).
  static Generator<String> creditCard() {
    return (random, size) {
      final cardNumber = List.generate(16, (_) => random.nextInt(10)).join();
      return DataShape(cardNumber);
    };
  }

  /// Generates a random list of type [T] using the provided [generator].
  ///
  /// The list length is randomly determined up to [maxLength].
  static Generator<List<T>> listOf<T>(Generator<T> generator, {int maxLength = 10}) {
    return (Random random, int size) {
      final length = random.nextInt(maxLength);
      final list = List.generate(length, (_) => generator(random, size).value);
      return DataShape(list);
    };
  }

  /// Generates a random enum value from the provided [values].
  static Generator<T> enumValue<T>(List<T> values) {
    return (Random random, int size) {
      final value = values[random.nextInt(values.length)];
      return DataShape(value);
    };
  }
}

/// A class that generates chaotic string inputs for testing edge cases and security issues.
class ChaoticString {
  /// Common SQL injection attack strings.
  static final _sqlInjections = [
    "' OR '1'='1",
    "; DROP TABLE users;",
    "' UNION SELECT * FROM users--",
  ];

  /// Common XSS attack payloads.
  static final _xssPayloads = [
    "<script>alert('xss')</script>",
    "javascript:alert(1)",
    "<img src=x onerror=alert('XSS')>",
  ];

  /// Path traversal attack strings.
  static final _pathTraversals = [
    "../../../etc/passwd",
    "..\\..\\windows\\system32",
    "%2e%2e%2f%2e%2e%2f",
  ];

  /// Command injection attack strings.
  static final _commandInjections = [
    r'$(rm -rf /)',
    '`; shutdown -h now`',
    '| cat /etc/passwd',
  ];

  /// LDAP injection attack strings.
  static final _ldapInjections = [
    '*)(uid=*))(|(uid=*',
  ];

  /// URL attack payloads.
  static final _urlAttackPayloads = [
    'http://127.0.0.1:80/evil',
    'https://evil.com/?q=<script>alert(1)</script>',
  ];

  /// Unicode special characters and emojis.
  static final _specialChars = [
    "☺☻♥♦♣♠•◘○",
    "ᾢᾣᾤᾥᾦᾧᾨᾩᾪ",
    "🎈🎉🎊🎋🎌🎍🎎🎏",
  ];

  /// Generates chaotic string inputs combining various attack vectors and edge cases.
  ///
  /// The generated strings may include SQL injection attempts, XSS payloads, path traversals,
  /// command injections, LDAP injections, special characters, null bytes, control characters,
  /// URL encoded chaos, and mixed-case irregularities.
  ///
  /// [maxLength] controls the maximum length of randomly generated filler strings.
  static Generator<String> chaotic({int maxLength = 100}) {
    return (random, size) {
      final attacks = [
        ..._sqlInjections,
        ..._xssPayloads,
        ..._pathTraversals,
        ..._commandInjections,
        ..._ldapInjections,
        ..._urlAttackPayloads,
        ..._specialChars,
        // Add a random long string
        'A' * random.nextInt(maxLength),
        // Add a null byte injection
        'before\x00after',
        // Add control characters
        String.fromCharCodes(List.generate(16, (i) => i)),
        // URL encoded chaos
        '%00%01%02%03',
        // Mixed case weirdness
        'UpperLowerUpperLower'
            .split('')
            .map((c) => random.nextBool() ? c.toUpperCase() : c.toLowerCase())
            .join(),
      ];

      // Randomly combine multiple attacks or choose one.
      if (random.nextBool()) {
        final numAttacks = random.nextInt(3) + 1;
        final selectedAttacks = List.generate(
            numAttacks, (_) => attacks[random.nextInt(attacks.length)]);
        return DataShape(selectedAttacks.join());
      } else {
        return DataShape(attacks[random.nextInt(attacks.length)]);
      }
    };
  }
}
