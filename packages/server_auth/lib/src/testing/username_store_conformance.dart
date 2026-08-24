import 'dart:async';

import 'package:server_auth/src/core/account_policy.dart';
import 'package:server_auth/src/core/authentication_methods.dart';
import 'package:server_auth/src/core/deletion_transaction.dart';
import 'package:server_auth/src/core/models.dart';
import 'package:server_auth/src/core/store.dart';
import 'package:server_auth/src/core/username_store.dart';

/// Describes a failed username-store conformance case.
final class AuthUsernameStoreConformanceFailure implements Exception {
  /// Creates a failure for [caseId] caused by [cause].
  const AuthUsernameStoreConformanceFailure(this.caseId, this.cause);

  /// Stable identifier of the failed case.
  final String caseId;

  /// Error raised by the adapter or the failed expectation.
  final Object cause;

  @override
  String toString() => 'AuthUsernameStoreConformanceFailure($caseId): $cause';
}

/// Isolated adapter fixture for the public username transaction verifier.
final class AuthUsernameStoreConformanceFixture {
  /// Creates a fixture from the username-capable store and fault hook.
  const AuthUsernameStoreConformanceFixture({
    required this.store,
    this.armFault,
  });

  /// Core authentication store under test.
  final AuthStore store;

  /// Arms one deterministic failure inside the adapter's next transaction.
  final FutureOr<void> Function(AuthUsernameFaultPoint point)? armFault;
}

/// Verifies username reservation, rollback, contention, replay, removal, and
/// hard-deletion guarantees for a durable [AuthStore] adapter.
Future<void> verifyAuthUsernameStoreConformance(
  AuthUsernameStoreConformanceFixture fixture,
) async {
  final root = fixture.store;
  if (root is! AuthUsernameStore) {
    throw const AuthUsernameStoreConformanceFailure(
      'capability',
      'Root AuthUsernameStore is required',
    );
  }
  final store = root as AuthUsernameStore;
  final authenticationMethods = AuthAuthenticationMethodService(
    store: root,
    contributors: <AuthAuthenticationMethodInventoryContributor>[
      _UsernameInventory(store, root),
      _OAuthInventory(root.accounts),
    ],
  )..composeContributors(const []);

  await _case('registration.concurrent-normalized-identifier', () async {
    final outcomes = await Future.wait([
      Future.sync(
        () => store.registerUsername(
          _registration('registration-a', 'shared-name'),
        ),
      ),
      Future.sync(
        () => store.registerUsername(
          _registration('registration-b', 'shared-name'),
        ),
      ),
    ]);
    _check(
      outcomes.where((result) => result.succeeded).length == 1,
      'registration winner',
    );
    _check(
      outcomes
              .where(
                (result) =>
                    result.status == AuthUsernameMutationStatus.conflict,
              )
              .length ==
          1,
      'registration conflict',
    );
  });

  await _case('registration.single-use-replay', () async {
    final command = _registration('registration-replay', 'replay-name');
    final first = await store.registerUsername(command);
    final replay = await store.registerUsername(command);
    _check(first.status == AuthUsernameMutationStatus.created, 'created');
    _check(
      replay.status == AuthUsernameMutationStatus.conflict,
      'replay conflict',
    );
    _check(
      (await store.findByUsername('replay-name'))?.id == first.credential?.id,
      'original ownership retained',
    );
  });

  await _case('registration.user-conflict-is-mutation-free', () async {
    final first = await store.registerUsername(
      _registration('registration-owner', 'owner-name'),
    );
    final now = DateTime.utc(2030);
    final conflictingUser = AuthUser(
      id: first.user!.id,
      email: first.user!.email,
      name: 'shadow-name',
      attributes: const <String, dynamic>{'username': 'shadow-name'},
    );
    final result = await store.registerUsername(
      AuthUsernameRegistrationCommand(
        user: conflictingUser,
        credential: AuthPasswordCredential(
          id: 'registration-shadow-credential',
          userId: conflictingUser.id,
          identifier: 'shadow-name',
          passwordHash: 'encoded-hash',
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );
    _check(
      result.status == AuthUsernameMutationStatus.conflict,
      'user conflict',
    );
    _check(await store.findByUsername('shadow-name') == null, 'no credential');
    _check(
      (await store.findUsernameForUser(conflictingUser.id))?.identifier ==
          'owner-name',
      'original credential retained',
    );
    _check(
      (await root.users.findById(conflictingUser.id))?.attributes['username'] ==
          'owner-name',
      'original projection retained',
    );
  });

  await _case('change.conflict-rollback', () async {
    final first = await store.registerUsername(
      _registration('change-conflict-a', 'change-before'),
    );
    await store.registerUsername(
      _registration('change-conflict-b', 'change-claimed'),
    );
    final result = await store.changeUsername(
      _change(first, from: 'change-before', to: 'change-claimed'),
    );
    _check(result.status == AuthUsernameMutationStatus.conflict, 'conflict');
    _check(
      (await store.findUsernameForUser(first.user!.id))?.identifier ==
          'change-before',
      'credential rollback',
    );
    _check(
      (await root.users.findById(first.user!.id))?.attributes['username'] ==
          'change-before',
      'projection rollback',
    );
  });

  await _case('change.concurrent-and-replay', () async {
    final registered = await store.registerUsername(
      _registration('change-race', 'race-before'),
    );
    final commandA = _change(
      registered,
      from: 'race-before',
      to: 'race-after-a',
    );
    final commandB = _change(
      registered,
      from: 'race-before',
      to: 'race-after-b',
    );
    final outcomes = await Future.wait([
      Future.sync(() => store.changeUsername(commandA)),
      Future.sync(() => store.changeUsername(commandB)),
    ]);
    _check(
      outcomes
              .where(
                (result) => result.status == AuthUsernameMutationStatus.changed,
              )
              .length ==
          1,
      'rename winner',
    );
    final winner = outcomes.firstWhere((result) => result.succeeded);
    final replay = await store.changeUsername(
      _change(
        registered,
        from: 'race-before',
        to: winner.credential!.identifier,
      ),
    );
    _check(
      replay.status == AuthUsernameMutationStatus.unchanged,
      'idempotent replay',
    );
  });

  await _case('change.concurrent-target-reservation', () async {
    final first = await store.registerUsername(
      _registration('change-target-a', 'change-target-before-a'),
    );
    final second = await store.registerUsername(
      _registration('change-target-b', 'change-target-before-b'),
    );
    final outcomes = await Future.wait([
      Future.sync(
        () => store.changeUsername(
          _change(
            first,
            from: 'change-target-before-a',
            to: 'change-shared-target',
          ),
        ),
      ),
      Future.sync(
        () => store.changeUsername(
          _change(
            second,
            from: 'change-target-before-b',
            to: 'change-shared-target',
          ),
        ),
      ),
    ]);
    _check(
      outcomes
              .where(
                (result) => result.status == AuthUsernameMutationStatus.changed,
              )
              .length ==
          1,
      'shared target winner',
    );
    _check(
      outcomes
              .where(
                (result) =>
                    result.status == AuthUsernameMutationStatus.conflict,
              )
              .length ==
          1,
      'shared target conflict',
    );
    final winnerIndex = outcomes.indexWhere((result) => result.succeeded);
    final loser = winnerIndex == 0 ? second : first;
    _check(
      (await store.findByUsername('change-shared-target'))?.userId ==
          outcomes[winnerIndex].user?.id,
      'shared target ownership',
    );
    _check(
      (await store.findUsernameForUser(loser.user!.id))?.identifier ==
          (winnerIndex == 0
              ? 'change-target-before-b'
              : 'change-target-before-a'),
      'loser reservation preserved',
    );
  });

  await _case('availability.disabled-and-locked', () async {
    final disabled = await store.registerUsername(
      _registration('disabled', 'disabled-before'),
    );
    final disabledUser = disabled.user!;
    await root.users.update(
      AuthUser(
        id: disabledUser.id,
        email: disabledUser.email,
        name: disabledUser.name,
        attributes: <String, dynamic>{
          ...disabledUser.attributes,
          'disabled': true,
        },
      ),
    );
    final disabledResult = await store.changeUsername(
      _change(disabled, from: 'disabled-before', to: 'disabled-after'),
    );
    _check(
      disabledResult.status == AuthUsernameMutationStatus.userUnavailable,
      'disabled result',
    );
    if (root is AuthAccountStateStore) {
      final locked = await store.registerUsername(
        _registration('locked', 'locked-before'),
      );
      await (root as AuthAccountStateStore).upsert(
        AuthAccountState(
          userId: locked.user!.id,
          lockedUntil: DateTime.utc(2035),
        ),
      );
      final lockedResult = await store.changeUsername(
        _change(locked, from: 'locked-before', to: 'locked-after'),
      );
      _check(
        lockedResult.status == AuthUsernameMutationStatus.userUnavailable,
        'locked result',
      );
    }
  });

  final armFault = fixture.armFault;
  if (armFault != null) {
    await _case('fault.registration-rollback', () async {
      await armFault(AuthUsernameFaultPoint.registrationAfterUserWrite);
      final command = _registration('fault-register', 'fault-register-name');
      final error = await _capture(() => store.registerUsername(command));
      _check(error != null, 'fault surfaced');
      _check(
        await root.users.findById(command.user.id) == null,
        'user rollback',
      );
      _check(
        await store.findByUsername(command.credential.identifier) == null,
        'identifier rollback',
      );
      _check(
        (await store.registerUsername(command)).status ==
            AuthUsernameMutationStatus.created,
        'retry after rollback',
      );
    });

    await _case('fault.change-rollback', () async {
      final registered = await store.registerUsername(
        _registration('fault-change', 'fault-change-before'),
      );
      await armFault(AuthUsernameFaultPoint.changeAfterCredentialWrite);
      final error = await _capture(
        () => store.changeUsername(
          _change(
            registered,
            from: 'fault-change-before',
            to: 'fault-change-after',
          ),
        ),
      );
      _check(error != null, 'fault surfaced');
      _check(
        (await store.findUsernameForUser(registered.user!.id))?.identifier ==
            'fault-change-before',
        'credential rollback',
      );
      _check(
        (await root.users.findById(
              registered.user!.id,
            ))?.attributes['username'] ==
            'fault-change-before',
        'projection rollback',
      );
      _check(
        (await store.changeUsername(
              _change(
                registered,
                from: 'fault-change-before',
                to: 'fault-change-after',
              ),
            )).status ==
            AuthUsernameMutationStatus.changed,
        'retry after rollback',
      );
    });

    await _case('fault.removal-rollback', () async {
      final registered = await store.registerUsername(
        _registration('fault-remove', 'fault-remove-name'),
      );
      final userId = registered.user!.id;
      await root.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'fault-remove-account',
          userId: userId,
        ),
      );
      await armFault(AuthUsernameFaultPoint.removalAfterUserWrite);
      final error = await _capture(
        () => store.removeUsernameIfSafe(
          AuthUsernameRemovalCommand(
            userId: userId,
            credentialId: registered.credential!.id,
            loadInventory: () => authenticationMethods.snapshotForUser(userId),
          ),
        ),
      );
      _check(error != null, 'fault surfaced');
      _check(
        (await store.findUsernameForUser(userId))?.identifier ==
            'fault-remove-name',
        'credential rollback',
      );
      _check(
        (await root.users.findById(userId))?.attributes['username'] ==
            'fault-remove-name',
        'projection rollback',
      );
      _check(
        await store.removeUsernameIfSafe(
              AuthUsernameRemovalCommand(
                userId: userId,
                credentialId: registered.credential!.id,
                loadInventory: () =>
                    authenticationMethods.snapshotForUser(userId),
              ),
            ) ==
            AuthAuthenticationMethodMutationResult.mutated,
        'retry after rollback',
      );
    });
  }

  await _case('removal.inventory-and-replay', () async {
    final registered = await store.registerUsername(
      _registration('remove', 'remove-name'),
    );
    final userId = registered.user!.id;
    await root.accounts.link(
      AuthAccount(
        providerId: 'github',
        providerAccountId: 'remove-account',
        userId: userId,
      ),
    );
    final first = await store.removeUsernameIfSafe(
      AuthUsernameRemovalCommand(
        userId: userId,
        credentialId: registered.credential!.id,
        loadInventory: () => authenticationMethods.snapshotForUser(userId),
      ),
    );
    _check(first == AuthAuthenticationMethodMutationResult.mutated, 'removed');
    final replay = await store.removeUsernameIfSafe(
      AuthUsernameRemovalCommand(
        userId: userId,
        credentialId: registered.credential!.id,
        loadInventory: () => authenticationMethods.snapshotForUser(userId),
      ),
    );
    _check(replay == AuthAuthenticationMethodMutationResult.notFound, 'replay');
    _check(
      !(await root.users.findById(userId))!.attributes.containsKey('username'),
      'projection removal',
    );
  });

  if (root is AuthAdminStoreCapabilities &&
      root is AuthUserDeletionCoordinatorHost) {
    await _case('hard-deletion.releases-identifier', () async {
      (root as AuthUserDeletionCoordinatorHost)
          .bindUserDeletionPlanContributors(const []);
      final registered = await store.registerUsername(
        _registration('hard-delete', 'hard-delete-name'),
      );
      _check(
        await (root as AuthAdminStoreCapabilities).deleteUserForAdministration(
          registered.user!.id,
        ),
        'hard deletion',
      );
      _check(await store.findByUsername('hard-delete-name') == null, 'cleanup');
      final reused = await store.registerUsername(
        _registration('hard-delete-reuse', 'hard-delete-name'),
      );
      _check(reused.succeeded, 'identifier reuse');
    });
  }
}

AuthUsernameRegistrationCommand _registration(String id, String username) {
  final now = DateTime.utc(2030);
  final user = AuthUser(
    id: '$id-user',
    email: '$id@example.test',
    name: username,
    attributes: <String, dynamic>{'username': username},
  );
  return AuthUsernameRegistrationCommand(
    user: user,
    credential: AuthPasswordCredential(
      id: '$id-credential',
      userId: user.id,
      identifier: username,
      passwordHash: 'encoded-hash',
      createdAt: now,
      updatedAt: now,
    ),
  );
}

AuthUsernameChangeCommand _change(
  AuthUsernameMutationResult registered, {
  required String from,
  required String to,
}) => AuthUsernameChangeCommand(
  userId: registered.user!.id,
  credentialId: registered.credential!.id,
  expectedUsername: from,
  username: to,
  updatedAt: DateTime.utc(2031),
);

final class _UsernameInventory
    implements
        AuthAuthenticationMethodInventoryContributor,
        AuthAuthenticationMethodInventoryBinding {
  const _UsernameInventory(this.store, this.root);

  final AuthUsernameStore store;
  final AuthStore root;

  @override
  String get authenticationMethodNamespace => 'username';

  @override
  Object get authenticationMethodStore => root;

  @override
  Set<AuthAuthenticationMethodKind> get authenticationMethodKinds => const {
    AuthAuthenticationMethodKind.username,
  };

  @override
  Future<AuthAuthenticationMethodSnapshot> authenticationMethodsForUser(
    String requestedUserId,
  ) async {
    final credential = await store.findUsernameForUser(requestedUserId);
    return AuthAuthenticationMethodSnapshot.complete([
      if (credential?.enabled ?? false)
        AuthAuthenticationMethod.username(credential!.id),
    ]);
  }
}

final class _OAuthInventory
    implements
        AuthAuthenticationMethodInventoryContributor,
        AuthAuthenticationMethodInventoryBinding {
  const _OAuthInventory(this.store);

  final AuthAccountStore store;

  @override
  String get authenticationMethodNamespace => 'oauth';

  @override
  Object get authenticationMethodStore => store;

  @override
  Set<AuthAuthenticationMethodKind> get authenticationMethodKinds => const {
    AuthAuthenticationMethodKind.oauthProvider,
  };

  @override
  Future<AuthAuthenticationMethodSnapshot> authenticationMethodsForUser(
    String requestedUserId,
  ) async => AuthAuthenticationMethodSnapshot.complete([
    for (final account in await store.listForUser(requestedUserId))
      AuthAuthenticationMethod.oauthProvider(
        providerId: account.providerId,
        providerAccountId: account.providerAccountId,
      ),
  ]);
}

Future<Object?> _capture(FutureOr<Object?> Function() operation) async {
  try {
    await Future.sync(operation);
    return null;
  } catch (error) {
    return error;
  }
}

Future<void> _case(String id, Future<void> Function() body) async {
  try {
    await body();
  } on AuthUsernameStoreConformanceFailure {
    rethrow;
  } catch (error) {
    throw AuthUsernameStoreConformanceFailure(id, error);
  }
}

void _check(bool condition, String label) {
  if (!condition) throw StateError(label);
}
