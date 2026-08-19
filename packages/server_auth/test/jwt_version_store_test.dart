import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('in-memory JWT versions start at zero and rotate atomically', () async {
    final store = InMemoryAuthJwtVersionStore();

    expect(await store.current('user-1'), equals(0));
    expect(await store.rotate('user-1'), equals(1));
    expect(await store.current('user-1'), equals(1));
    expect(await store.rotate('user-1'), equals(2));
    expect(await store.current('user-1'), equals(2));
  });

  test(
    'JWT verification rejects a rotated version and accepts a new one',
    () async {
      final versions = InMemoryAuthJwtVersionStore();
      const sessionOptions = JwtSessionOptions(
        secret: 'version-test-secret',
        maxAge: Duration(hours: 1),
      );
      final token = issueAuthJwtToken(
        options: sessionOptions,
        claims: {
          'sub': 'user-1',
          authJwtVersionClaim: await versions.current('user-1'),
        },
      ).token;
      final verifier = JwtVerifier(
        options: sessionOptions.toVerifierOptions().copyWith(
          requiredClaims: const <String>['exp', 'sub', authJwtVersionClaim],
        ),
        validateClaims: (claims) async =>
            claims[authJwtVersionClaim] == await versions.current('user-1'),
      );

      expect((await verifier.verifyToken(token)).subject, equals('user-1'));
      await versions.rotate('user-1');
      expect(
        () => verifier.verifyToken(token),
        throwsA(
          isA<JwtAuthException>().having(
            (error) => error.message,
            'message',
            equals('claims_rejected'),
          ),
        ),
      );

      final freshToken = issueAuthJwtToken(
        options: sessionOptions,
        claims: {
          'sub': 'user-1',
          authJwtVersionClaim: await versions.current('user-1'),
        },
      ).token;
      expect(
        (await verifier.verifyToken(freshToken)).subject,
        equals('user-1'),
      );
    },
  );

  test('invalid JWT version store identifiers are rejected', () async {
    final store = InMemoryAuthJwtVersionStore();

    expect(() => store.current(' '), throwsArgumentError);
    expect(() => store.rotate(''), throwsArgumentError);
  });
}
