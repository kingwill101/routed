import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('PasswordPolicy', () {
    const policy = PasswordPolicy();

    test('defaults to a length-first registration policy', () {
      expect(policy.validateRegistration('short'), 'password_too_short');
      expect(policy.validateRegistration('twelve chars'), isNull);
      expect(policy.validateRegistration('a' * 1025), 'password_too_long');
    });

    test('allows legacy short passwords to authenticate', () {
      expect(policy.allowsAuthentication('short'), isTrue);
      expect(policy.allowsAuthentication('a' * 1025), isFalse);
    });

    test('supports a stricter application policy', () {
      const strict = PasswordPolicy(minimumLength: 20, maximumLength: 64);
      expect(strict.validateRegistration('a' * 19), 'password_too_short');
      expect(strict.validateRegistration('a' * 20), isNull);
      expect(strict.validateRegistration('a' * 65), 'password_too_long');
    });
  });

  test('built-in registration refuses weak passwords before hashing', () async {
    final hasher = _CountingHasher();
    final result = await authorizeCredentialsRegistration(
      store: InMemoryAuthStore(),
      passwordHasher: hasher,
      provider: CredentialsProvider(),
      context: Object(),
      credentials: AuthCredentials(
        email: 'user@example.com',
        password: 'short',
      ),
    );

    expect(result, isNull);
    expect(hasher.hashCalls, isZero);
  });

  test('built-in sign-in skips oversized verifier input', () async {
    final hasher = _CountingHasher();
    final result = await authorizeCredentialsSignIn(
      store: InMemoryAuthStore(),
      passwordHasher: hasher,
      provider: CredentialsProvider(),
      context: Object(),
      credentials: AuthCredentials(
        email: 'user@example.com',
        password: 'a' * 1025,
      ),
    );

    expect(result, isNull);
    expect(hasher.verifyCalls, isZero);
  });
}

class _CountingHasher implements PasswordHasher {
  int hashCalls = 0;
  int verifyCalls = 0;

  @override
  String hash(String password) {
    hashCalls++;
    return 'test-hash';
  }

  @override
  PasswordVerification verify(String password, String encodedHash) {
    verifyCalls++;
    return const PasswordVerification(matches: false, needsRehash: false);
  }
}
