import 'dart:async';

import '../core/deletion_transaction.dart';
import '../core/device_authorization_store.dart';
import '../core/email_otp_store.dart';
import '../core/models.dart';
import '../core/oauth_challenge_store.dart';
import '../core/password_reset_token_store.dart';
import '../core/store.dart';

/// Creates a fresh, isolated fixture for one conformance case.
///
/// Durable adapter tests should create a new database, schema, or namespace on
/// every invocation. This lets the suite run cases independently and in any
/// order.
typedef AuthStoreConformanceFixtureFactory =
    FutureOr<AuthStoreConformanceFixture> Function();

/// Creates a fresh [AuthStore] for one conformance case.
typedef AuthStoreConformanceStoreFactory = FutureOr<AuthStore> Function();

/// Disposes an [AuthStore] created for a conformance case.
typedef AuthStoreConformanceStoreDisposer =
    FutureOr<void> Function(AuthStore store);

/// An isolated adapter instance and its optional cleanup callback.
final class AuthStoreConformanceFixture {
  /// Creates a fixture around [store].
  const AuthStoreConformanceFixture({required this.store, this.dispose});

  /// The adapter under test.
  final AuthStore store;

  /// Releases database handles or removes the fixture namespace.
  final FutureOr<void> Function()? dispose;

  Future<void> _close() async {
    await Future.sync(() => dispose?.call());
  }
}

/// An optional persistence capability exercised by a conformance case.
enum AuthStoreConformanceCapability {
  /// Direct lookup of a password credential by its owning user.
  credentialUserLookup,

  /// Transactional confirmation-token account deletion.
  accountDeletion,
}

/// The result of running one conformance case.
final class AuthStoreConformanceResult {
  const AuthStoreConformanceResult._({this.skippedReason});

  /// Creates a successful result.
  const AuthStoreConformanceResult.passed() : this._();

  /// Creates a result for an optional capability the adapter does not expose.
  const AuthStoreConformanceResult.skipped(String reason)
    : this._(skippedReason: reason);

  /// Why the case was skipped, or `null` when it passed.
  final String? skippedReason;

  /// Whether the adapter did not expose the case's optional capability.
  bool get isSkipped => skippedReason != null;
}

/// A failed persistence-adapter conformance case.
final class AuthStoreConformanceFailure implements Exception {
  /// Creates a failure for [caseId] caused by [cause].
  const AuthStoreConformanceFailure({
    required this.caseId,
    required this.cause,
  });

  /// Stable identifier of the failed case.
  final String caseId;

  /// The failed expectation or adapter exception.
  final Object cause;

  @override
  String toString() => 'AuthStoreConformanceFailure($caseId): $cause';
}

/// One independently runnable adapter conformance case.
final class AuthStoreConformanceCase {
  const AuthStoreConformanceCase._({
    required this.id,
    required this.description,
    required Future<AuthStoreConformanceResult> Function() run,
    this.optionalCapability,
  }) : _run = run;

  /// Stable machine-readable case identifier.
  final String id;

  /// Human-readable behavior covered by this case.
  final String description;

  /// Optional capability required by this case.
  final AuthStoreConformanceCapability? optionalCapability;

  final Future<AuthStoreConformanceResult> Function() _run;

  /// Runs this case against a fresh fixture.
  Future<AuthStoreConformanceResult> run() => _run();
}

/// Reusable contract suite for durable [AuthStore] implementations.
///
/// The suite has no dependency on a particular test framework. A package using
/// `package:test` can register the cases like this:
///
/// ```dart
/// final suite = AuthStoreConformanceSuite.fromStoreFactory(
///   createStore: () => SqlAuthStore.openForTest(),
///   disposeStore: (store) => (store as SqlAuthStore).close(),
/// );
///
/// for (final conformanceCase in suite.cases) {
///   test(conformanceCase.description, () async {
///     final result = await conformanceCase.run();
///     if (result.isSkipped) markTestSkipped(result.skippedReason!);
///   });
/// }
/// ```
///
/// Every case receives a new fixture. Base cases only use [AuthStore]. Cases
/// for optional interfaces report a skipped result when the interface is not
/// present. In particular, WebAuthn stores are not required by this suite.
/// Case IDs are stable public contract identifiers suitable for CI reports and
/// adapter allowlists; additions do not change existing identifiers.
final class AuthStoreConformanceSuite {
  /// Creates a suite backed by an isolated fixture factory.
  AuthStoreConformanceSuite({
    required AuthStoreConformanceFixtureFactory createFixture,
  }) : _createFixture = createFixture;

  /// Creates a suite from a store factory and optional disposer.
  factory AuthStoreConformanceSuite.fromStoreFactory({
    required AuthStoreConformanceStoreFactory createStore,
    AuthStoreConformanceStoreDisposer? disposeStore,
  }) {
    return AuthStoreConformanceSuite(
      createFixture: () async {
        final store = await Future.sync(createStore);
        return AuthStoreConformanceFixture(
          store: store,
          dispose: disposeStore == null ? null : () => disposeStore(store),
        );
      },
    );
  }

  final AuthStoreConformanceFixtureFactory _createFixture;

  /// Independently runnable cases in stable registration order.
  late final List<AuthStoreConformanceCase> cases =
      List<AuthStoreConformanceCase>.unmodifiable(<AuthStoreConformanceCase>[
        _case(
          id: 'users.create-find',
          description: 'creates users and resolves canonical identity',
          verify: _verifyUserCreateAndFind,
        ),
        _case(
          id: 'users.email-uniqueness',
          description: 'enforces email uniqueness at the write boundary',
          verify: _verifyUserEmailUniqueness,
        ),
        _case(
          id: 'users.email-update-atomicity',
          description: 'preserves email indexes when an update conflicts',
          verify: _verifyUserEmailUpdateAtomicity,
        ),
        _case(
          id: 'users.create-or-find-contention',
          description: 'creates one canonical email identity under contention',
          verify: _verifyUserCreateOrFindContention,
        ),
        _case(
          id: 'credentials.registration-lookup',
          description: 'registers and resolves password credentials atomically',
          verify: _verifyCredentialRegistration,
        ),
        _case(
          id: 'credentials.registration-contention',
          description: 'registers one credential owner under contention',
          verify: _verifyCredentialRegistrationContention,
        ),
        _case(
          id: 'credentials.user-lookup',
          description: 'resolves credentials through the optional user lookup',
          capability: AuthStoreConformanceCapability.credentialUserLookup,
          supports: (store) =>
              store.credentials is AuthCredentialUserLookupStore,
          verify: _verifyCredentialUserLookup,
        ),
        _case(
          id: 'accounts.uniqueness',
          description: 'keeps external account links globally unique',
          verify: _verifyAccountUniqueness,
        ),
        _case(
          id: 'accounts.link-contention',
          description: 'selects one canonical account owner under contention',
          verify: _verifyAccountLinkContention,
        ),
        _case(
          id: 'accounts.safe-unlink',
          description: 'prevents unlinking the last authentication method',
          verify: _verifySafeAccountUnlink,
        ),
        _case(
          id: 'sessions.rotation',
          description: 'rotates sessions atomically and rejects replay',
          verify: _verifySessionRotation,
        ),
        _case(
          id: 'sessions.rotation-contention',
          description: 'commits exactly one session rotation replacement',
          verify: _verifySessionRotationContention,
        ),
        _case(
          id: 'sessions.revocation',
          description: 'revokes only user-owned sessions',
          verify: _verifySessionRevocation,
        ),
        _case(
          id: 'tokens.verification-single-use',
          description: 'consumes verification tokens at most once',
          verify: _verifyVerificationTokens,
        ),
        _case(
          id: 'tokens.verification-replay-contention',
          description: 'rejects concurrent verification-token replay',
          verify: _verifyVerificationTokenContention,
        ),
        _case(
          id: 'tokens.password-reset-single-use',
          description: 'replaces and consumes password-reset tokens atomically',
          verify: _verifyPasswordResetTokens,
        ),
        _case(
          id: 'tokens.password-reset-replay-contention',
          description: 'rejects concurrent password-reset token replay',
          verify: _verifyPasswordResetTokenContention,
        ),
        _case(
          id: 'oauth.challenge-replay-contention',
          description: 'consumes one OAuth challenge under contention',
          verify: _verifyOAuthChallengeContention,
        ),
        _case(
          id: 'jwt.version-rotation',
          description: 'tracks independent atomic JWT versions',
          verify: _verifyJwtVersions,
        ),
        _case(
          id: 'jwt.version-rotation-contention',
          description: 'returns distinct monotonic JWT rotation versions',
          verify: _verifyJwtVersionContention,
        ),
        _case(
          id: 'device-authorization.approve-claim-contention',
          description: 'approves and claims a device authorization once',
          verify: _verifyDeviceAuthorizationContention,
        ),
        _case(
          id: 'email-otp.verification-contention',
          description: 'replaces and verifies an email OTP exactly once',
          verify: _verifyEmailOtpContention,
        ),
        _case(
          id: 'account-deletion.transaction',
          description: 'rolls back and retries transactional account deletion',
          capability: AuthStoreConformanceCapability.accountDeletion,
          supports: (store) => store is AuthUserDeletionCoordinatorHost,
          verify: _verifyAccountDeletionTransaction,
        ),
      ]);

  AuthStoreConformanceCase _case({
    required String id,
    required String description,
    required Future<void> Function(AuthStore store) verify,
    AuthStoreConformanceCapability? capability,
    bool Function(AuthStore store)? supports,
  }) {
    return AuthStoreConformanceCase._(
      id: id,
      description: description,
      optionalCapability: capability,
      run: () async {
        final fixture = await Future.sync(_createFixture);
        try {
          if (supports != null && !supports(fixture.store)) {
            return AuthStoreConformanceResult.skipped(
              'Adapter does not expose ${capability!.name}.',
            );
          }
          try {
            await verify(fixture.store);
          } catch (error, stackTrace) {
            Error.throwWithStackTrace(
              AuthStoreConformanceFailure(caseId: id, cause: error),
              stackTrace,
            );
          }
          return const AuthStoreConformanceResult.passed();
        } finally {
          await fixture._close();
        }
      },
    );
  }
}

Future<void> _verifyUserCreateAndFind(AuthStore store) async {
  final user = _user('user-1', 'one@example.com');
  final created = await Future.sync(() => store.users.create(user));
  _check(created.id == user.id, 'create must return the persisted user');
  _check(
    (await Future.sync(() => store.users.findById(user.id)))?.email ==
        user.email,
    'findById must return the persisted user',
  );
  _check(
    (await Future.sync(() => store.users.findByEmail(user.email!)))?.id ==
        user.id,
    'findByEmail must return the canonical user',
  );

  final same = await Future.sync(() => store.users.createOrFindByEmail(user));
  _check(!same.created, 'createOrFindByEmail must not duplicate a user');
  _check(same.user.id == user.id, 'createOrFindByEmail changed identity');
}

Future<void> _verifyUserEmailUniqueness(AuthStore store) async {
  final first = _user('user-1', 'unique@example.com');
  await Future.sync(() => store.users.create(first));
  final duplicate = _user('user-2', first.email!);
  await _allowRejectedWrite(() => store.users.create(duplicate));

  _check(
    await Future.sync(() => store.users.findById(duplicate.id)) == null,
    'duplicate email write persisted a second user',
  );
  _check(
    (await Future.sync(() => store.users.findByEmail(first.email!)))?.id ==
        first.id,
    'duplicate email write replaced the canonical user',
  );

  final found = await Future.sync(
    () => store.users.createOrFindByEmail(duplicate),
  );
  _check(!found.created, 'createOrFindByEmail created a duplicate email');
  _check(found.user.id == first.id, 'canonical email owner was not returned');
}

Future<void> _verifyUserEmailUpdateAtomicity(AuthStore store) async {
  final first = _user('user-1', 'first@example.com');
  final second = _user('user-2', 'second@example.com');
  await Future.sync(() => store.users.create(first));
  await Future.sync(() => store.users.create(second));

  await _allowRejectedWrite(
    () => store.users.updateEmailForUser(first.id, second.email!),
  );
  _check(
    (await Future.sync(() => store.users.findByEmail(first.email!)))?.id ==
        first.id,
    'a rejected email update removed the original index',
  );
  _check(
    (await Future.sync(() => store.users.findByEmail(second.email!)))?.id ==
        second.id,
    'a rejected email update changed the conflicting owner',
  );

  final updated = await Future.sync(
    () => store.users.updateEmailForUser(first.id, 'new@example.com'),
  );
  _check(updated?.email == 'new@example.com', 'valid email update failed');
  _check(
    await Future.sync(() => store.users.findByEmail(first.email!)) == null,
    'valid email update retained the old index',
  );
}

Future<void> _verifyUserCreateOrFindContention(AuthStore store) async {
  const email = 'contended@example.com';
  final candidates = <AuthUser>[
    for (var index = 0; index < 16; index++)
      _user('contended-user-$index', email),
  ];
  final results = await Future.wait([
    for (final candidate in candidates)
      Future.sync(() => store.users.createOrFindByEmail(candidate)),
  ]);

  final created = results.where((result) => result.created).toList();
  _check(created.length == 1, 'contention created more than one email owner');
  final canonicalId = created.single.user.id;
  _check(
    results.every((result) => result.user.id == canonicalId),
    'createOrFindByEmail returned conflicting canonical users',
  );
  _check(
    (await Future.sync(() => store.users.findByEmail(email)))?.id ==
        canonicalId,
    'email lookup did not preserve the contention winner',
  );
  final persisted = await Future.wait([
    for (final candidate in candidates)
      Future.sync(() => store.users.findById(candidate.id)),
  ]);
  _check(
    persisted.whereType<AuthUser>().length == 1,
    'losing email candidates were persisted',
  );
}

Future<void> _verifyCredentialRegistration(AuthStore store) async {
  final now = _conformanceNow();
  final user = _user('user-1', 'credential@example.com');
  final credential = _credential(user, now: now);
  final registered = await Future.sync(
    () => store.credentials.register(user, credential),
  );
  _check(registered?.id == user.id, 'credential registration failed');
  final found = await Future.sync(
    () => store.credentials.findByIdentifier(credential.identifier),
  );
  _check(found?.id == credential.id, 'credential lookup returned no record');
  _check(
    found?.passwordHash == credential.passwordHash,
    'credential lookup changed the encoded password hash',
  );

  final otherUser = _user('user-2', 'other@example.com');
  final duplicate = _credential(
    otherUser,
    identifier: credential.identifier,
    now: now,
  );
  await _allowRejectedWrite(
    () => store.credentials.register(otherUser, duplicate),
  );
  _check(
    await Future.sync(() => store.users.findById(otherUser.id)) == null,
    'rejected credential registration persisted its user',
  );
  _check(
    (await Future.sync(
          () => store.credentials.findByIdentifier(credential.identifier),
        ))?.userId ==
        user.id,
    'duplicate credential registration replaced the owner',
  );
}

Future<void> _verifyCredentialRegistrationContention(AuthStore store) async {
  final now = _conformanceNow();
  const identifier = 'contended-login';
  final users = <AuthUser>[
    for (var index = 0; index < 16; index++)
      AuthUser(id: 'credential-user-$index'),
  ];
  final results = await Future.wait([
    for (final user in users)
      _rejectedWriteAsNull(
        () => store.credentials.register(
          user,
          _credential(user, identifier: identifier, now: now),
        ),
      ),
  ]);

  final registered = results.whereType<AuthUser>().toList();
  _check(registered.length == 1, 'contention registered multiple credentials');
  final ownerId = registered.single.id;
  _check(
    (await Future.sync(
          () => store.credentials.findByIdentifier(identifier),
        ))?.userId ==
        ownerId,
    'credential lookup did not preserve the contention winner',
  );
  final persisted = await Future.wait([
    for (final user in users) Future.sync(() => store.users.findById(user.id)),
  ]);
  _check(
    persisted.whereType<AuthUser>().length == 1,
    'losing credential registrations persisted users',
  );
}

Future<void> _verifyCredentialUserLookup(AuthStore store) async {
  final now = _conformanceNow();
  final user = _user('lookup-user', 'lookup@example.com');
  final credential = _credential(user, now: now);
  await Future.sync(() => store.credentials.register(user, credential));
  final lookup = store.credentials as AuthCredentialUserLookupStore;
  final found = await Future.sync(() => lookup.findForUser(user.id));
  _check(found?.id == credential.id, 'user credential lookup returned no row');
}

Future<void> _verifyAccountUniqueness(AuthStore store) async {
  final first = _account('user-1', accountId: 'provider-account');
  final linked = await Future.sync(() => store.accounts.link(first));
  _check(linked.userId == first.userId, 'initial account link failed');

  final conflicting = _account('user-2', accountId: 'provider-account');
  final canonical = await Future.sync(() => store.accounts.link(conflicting));
  _check(
    canonical.userId == first.userId,
    'a provider identity was reassigned to another user',
  );
  _check(
    (await Future.sync(
          () => store.accounts.find(first.providerId, first.providerAccountId),
        ))?.userId ==
        first.userId,
    'provider identity lookup returned the wrong owner',
  );
  _check(
    (await Future.sync(() => store.accounts.listForUser('user-2'))).isEmpty,
    'conflicting provider identity appeared in the second user account',
  );
}

Future<void> _verifyAccountLinkContention(AuthStore store) async {
  final candidates = <AuthAccount>[
    for (var index = 0; index < 16; index++)
      _account('account-user-$index', accountId: 'contended-account'),
  ];
  final linked = await Future.wait([
    for (final candidate in candidates)
      Future.sync(() => store.accounts.link(candidate)),
  ]);
  final owners = linked.map((account) => account.userId).toSet();
  _check(
    owners.length == 1,
    'account link contention returned multiple owners',
  );
  final ownerId = owners.single;
  _check(ownerId != null, 'account link contention returned no owner');
  _check(
    (await Future.sync(
          () => store.accounts.find(
            candidates.first.providerId,
            candidates.first.providerAccountId,
          ),
        ))?.userId ==
        ownerId,
    'account lookup did not preserve the contention winner',
  );
  final listings = await Future.wait([
    for (final candidate in candidates)
      Future.sync(() => store.accounts.listForUser(candidate.userId!)),
  ]);
  _check(
    listings.fold<int>(0, (count, accounts) => count + accounts.length) == 1,
    'provider identity was persisted for multiple users',
  );
}

Future<void> _verifySafeAccountUnlink(AuthStore store) async {
  final first = _account('user-1', accountId: 'first');
  final second = _account('user-1', accountId: 'second');
  await Future.sync(() => store.accounts.link(first));
  await Future.sync(() => store.accounts.link(second));

  final firstResult = await Future.sync(
    () => store.accounts.unlinkForUserIfSafe(
      'user-1',
      first.providerId,
      first.providerAccountId,
      hasEnabledPasswordCredential: false,
    ),
  );
  _check(
    firstResult == AuthAccountUnlinkResult.unlinked,
    'an account with another provider identity could not be unlinked',
  );
  final blocked = await Future.sync(
    () => store.accounts.unlinkForUserIfSafe(
      'user-1',
      second.providerId,
      second.providerAccountId,
      hasEnabledPasswordCredential: false,
    ),
  );
  _check(
    blocked == AuthAccountUnlinkResult.lastAuthenticationMethod,
    'the last authentication method was removed',
  );
  final removed = await Future.sync(
    () => store.accounts.unlinkForUserIfSafe(
      'user-1',
      second.providerId,
      second.providerAccountId,
      hasEnabledPasswordCredential: true,
    ),
  );
  _check(
    removed == AuthAccountUnlinkResult.unlinked,
    'password-backed account could not unlink its last provider',
  );
}

Future<void> _verifySessionRotation(AuthStore store) async {
  final now = _conformanceNow();
  final previous = _session('session-1', 'token-hash-1', now: now);
  final replacement = _session('session-2', 'token-hash-2', now: now);
  final collision = _session(
    'collision',
    'collision-hash',
    userId: 'user-2',
    now: now,
  );
  await Future.sync(() => store.sessions.create(previous));
  await Future.sync(() => store.sessions.create(collision));
  await _allowRejectedWrite(
    () => store.sessions.rotate(
      previousTokenHash: previous.tokenHash,
      replacement: _session(
        'colliding-replacement',
        collision.tokenHash,
        now: now,
      ),
    ),
  );
  _check(
    (await Future.sync(
          () => store.sessions.find(previous.tokenHash),
        ))?.revokedAt ==
        null,
    'failed session rotation revoked the previous token',
  );
  final rotated = await Future.sync(
    () => store.sessions.rotate(
      previousTokenHash: previous.tokenHash,
      replacement: replacement,
    ),
  );
  _check(rotated?.id == replacement.id, 'session rotation failed');
  _check(
    (await Future.sync(
          () => store.sessions.find(previous.tokenHash),
        ))?.revokedAt !=
        null,
    'session rotation did not revoke the previous token',
  );
  _check(
    (await Future.sync(() => store.sessions.find(replacement.tokenHash)))?.id ==
        replacement.id,
    'session rotation did not persist the replacement',
  );
  _check(
    await Future.sync(
          () => store.sessions.rotate(
            previousTokenHash: previous.tokenHash,
            replacement: _session('session-3', 'token-hash-3', now: now),
          ),
        ) ==
        null,
    'a revoked session was rotated again',
  );
}

Future<void> _verifySessionRotationContention(AuthStore store) async {
  final now = _conformanceNow();
  final original = _session(
    'rotation-original',
    'rotation-original-hash',
    userId: 'rotation-user',
    now: now,
  );
  await Future.sync(() => store.sessions.create(original));
  final replacements = <AuthSessionRecord>[
    for (var index = 0; index < 16; index++)
      _session(
        'rotation-replacement-$index',
        'rotation-replacement-hash-$index',
        userId: original.userId,
        now: now,
      ),
  ];
  final results = await Future.wait([
    for (final replacement in replacements)
      Future.sync(
        () => store.sessions.rotate(
          previousTokenHash: original.tokenHash,
          replacement: replacement,
        ),
      ),
  ]);

  final winners = results.whereType<AuthSessionRecord>().toList();
  _check(winners.length == 1, 'session rotation had multiple winners');
  final winner = winners.single;
  final stored = await Future.sync(
    () => store.sessions.listForUser(original.userId),
  );
  _check(stored.length == 2, 'session rotation persisted losing replacements');
  _check(
    stored.where((session) => session.id == original.id).single.revokedAt !=
        null,
    'session rotation did not revoke the original session',
  );
  _check(
    stored.where((session) => session.id == winner.id).single.revokedAt == null,
    'session rotation winner was not active',
  );
  for (final losing in replacements.where(
    (replacement) => replacement.id != winner.id,
  )) {
    _check(
      await Future.sync(() => store.sessions.find(losing.tokenHash)) == null,
      'a losing session replacement was persisted',
    );
  }
}

Future<void> _verifySessionRevocation(AuthStore store) async {
  final now = _conformanceNow();
  final current = _session('current', 'current-hash', now: now);
  final other = _session('other', 'other-hash', now: now);
  final foreign = _session(
    'foreign',
    'foreign-hash',
    userId: 'user-2',
    now: now,
  );
  await Future.sync(() => store.sessions.create(current));
  await Future.sync(() => store.sessions.create(other));
  await Future.sync(() => store.sessions.create(foreign));

  _check(
    await Future.sync(() => store.sessions.revokeById('user-1', foreign.id)) ==
        null,
    'revokeById crossed the user ownership boundary',
  );
  final count = await Future.sync(
    () => store.sessions.revokeAllForUserExcept('user-1', current.id),
  );
  _check(count == 1, 'revokeAllForUserExcept returned the wrong count');
  _check(
    (await Future.sync(
          () => store.sessions.find(current.tokenHash),
        ))?.revokedAt ==
        null,
    'revokeAllForUserExcept revoked the current session',
  );
  _check(
    (await Future.sync(
          () => store.sessions.find(other.tokenHash),
        ))?.revokedAt !=
        null,
    'revokeAllForUserExcept did not revoke another session',
  );
  _check(
    (await Future.sync(
          () => store.sessions.find(foreign.tokenHash),
        ))?.revokedAt ==
        null,
    'session revocation crossed the user ownership boundary',
  );
}

Future<void> _verifyVerificationTokens(AuthStore store) async {
  final token = AuthVerificationToken(
    identifier: 'verify@example.com',
    token: 'verification-secret',
    expiresAt: _conformanceNow().add(const Duration(minutes: 10)),
    metadata: const <String, dynamic>{'purpose': 'conformance'},
  );
  await Future.sync(() => store.verificationTokens.save(token));
  final consumed = await Future.sync(
    () => store.verificationTokens.consume(token.identifier, token.token),
  );
  _check(consumed != null, 'verification token could not be consumed');
  _check(
    consumed!.metadata['purpose'] == 'conformance',
    'verification token metadata was not preserved',
  );
  _check(
    await Future.sync(
          () => store.verificationTokens.consume(token.identifier, token.token),
        ) ==
        null,
    'verification token could be replayed',
  );
}

Future<void> _verifyVerificationTokenContention(AuthStore store) async {
  final token = AuthVerificationToken(
    identifier: 'verification-contention@example.com',
    token: 'verification-contention-secret',
    expiresAt: _conformanceNow().add(const Duration(minutes: 10)),
    metadata: const <String, dynamic>{'purpose': 'contention'},
  );
  await Future.sync(() => store.verificationTokens.save(token));
  final results = await Future.wait(
    List<Future<AuthVerificationToken?>>.generate(
      16,
      (_) => Future.sync(
        () => store.verificationTokens.consume(token.identifier, token.token),
      ),
    ),
  );
  final consumed = results.whereType<AuthVerificationToken>().toList();
  _check(
    consumed.length == 1,
    'verification token contention did not have exactly one winner',
  );
  _check(
    consumed.single.metadata['purpose'] == 'contention',
    'verification token metadata was not preserved',
  );
  _check(
    await Future.sync(
          () => store.verificationTokens.consume(token.identifier, token.token),
        ) ==
        null,
    'verification token was available after contention',
  );
}

Future<void> _verifyPasswordResetTokens(AuthStore store) async {
  final now = _conformanceNow();
  final first = buildAuthPasswordResetToken(
    userId: 'user-1',
    token: 'reset-secret-1',
    ttl: const Duration(minutes: 10),
    now: now,
  );
  final second = buildAuthPasswordResetToken(
    userId: 'user-1',
    token: 'reset-secret-2',
    ttl: const Duration(minutes: 10),
    now: now,
  );
  await Future.sync(() => store.passwordResetTokens.save(first));
  await Future.sync(() => store.passwordResetTokens.save(second));
  _check(
    await Future.sync(
          () => store.passwordResetTokens.findActive('reset-secret-1'),
        ) ==
        null,
    'a newer password-reset token did not replace the old token',
  );
  _check(
    (await Future.sync(
          () => store.passwordResetTokens.findActive('reset-secret-2'),
        ))?.userId ==
        'user-1',
    'active password-reset lookup consumed or lost the token',
  );
  final consumed = await Future.sync(
    () => store.passwordResetTokens.consume('reset-secret-2'),
  );
  _check(consumed?.userId == 'user-1', 'password-reset token was not consumed');
  _check(
    await Future.sync(
          () => store.passwordResetTokens.consume('reset-secret-2'),
        ) ==
        null,
    'password-reset token could be replayed',
  );
}

Future<void> _verifyPasswordResetTokenContention(AuthStore store) async {
  final now = _conformanceNow();
  const rawToken = 'reset-contention-secret';
  await Future.sync(
    () => store.passwordResetTokens.save(
      buildAuthPasswordResetToken(
        userId: 'reset-contention-user',
        token: rawToken,
        ttl: const Duration(minutes: 10),
        now: now,
      ),
    ),
  );
  final results = await Future.wait(
    List<Future<AuthPasswordResetToken?>>.generate(
      16,
      (_) => Future.sync(() => store.passwordResetTokens.consume(rawToken)),
    ),
  );
  _check(
    results.whereType<AuthPasswordResetToken>().length == 1,
    'password-reset contention did not have exactly one winner',
  );
  _check(
    await Future.sync(() => store.passwordResetTokens.consume(rawToken)) ==
        null,
    'password-reset token was available after contention',
  );
}

Future<void> _verifyOAuthChallengeContention(AuthStore store) async {
  final challenge = AuthOAuthChallenge(
    providerId: 'conformance-provider',
    state: 'oauth-contention-state',
    expiresAt: _conformanceNow().add(const Duration(minutes: 10)),
    codeVerifier: 'oauth-code-verifier',
    nonce: 'oauth-nonce',
  );
  await Future.sync(() => store.oauthChallenges.save(challenge));
  final results = await Future.wait([
    for (var index = 0; index < 16; index++)
      Future.sync(
        () => store.oauthChallenges.consume(
          challenge.providerId,
          challenge.state,
        ),
      ),
  ]);
  final consumed = results.whereType<AuthOAuthChallenge>().toList();
  _check(consumed.length == 1, 'OAuth challenge had multiple consumers');
  _check(
    consumed.single.codeVerifier == challenge.codeVerifier &&
        consumed.single.nonce == challenge.nonce,
    'OAuth challenge bindings were not preserved',
  );
  _check(
    await Future.sync(
          () => store.oauthChallenges.consume(
            challenge.providerId,
            challenge.state,
          ),
        ) ==
        null,
    'OAuth challenge was available after contention',
  );
}

Future<void> _verifyJwtVersions(AuthStore store) async {
  _check(
    await Future.sync(() => store.jwtVersions.current('user-1')) == 0,
    'new JWT version did not start at zero',
  );
  _check(
    await Future.sync(() => store.jwtVersions.rotate('user-1')) == 1,
    'first JWT rotation did not advance to one',
  );
  _check(
    await Future.sync(() => store.jwtVersions.rotate('user-1')) == 2,
    'second JWT rotation did not advance to two',
  );
  _check(
    await Future.sync(() => store.jwtVersions.current('user-2')) == 0,
    'JWT versions leaked between users',
  );
}

Future<void> _verifyJwtVersionContention(AuthStore store) async {
  const userId = 'jwt-contention-user';
  final versions = await Future.wait([
    for (var index = 0; index < 16; index++)
      Future.sync(() => store.jwtVersions.rotate(userId)),
  ]);
  _check(
    versions.toSet().length == versions.length,
    'JWT rotations returned duplicate versions',
  );
  _check(
    versions.toSet().containsAll(<int>{
      for (var value = 1; value <= 16; value++) value,
    }),
    'JWT rotations did not return the complete monotonic sequence',
  );
  _check(
    await Future.sync(() => store.jwtVersions.current(userId)) == 16,
    'JWT rotation contention persisted the wrong current version',
  );
}

Future<void> _verifyDeviceAuthorizationContention(AuthStore store) async {
  final now = _conformanceNow();
  final authorization = AuthDeviceAuthorization(
    id: 'device-contention',
    deviceCodeHash: 'device-contention-hash',
    userCodeHash: 'user-contention-hash',
    clientId: 'device-contention-client',
    scopes: const <String>['openid'],
    createdAt: now,
    expiresAt: now.add(const Duration(minutes: 10)),
    interval: const Duration(seconds: 5),
  );
  await Future.sync(() => store.deviceAuthorizations.create(authorization));
  final approvals = await Future.wait([
    for (var index = 0; index < 8; index++)
      Future.sync(
        () => store.deviceAuthorizations.approve(
          authorization.userCodeHash,
          'device-user-$index',
          now: now,
        ),
      ),
  ]);
  final approved = approvals.whereType<AuthDeviceAuthorization>().toList();
  _check(approved.length == 1, 'device authorization had multiple approvers');

  final claims = await Future.wait([
    for (var index = 0; index < 16; index++)
      Future.sync(
        () => store.deviceAuthorizations.claimApproved(
          authorization.deviceCodeHash,
          clientId: authorization.clientId,
          now: now,
        ),
      ),
  ]);
  final claimed = claims.whereType<AuthDeviceAuthorization>().toList();
  _check(claimed.length == 1, 'device authorization had multiple claimants');
  _check(
    claimed.single.userId == approved.single.userId,
    'device authorization claim changed the approved user',
  );
  _check(
    await Future.sync(
          () => store.deviceAuthorizations.claimApproved(
            authorization.deviceCodeHash,
            clientId: authorization.clientId,
            now: now,
          ),
        ) ==
        null,
    'device authorization was claimable after contention',
  );
}

Future<void> _verifyEmailOtpContention(AuthStore store) async {
  final now = _conformanceNow();
  const email = 'otp-contention@example.com';
  const staleCode = '111111';
  const activeCode = '222222';
  AuthEmailOtp otp(String id, String code) => AuthEmailOtp(
    id: id,
    email: email,
    codeHash: hashAuthEmailOtpCode(code),
    type: AuthEmailOtpType.signIn,
    createdAt: now,
    expiresAt: now.add(const Duration(minutes: 5)),
    maxAttempts: 32,
  );

  await Future.sync(() => store.emailOtps.save(otp('otp-stale', staleCode)));
  await Future.sync(() => store.emailOtps.save(otp('otp-active', activeCode)));
  final stale = await Future.sync(
    () => store.emailOtps.verify(
      email,
      AuthEmailOtpType.signIn,
      staleCode,
      now: now,
    ),
  );
  _check(
    stale.status == AuthEmailOtpVerificationStatus.invalid,
    'a replaced email OTP remained valid',
  );
  final results = await Future.wait([
    for (var index = 0; index < 16; index++)
      Future.sync(
        () => store.emailOtps.verify(
          email,
          AuthEmailOtpType.signIn,
          activeCode,
          now: now,
        ),
      ),
  ]);
  _check(
    results
            .where(
              (result) =>
                  result.status == AuthEmailOtpVerificationStatus.verified,
            )
            .length ==
        1,
    'email OTP contention did not have exactly one winner',
  );
  final replay = await Future.sync(
    () => store.emailOtps.verify(
      email,
      AuthEmailOtpType.signIn,
      activeCode,
      now: now,
    ),
  );
  _check(
    replay.status != AuthEmailOtpVerificationStatus.verified,
    'email OTP was accepted after contention',
  );
}

Future<void> _verifyAccountDeletionTransaction(AuthStore store) async {
  final host = store as AuthUserDeletionCoordinatorHost;
  final coordinator = host.userDeletionCoordinator;
  final now = _conformanceNow();
  final user = _user('delete-user', 'delete@example.com');
  final credential = _credential(user, now: now);
  final account = _account(user.id, accountId: 'delete-account');
  final session = _session(
    'delete-session',
    'delete-session-hash',
    userId: user.id,
    now: now,
  );
  const deletionToken = 'delete-confirmation';
  await Future.sync(() => store.credentials.register(user, credential));
  await Future.sync(() => store.accounts.link(account));
  await Future.sync(() => store.sessions.create(session));
  await Future.sync(
    () => store.passwordResetTokens.save(
      buildAuthPasswordResetToken(
        userId: user.id,
        token: 'delete-reset-token',
        ttl: const Duration(minutes: 10),
        now: now,
      ),
    ),
  );
  await Future.sync(
    () => store.verificationTokens.save(
      AuthVerificationToken(
        identifier: 'account_deletion:${user.id}',
        token: deletionToken,
        expiresAt: now.add(const Duration(minutes: 10)),
      ),
    ),
  );

  _FaultingDeletionContributor? faultingContributor;
  if (coordinator.domain case AuthInMemoryUserDeletionDomain domain) {
    faultingContributor = _FaultingDeletionContributor(
      domain: domain,
      error: StateError('contributor rollback marker'),
    );
    host.bindUserDeletionPlanContributors([faultingContributor]);
  } else {
    host.bindUserDeletionPlanContributors(const []);
  }

  final invalid = await coordinator.confirmAndDeleteUser(
    userId: user.id,
    token: 'invalid-deletion-token',
    now: now,
  );
  _check(!invalid, 'an invalid deletion token was accepted');
  await _checkUserDataPresent(
    store,
    user: user,
    credential: credential,
    account: account,
    session: session,
  );

  if (faultingContributor != null) {
    Object? rollbackError;
    try {
      await coordinator.confirmAndDeleteUser(
        userId: user.id,
        token: deletionToken,
        now: now,
      );
    } catch (error) {
      rollbackError = error;
    }
    _check(
      identical(rollbackError, faultingContributor.error),
      'plugin deletion failure was swallowed',
    );
    await _checkUserDataPresent(
      store,
      user: user,
      credential: credential,
      account: account,
      session: session,
    );
  }

  final results = await Future.wait([
    coordinator.confirmAndDeleteUser(
      userId: user.id,
      token: deletionToken,
      now: now,
    ),
    coordinator.confirmAndDeleteUser(
      userId: user.id,
      token: deletionToken,
      now: now,
    ),
  ]);
  _check(
    results.where((deleted) => deleted).length == 1,
    'deletion contention did not have exactly one winner',
  );
  _check(
    await Future.sync(() => store.users.findById(user.id)) == null,
    'account deletion retained the user',
  );
  _check(
    await Future.sync(
          () => store.credentials.findByIdentifier(credential.identifier),
        ) ==
        null,
    'account deletion retained the password credential',
  );
  _check(
    (await Future.sync(() => store.accounts.listForUser(user.id))).isEmpty,
    'account deletion retained linked identities',
  );
  _check(
    (await Future.sync(() => store.sessions.listForUser(user.id))).isEmpty,
    'account deletion retained sessions',
  );
  _check(
    await Future.sync(
          () => store.passwordResetTokens.findActive('delete-reset-token'),
        ) ==
        null,
    'account deletion retained password-reset tokens',
  );
  _check(
    await Future.sync(() => store.jwtVersions.current(user.id)) == 1,
    'account deletion did not invalidate JWTs',
  );
}

final class _FaultingDeletionContributor
    implements AuthUserDeletionPlanContributor {
  _FaultingDeletionContributor({required this.domain, required this.error});

  final AuthInMemoryUserDeletionDomain domain;
  final Object error;
  bool failedOnce = false;

  @override
  String get userDataNamespace => 'conformance_fault';

  @override
  AuthUserDeletionPlan createUserDeletionPlan(AuthUser user) =>
      AuthInMemoryUserDeletionPlan(
        domain: domain,
        userId: user.id,
        namespace: userDataNamespace,
        operation: _FaultingDeletionOperation(this),
      );
}

final class _FaultingDeletionOperation
    implements AuthInMemoryUserDeletionOperation {
  const _FaultingDeletionOperation(this.contributor);

  final _FaultingDeletionContributor contributor;

  @override
  Object captureState() => const Object();

  @override
  void apply() {
    if (contributor.failedOnce) return;
    contributor.failedOnce = true;
    throw contributor.error;
  }

  @override
  void restoreState(Object state) {}
}

Future<void> _checkUserDataPresent(
  AuthStore store, {
  required AuthUser user,
  required AuthPasswordCredential credential,
  required AuthAccount account,
  required AuthSessionRecord session,
}) async {
  _check(
    await Future.sync(() => store.users.findById(user.id)) != null,
    'rollback removed the user',
  );
  _check(
    await Future.sync(
          () => store.credentials.findByIdentifier(credential.identifier),
        ) !=
        null,
    'rollback removed the password credential',
  );
  _check(
    await Future.sync(
          () => store.accounts.find(
            account.providerId,
            account.providerAccountId,
          ),
        ) !=
        null,
    'rollback removed a linked identity',
  );
  _check(
    await Future.sync(() => store.sessions.find(session.tokenHash)) != null,
    'rollback removed the session',
  );
  _check(
    await Future.sync(
          () => store.passwordResetTokens.findActive('delete-reset-token'),
        ) !=
        null,
    'rollback removed the password-reset token',
  );
}

AuthUser _user(String id, String email) => AuthUser(id: id, email: email);

DateTime _conformanceNow() => DateTime.utc(2100, 1, 1, 12);

AuthPasswordCredential _credential(
  AuthUser user, {
  required DateTime now,
  String? identifier,
}) {
  return AuthPasswordCredential(
    id: 'credential-${user.id}',
    userId: user.id,
    identifier: identifier ?? user.email!,
    passwordHash: r'$conformance$encoded-password-hash',
    createdAt: now,
    updatedAt: now,
  );
}

AuthAccount _account(String userId, {required String accountId}) {
  return AuthAccount(
    providerId: 'conformance-provider',
    providerAccountId: accountId,
    userId: userId,
    accessToken: 'private-access-token',
  );
}

AuthSessionRecord _session(
  String id,
  String tokenHash, {
  String userId = 'user-1',
  required DateTime now,
}) {
  return AuthSessionRecord(
    id: id,
    tokenHash: tokenHash,
    userId: userId,
    createdAt: now,
    expiresAt: now.add(const Duration(days: 1)),
    lastUsedAt: now,
    authenticationMethod: 'conformance',
  );
}

Future<void> _allowRejectedWrite(FutureOr<Object?> Function() write) async {
  try {
    final result = await Future.sync(write);
    _check(result == null, 'conflicting write returned a successful result');
  } on _AuthStoreExpectationFailure {
    rethrow;
  } catch (_) {
    // Constraint errors are a valid way to reject conflicting writes.
  }
}

Future<T?> _rejectedWriteAsNull<T>(FutureOr<T?> Function() write) async {
  try {
    return await Future.sync(write);
  } catch (_) {
    // Constraint errors are a valid losing result for contended writes.
    return null;
  }
}

void _check(bool condition, String message) {
  if (!condition) throw _AuthStoreExpectationFailure(message);
}

final class _AuthStoreExpectationFailure implements Exception {
  const _AuthStoreExpectationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
