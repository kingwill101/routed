import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('Argon2idPasswordHasher', () {
    late Argon2idPasswordHasher hasher;

    setUp(() {
      hasher = Argon2idPasswordHasher(
        iterations: 1,
        memoryKiB: 8,
        derivedKeyLength: 16,
      );
    });

    test('hashes and verifies passwords without embedding plaintext', () {
      const password = 'correct horse battery staple';
      final encoded = hasher.hash(password);

      expect(encoded, startsWith(r'routed-argon2id$v=1$'));
      expect(encoded, isNot(contains(password)));
      expect(hasher.verify(password, encoded).matches, isTrue);
      expect(
        hasher.verify('incorrect horse battery staple', encoded).matches,
        isFalse,
      );
    });

    test('uses a different salt for each password hash', () {
      final first = hasher.hash('same password');
      final second = hasher.hash('same password');

      expect(first, isNot(equals(second)));
      expect(hasher.verify('same password', first).matches, isTrue);
      expect(hasher.verify('same password', second).matches, isTrue);
    });

    test('rejects malformed or unsafe encoded hashes without throwing', () {
      for (final encoded in <String>[
        '',
        'not-a-hash',
        r'routed-pbkdf2-sha256$v=1$i=1$l=16$s=abc$h=def',
        r'routed-argon2id$v=1$i=0$m=8$p=1$l=16$s=abc$h=def',
        r'routed-argon2id$v=1$i=1$m=999999999$p=1$l=16$s=abc$h=def',
      ]) {
        final result = hasher.verify('password', encoded);
        expect(result.matches, isFalse, reason: encoded);
        expect(result.needsRehash, isFalse, reason: encoded);
      }
    });

    test('marks hashes with an older policy for rehash', () {
      final oldHasher = Argon2idPasswordHasher(
        iterations: 1,
        memoryKiB: 8,
        derivedKeyLength: 16,
      );
      final currentHasher = Argon2idPasswordHasher(
        iterations: 2,
        memoryKiB: 16,
        derivedKeyLength: 32,
      );
      final result = currentHasher.verify(
        'password',
        oldHasher.hash('password'),
      );

      expect(result.matches, isTrue);
      expect(result.needsRehash, isTrue);
    });

    test('rejects invalid policy parameters', () {
      expect(() => Argon2idPasswordHasher(memoryKiB: 7), throwsArgumentError);
      expect(
        () => Argon2idPasswordHasher(parallelism: 2, memoryKiB: 15),
        throwsArgumentError,
      );
    });
  });
}
