import 'dart:async';

import 'admin_models.dart';
import 'exceptions.dart';
import 'plugin.dart';
import 'models.dart';
import 'store.dart';

/// Plugin-owned persistence contract for administrative user operations.
///
/// Mutating methods that mention revocation must commit the user/admin state,
/// server-session revocation, and JWT version rotation atomically.
abstract interface class AuthAdminStore {
  /// User-owned namespaces covered by the hard-delete transaction.
  Set<String> get atomicUserDataNamespaces;

  FutureOr<AuthAdminUser?> findUser(String userId);
  FutureOr<AuthAdminUser?> findUserByEmail(String email);
  FutureOr<List<AuthAdminUser>> listUsers();
  FutureOr<AuthAdminUser> createUser(
    AuthUser user,
    AuthPasswordCredential credential,
  );
  FutureOr<AuthAdminUser> updateUser(
    AuthUser user, {
    bool revokeAccess = false,
  });
  FutureOr<AuthAdminUser> replaceRoles(
    String userId,
    Iterable<String> roles, {
    required Set<String> administratorRoles,
    required Set<String> administratorUserIds,
  });
  FutureOr<AuthAdminUser> setPassword(
    String userId,
    AuthPasswordCredential credential,
  );
  FutureOr<AuthAdminUser> setBan(
    String userId, {
    required bool banned,
    String? reason,
    DateTime? expiresAt,
  });
  FutureOr<bool> deleteUser(
    String userId, {
    required Set<String> administratorRoles,
    required Set<String> administratorUserIds,
  });
}

/// Serialized admin store for tests and local development.
///
/// It deliberately requires an [AuthStore] that exposes
/// [AuthAdminStoreCapabilities], ensuring admin mutations update the same user
/// records used by sign-in and session resolution.
final class InMemoryAuthAdminStore implements AuthAdminStore {
  InMemoryAuthAdminStore(AuthStore coreStore)
    : _core = coreStore,
      _capabilities = _requireCapabilities(coreStore);

  final AuthStore _core;
  final AuthAdminStoreCapabilities _capabilities;
  final Map<String, AuthAdminUserState> _states = {};
  List<AuthUserDataDeletionContributor> _userDataContributors = const [];
  Future<void> _tail = Future<void>.value();

  @override
  Set<String> get atomicUserDataNamespaces => Set.unmodifiable({
    'core',
    'admin',
    ..._userDataContributors.map((value) => value.userDataNamespace),
  });

  static AuthAdminStoreCapabilities _requireCapabilities(AuthStore store) {
    if (store is! AuthAdminStoreCapabilities) {
      throw ArgumentError(
        'InMemoryAuthAdminStore requires AuthAdminStoreCapabilities.',
      );
    }
    return store as AuthAdminStoreCapabilities;
  }

  Future<T> _atomic<T>(FutureOr<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void composeUserDataContributors(
    Iterable<AuthUserDataDeletionContributor> contributors,
  ) {
    _userDataContributors = List.unmodifiable(contributors);
  }

  AuthAdminUserState _state(String userId) =>
      _states.putIfAbsent(userId, () => AuthAdminUserState(userId: userId));

  @override
  Future<AuthAdminUser?> findUser(String userId) => _atomic(() async {
    final user = await _core.users.findById(userId.trim());
    return user == null
        ? null
        : AuthAdminUser(user: user, state: _state(user.id));
  });

  @override
  Future<AuthAdminUser?> findUserByEmail(String email) => _atomic(() async {
    final user = await _core.users.findByEmail(email.trim().toLowerCase());
    return user == null
        ? null
        : AuthAdminUser(user: user, state: _state(user.id));
  });

  @override
  Future<List<AuthAdminUser>> listUsers() => _atomic(() async {
    final users = await _capabilities.listUsersForAdministration();
    return List<AuthAdminUser>.unmodifiable(
      users.map((user) => AuthAdminUser(user: user, state: _state(user.id))),
    );
  });

  @override
  Future<AuthAdminUser> createUser(
    AuthUser user,
    AuthPasswordCredential credential,
  ) => _atomic(() async {
    if (await _core.users.findById(user.id) != null ||
        user.email == null ||
        await _core.users.findByEmail(user.email!) != null) {
      throw AuthFlowException('user_exists');
    }
    final created = await _core.credentials.register(user, credential);
    if (created == null) throw AuthFlowException('user_exists');
    return AuthAdminUser(user: created, state: _state(created.id));
  });

  @override
  Future<AuthAdminUser> updateUser(
    AuthUser user, {
    bool revokeAccess = false,
  }) => _atomic(() async {
    final current = await _core.users.findById(user.id);
    if (current == null) throw AuthFlowException('user_not_found');
    final changesEmail = user.email != null && user.email != current.email;
    final credential = changesEmail
        ? await _capabilities.findCredentialForUser(user.id)
        : null;
    if (credential != null) {
      await _capabilities.upsertCredentialForAdministration(
        AuthPasswordCredential(
          id: credential.id,
          userId: credential.userId,
          identifier: user.email!,
          passwordHash: credential.passwordHash,
          createdAt: credential.createdAt,
          updatedAt: DateTime.now().toUtc(),
          enabled: credential.enabled,
        ),
      );
    }
    final updated = await _capabilities.updateUserForAdministration(user);
    if (updated == null) {
      if (credential != null) {
        await _capabilities.upsertCredentialForAdministration(credential);
      }
      throw AuthFlowException('email_taken');
    }
    if (revokeAccess) await _revoke(updated.id);
    return AuthAdminUser(user: updated, state: _state(updated.id));
  });

  @override
  Future<AuthAdminUser> replaceRoles(
    String userId,
    Iterable<String> roles, {
    required Set<String> administratorRoles,
    required Set<String> administratorUserIds,
  }) => _atomic(() async {
    final current = await _core.users.findById(userId.trim());
    if (current == null) throw AuthFlowException('user_not_found');
    final normalized = normalizeAuthAdminRoles(roles);
    if (normalized.isEmpty) throw AuthFlowException('invalid_role');
    final wasAdmin = _isAdmin(
      current,
      administratorRoles,
      administratorUserIds,
    );
    final next = AuthUser(
      id: current.id,
      email: current.email,
      name: current.name,
      image: current.image,
      roles: normalized,
      attributes: current.attributes,
    );
    if (wasAdmin && !_isAdmin(next, administratorRoles, administratorUserIds)) {
      await _requireAnotherAdmin(
        current.id,
        administratorRoles,
        administratorUserIds,
      );
    }
    final updated = await _capabilities.updateUserForAdministration(next);
    if (updated == null) throw AuthFlowException('user_not_found');
    await _revoke(updated.id);
    return AuthAdminUser(user: updated, state: _state(updated.id));
  });

  @override
  Future<AuthAdminUser> setPassword(
    String userId,
    AuthPasswordCredential credential,
  ) => _atomic(() async {
    final user = await _core.users.findById(userId.trim());
    if (user == null) throw AuthFlowException('user_not_found');
    final existing = await _capabilities.findCredentialForUser(user.id);
    final value = existing == null
        ? credential
        : AuthPasswordCredential(
            id: existing.id,
            userId: existing.userId,
            identifier: user.email ?? existing.identifier,
            passwordHash: credential.passwordHash,
            createdAt: existing.createdAt,
            updatedAt: credential.updatedAt,
            enabled: true,
          );
    await _capabilities.upsertCredentialForAdministration(value);
    await _revoke(user.id);
    return AuthAdminUser(user: user, state: _state(user.id));
  });

  @override
  Future<AuthAdminUser> setBan(
    String userId, {
    required bool banned,
    String? reason,
    DateTime? expiresAt,
  }) => _atomic(() async {
    final user = await _core.users.findById(userId.trim());
    if (user == null) throw AuthFlowException('user_not_found');
    final current = _state(user.id);
    final updated = current.copyWith(
      banned: banned,
      banReason: reason?.trim(),
      banExpiresAt: expiresAt?.toUtc(),
      clearBanReason: !banned,
      clearBanExpiresAt: !banned,
      updatedAt: DateTime.now().toUtc(),
    );
    _states[user.id] = updated;
    if (banned) await _revoke(user.id);
    return AuthAdminUser(user: user, state: updated);
  });

  @override
  Future<bool> deleteUser(
    String userId, {
    required Set<String> administratorRoles,
    required Set<String> administratorUserIds,
  }) => _atomic(() async {
    final user = await _core.users.findById(userId.trim());
    if (user == null) throw AuthFlowException('user_not_found');
    if (_isAdmin(user, administratorRoles, administratorUserIds)) {
      await _requireAnotherAdmin(
        user.id,
        administratorRoles,
        administratorUserIds,
      );
    }
    for (final contributor in _userDataContributors) {
      await contributor.validateUserDeletion(user.id);
    }
    for (final contributor in _userDataContributors) {
      await contributor.deleteUserData(user.id);
    }
    await _revoke(user.id);
    final deleted = await _capabilities.deleteUserForAdministration(user.id);
    if (deleted) _states.remove(user.id);
    return deleted;
  });

  Future<void> _revoke(String userId) async {
    await _core.sessions.revokeAllForUser(userId);
    await _core.jwtVersions.rotate(userId);
  }

  Future<void> _requireAnotherAdmin(
    String excludedUserId,
    Set<String> roles,
    Set<String> ids,
  ) async {
    final users = await _capabilities.listUsersForAdministration();
    if (!users.any(
      (user) => user.id != excludedUserId && _isAdmin(user, roles, ids),
    )) {
      throw AuthFlowException('last_admin');
    }
  }

  bool _isAdmin(AuthUser user, Set<String> roles, Set<String> ids) =>
      ids.contains(user.id) || user.roles.any(roles.contains);
}
