import 'dart:async';

import '../core/providers.dart';
import '../core/tokens.dart' show hashOpaqueToken;
import '../core/webauthn_store.dart';

typedef AuthWebAuthnStoreConformanceFactory =
    FutureOr<AuthWebAuthnStoreConformanceFixture> Function();

final class AuthWebAuthnStoreConformanceFixture {
  const AuthWebAuthnStoreConformanceFixture({
    required this.capabilities,
    this.dispose,
  });

  final AuthWebAuthnStoreCapabilities capabilities;
  final FutureOr<void> Function()? dispose;
}

final class AuthWebAuthnStoreConformanceFailure implements Exception {
  const AuthWebAuthnStoreConformanceFailure(this.caseId, this.cause);

  final String caseId;
  final Object cause;

  @override
  String toString() => 'AuthWebAuthnStoreConformanceFailure($caseId): $cause';
}

final class AuthWebAuthnStoreConformanceCase {
  const AuthWebAuthnStoreConformanceCase({
    required this.id,
    required this.description,
    required Future<void> Function() run,
  }) : _run = run;

  final String id;
  final String description;
  final Future<void> Function() _run;

  Future<void> run() => _run();
}

/// Reusable one-time, uniqueness, compare-and-set, and stateful WebAuthn
/// persistence contract.
final class AuthWebAuthnStoreConformanceSuite {
  AuthWebAuthnStoreConformanceSuite(this.createFixture);

  final AuthWebAuthnStoreConformanceFactory createFixture;

  List<AuthWebAuthnStoreConformanceCase> get cases => [
    _case(
      'challenge_one_time_binding',
      'Challenges are digest-bound and consumed exactly once.',
      _challengeOneTimeBinding,
    ),
    _case(
      'challenge_contention',
      'Concurrent challenge consumers produce exactly one winner.',
      _challengeContention,
    ),
    _case(
      'credential_unique',
      'Credential IDs are globally unique and owner-scoped.',
      _credentialUnique,
    ),
    _case(
      'credential_create_contention',
      'Concurrent duplicate credential creation commits once.',
      _credentialCreateContention,
    ),
    _case(
      'counter_compare_and_set',
      'Signature counters advance only from the expected value.',
      _counterCompareAndSet,
    ),
    _case(
      'counter_contention',
      'Concurrent counter updates produce exactly one winner.',
      _counterContention,
    ),
    _case(
      'stateful_lifecycle',
      'A stateful create, rename, counter, and delete model remains exact.',
      _statefulLifecycle,
    ),
  ];

  AuthWebAuthnStoreConformanceCase _case(
    String id,
    String description,
    Future<void> Function(AuthWebAuthnStoreConformanceFixture fixture) body,
  ) => AuthWebAuthnStoreConformanceCase(
    id: id,
    description: description,
    run: () => _withFixture(id, body),
  );

  Future<void> _withFixture(
    String id,
    Future<void> Function(AuthWebAuthnStoreConformanceFixture fixture) body,
  ) async {
    final fixture = await Future.sync(createFixture);
    try {
      await body(fixture);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AuthWebAuthnStoreConformanceFailure(id, error),
        stackTrace,
      );
    } finally {
      await Future.sync(() => fixture.dispose?.call());
    }
  }

  Future<void> _challengeOneTimeBinding(
    AuthWebAuthnStoreConformanceFixture fixture,
  ) async {
    final store = fixture.capabilities.webAuthnChallenges;
    final challenge = _challenge('binding');
    await store.save(challenge);
    _require(
      await store.consume(
            challengeHash: challenge.challengeHash,
            ceremony: challenge.ceremony,
            relyingPartyId: challenge.relyingPartyId,
            origin: 'https://other.example.com',
            userId: challenge.userId,
            now: _now,
          ) ==
          null,
      'mismatched origin consumed challenge',
    );
    final consumed = await store.consume(
      challengeHash: challenge.challengeHash,
      ceremony: challenge.ceremony,
      relyingPartyId: challenge.relyingPartyId,
      origin: challenge.origin,
      userId: challenge.userId,
      now: _now,
    );
    _require(
      consumed?.id == challenge.id,
      'matching challenge was not returned',
    );
    _require(
      await store.consume(
            challengeHash: challenge.challengeHash,
            ceremony: challenge.ceremony,
            relyingPartyId: challenge.relyingPartyId,
            origin: challenge.origin,
            userId: challenge.userId,
            now: _now,
          ) ==
          null,
      'challenge replay succeeded',
    );
  }

  Future<void> _challengeContention(
    AuthWebAuthnStoreConformanceFixture fixture,
  ) async {
    final store = fixture.capabilities.webAuthnChallenges;
    final challenge = _challenge('contended');
    await store.save(challenge);
    final results = await Future.wait([
      for (var index = 0; index < 16; index++)
        Future.sync(
          () => store.consume(
            challengeHash: challenge.challengeHash,
            ceremony: challenge.ceremony,
            relyingPartyId: challenge.relyingPartyId,
            origin: challenge.origin,
            userId: challenge.userId,
            now: _now,
          ),
        ),
    ]);
    _require(
      results.whereType<AuthWebAuthnChallenge>().length == 1,
      'not one winner',
    );
  }

  Future<void> _credentialUnique(
    AuthWebAuthnStoreConformanceFixture fixture,
  ) async {
    final store = fixture.capabilities.webAuthnAuthenticators;
    final credential = _credential('unique');
    await store.create(credential);
    await _requireThrows(() => store.create(credential));
    _require(
      (await store.listForUser('user-1')).single.credentialId ==
          credential.credentialId,
      'owner list drifted',
    );
    _require((await store.listForUser('user-2')).isEmpty, 'owner leaked');
    _require(
      !await store.deleteForUser('user-2', credential.credentialId),
      'foreign owner deleted credential',
    );
  }

  Future<void> _credentialCreateContention(
    AuthWebAuthnStoreConformanceFixture fixture,
  ) async {
    final store = fixture.capabilities.webAuthnAuthenticators;
    final credential = _credential('create-contention');
    final results = await Future.wait([
      for (var index = 0; index < 16; index++)
        Future.sync(() async {
          try {
            await store.create(credential);
            return true;
          } catch (_) {
            return false;
          }
        }),
    ]);
    _require(
      results.where((created) => created).length == 1,
      'duplicate committed',
    );
    _require((await store.listForUser('user-1')).length == 1, 'duplicate rows');
  }

  Future<void> _counterCompareAndSet(
    AuthWebAuthnStoreConformanceFixture fixture,
  ) async {
    final store = fixture.capabilities.webAuthnAuthenticators;
    final credential = _credential('counter', counter: 7);
    await store.create(credential);
    _require(
      await store.updateUsage(
            credentialId: credential.credentialId,
            expectedCounter: 7,
            newCounter: 8,
            lastUsedAt: _now.subtract(const Duration(seconds: 1)),
          ) ==
          null,
      'pre-creation usage time mutated record',
    );
    _require(
      await store.updateUsage(
            credentialId: credential.credentialId,
            expectedCounter: 6,
            newCounter: 8,
            lastUsedAt: _now.add(const Duration(minutes: 1)),
          ) ==
          null,
      'stale expected counter mutated record',
    );
    final updated = await store.updateUsage(
      credentialId: credential.credentialId,
      expectedCounter: 7,
      newCounter: 8,
      lastUsedAt: _now.add(const Duration(minutes: 1)),
    );
    _require(updated?.counter == 8, 'counter did not advance');
    _require(
      await store.updateUsage(
            credentialId: credential.credentialId,
            expectedCounter: 7,
            newCounter: 9,
            lastUsedAt: _now.add(const Duration(minutes: 2)),
          ) ==
          null,
      'replayed expected counter mutated record',
    );
  }

  Future<void> _counterContention(
    AuthWebAuthnStoreConformanceFixture fixture,
  ) async {
    final store = fixture.capabilities.webAuthnAuthenticators;
    final credential = _credential('counter-contention');
    await store.create(credential);
    final results = await Future.wait([
      for (var index = 1; index <= 16; index++)
        Future.sync(
          () => store.updateUsage(
            credentialId: credential.credentialId,
            expectedCounter: 0,
            newCounter: index,
            lastUsedAt: _now.add(Duration(seconds: index)),
          ),
        ),
    ]);
    _require(
      results.whereType<WebAuthnAuthenticator>().length == 1,
      'not one CAS winner',
    );
    final persisted = await store.findByCredentialId(credential.credentialId);
    _require(
      persisted?.counter ==
          results.whereType<WebAuthnAuthenticator>().single.counter,
      'winner not persisted',
    );
  }

  Future<void> _statefulLifecycle(
    AuthWebAuthnStoreConformanceFixture fixture,
  ) async {
    final store = fixture.capabilities.webAuthnAuthenticators;
    final expected = <String, WebAuthnAuthenticator>{};
    for (var step = 0; step < 96; step++) {
      final slot = step % 12;
      final id = 'credential-state-$slot';
      final current = expected[id];
      switch (step % 4) {
        case 0:
          if (current == null) {
            final created = _credential('state-$slot');
            expected[id] = await store.create(created);
          }
        case 1:
          if (current != null) {
            final renamed = await store.renameForUser(
              'user-1',
              id,
              'Passkey $step',
            );
            _require(renamed != null, 'rename failed');
            expected[id] = renamed!;
          }
        case 2:
          if (current != null) {
            final updated = await store.updateUsage(
              credentialId: id,
              expectedCounter: current.counter,
              newCounter: current.counter + 1,
              lastUsedAt: _now.add(Duration(seconds: step)),
            );
            _require(updated != null, 'counter update failed');
            expected[id] = updated!;
          }
        case 3:
          if (current != null && slot.isEven) {
            _require(await store.deleteForUser('user-1', id), 'delete failed');
            expected.remove(id);
          }
      }
      final actual = await store.listForUser('user-1');
      _require(
        actual.length == expected.length,
        'stateful size drifted at $step',
      );
      for (final record in actual) {
        final model = expected[record.credentialId];
        _require(
          model != null &&
              model.counter == record.counter &&
              model.name == record.name,
          'stateful record drifted at $step',
        );
      }
    }
  }
}

final DateTime _now = DateTime.utc(2099, 1, 1);

AuthWebAuthnChallenge _challenge(String suffix) => AuthWebAuthnChallenge(
  id: 'challenge-$suffix',
  challengeHash: hashOpaqueToken('challenge-$suffix'),
  ceremony: AuthWebAuthnCeremony.authentication,
  relyingPartyId: 'example.com',
  origin: 'https://example.com',
  userId: 'user-1',
  createdAt: _now,
  expiresAt: _now.add(const Duration(minutes: 5)),
);

WebAuthnAuthenticator _credential(String suffix, {int counter = 0}) =>
    WebAuthnAuthenticator(
      credentialId: 'credential-$suffix',
      publicKey: 'cose-public-key-$suffix',
      counter: counter,
      userId: 'user-1',
      transports: const ['internal'],
      createdAt: _now,
      name: 'Passkey $suffix',
    );

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _requireThrows(FutureOr<void> Function() body) async {
  try {
    await Future.sync(body);
  } catch (_) {
    return;
  }
  throw StateError('operation unexpectedly succeeded');
}
