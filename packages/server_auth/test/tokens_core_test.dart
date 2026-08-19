import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('secureRandomToken returns non-empty randomized values', () {
    final a = secureRandomToken();
    final b = secureRandomToken();

    expect(a, isNotEmpty);
    expect(b, isNotEmpty);
    expect(a, isNot(equals(b)));
  });

  test('secureRandomToken supports custom byte length', () {
    final short = secureRandomToken(length: 8);
    final long = secureRandomToken(length: 64);

    expect(short.length, lessThan(long.length));
  });

  test('base64UrlNoPadding removes trailing padding', () {
    final encoded = base64UrlNoPadding(<int>[255]);

    expect(encoded, equals('_w'));
    expect(encoded.contains('='), isFalse);
  });

  test('pkceS256CodeChallenge matches RFC 7636 example', () {
    const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
    final challenge = pkceS256CodeChallenge(verifier);

    expect(challenge, equals('E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'));
  });

  test('hashOpaqueToken is deterministic without preserving the raw token', () {
    const token = 'one-time-secret';

    final digest = hashOpaqueToken(token);

    expect(digest, isNotEmpty);
    expect(digest, isNot(contains(token)));
    expect(hashOpaqueToken(token), equals(digest));
    expect(hashOpaqueToken('different-secret'), isNot(equals(digest)));
  });

  test('constantTimeStringEquals compares equal and unequal secret values', () {
    expect(constantTimeStringEquals('same-secret', 'same-secret'), isTrue);
    expect(constantTimeStringEquals('same-secret', 'different'), isFalse);
    expect(
      constantTimeStringEquals('same-secret', 'same-secret-plus'),
      isFalse,
    );
  });

  test('verification tokens are consumed once and stored by digest', () async {
    var now = DateTime.utc(2026, 8, 19, 12);
    final store = InMemoryAuthVerificationTokenStore(clock: () => now);
    final token = AuthVerificationToken(
      identifier: 'user@example.com',
      token: 'magic-secret',
      expiresAt: now.add(const Duration(minutes: 5)),
    );

    await store.save(token);

    expect(
      (await store.consume(token.identifier, token.token))?.expiresAt,
      equals(token.expiresAt),
    );
    expect(await store.consume(token.identifier, token.token), isNull);

    await store.save(token);
    final results = await Future.wait([
      store.consume(token.identifier, token.token),
      store.consume(token.identifier, token.token),
    ]);
    expect(results.whereType<AuthVerificationToken>(), hasLength(1));

    now = now.add(const Duration(minutes: 6));
    await store.save(token);
    expect(await store.consume(token.identifier, token.token), isNull);
  });

  test('verification token store rejects empty values', () async {
    final store = InMemoryAuthVerificationTokenStore();
    final expiry = DateTime.utc(2026, 8, 19, 12);

    await expectLater(
      store.save(
        AuthVerificationToken(
          identifier: '',
          token: 'secret',
          expiresAt: expiry,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      store.save(
        AuthVerificationToken(
          identifier: 'user@example.com',
          token: '',
          expiresAt: expiry,
        ),
      ),
      throwsArgumentError,
    );
    expect(await store.consume('', 'secret'), isNull);
    expect(await store.consume('user@example.com', ''), isNull);
  });

  test('verification token store evicts oldest digests at capacity', () async {
    final now = DateTime.utc(2026, 8, 19, 12);
    final store = InMemoryAuthVerificationTokenStore(
      clock: () => now,
      maxTokens: 2,
    );
    for (final identifier in ['one@example.com', 'two@example.com']) {
      await store.save(
        AuthVerificationToken(
          identifier: identifier,
          token: 'token-$identifier',
          expiresAt: now.add(const Duration(minutes: 5)),
        ),
      );
    }
    await store.save(
      AuthVerificationToken(
        identifier: 'three@example.com',
        token: 'token-three@example.com',
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );

    expect(
      await store.consume('one@example.com', 'token-one@example.com'),
      isNull,
    );
    expect(
      await store.consume('two@example.com', 'token-two@example.com'),
      isNotNull,
    );
    expect(
      await store.consume('three@example.com', 'token-three@example.com'),
      isNotNull,
    );
  });
}
