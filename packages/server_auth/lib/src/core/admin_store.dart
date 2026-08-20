import 'dart:async';

import 'account_policy.dart';
import 'admin_models.dart';
import 'deletion_transaction.dart';
import 'exceptions.dart';
import 'models.dart';
import 'store.dart';

/// A typed mutation executed entirely by an [AuthAdminStore].
sealed class AuthAdminMutation<T> {
  const AuthAdminMutation({this.authorization});

  final AuthAdminMutationAuthorization? authorization;
}

final class AuthAdminCreateUserMutation
    extends AuthAdminMutation<AuthAdminUser> {
  const AuthAdminCreateUserMutation({
    required super.authorization,
    required this.user,
    required this.credential,
  });

  final AuthUser user;
  final AuthPasswordCredential credential;
}

final class AuthAdminUpdateUserMutation
    extends AuthAdminMutation<AuthAdminUser> {
  const AuthAdminUpdateUserMutation({
    required super.authorization,
    required this.expectedUser,
    required this.user,
    required this.revokeAccess,
  });

  final AuthUser expectedUser;
  final AuthUser user;
  final bool revokeAccess;
}

final class AuthAdminReplaceRolesMutation
    extends AuthAdminMutation<AuthAdminUser> {
  const AuthAdminReplaceRolesMutation({
    required super.authorization,
    required this.userId,
    required this.roles,
  });

  final String userId;
  final List<String> roles;
}

/// Trusted bootstrap-only role grant. This command is never route-contributed.
final class AuthAdminTrustedReplaceRolesMutation
    extends AuthAdminMutation<AuthAdminUser> {
  const AuthAdminTrustedReplaceRolesMutation({
    required this.userId,
    required this.roles,
    required this.administratorRoles,
    required this.administratorUserIds,
  });

  final String userId;
  final List<String> roles;
  final Set<String> administratorRoles;
  final Set<String> administratorUserIds;
}

final class AuthAdminSetPasswordMutation
    extends AuthAdminMutation<AuthAdminUser> {
  const AuthAdminSetPasswordMutation({
    required super.authorization,
    required this.userId,
    required this.credential,
  });

  final String userId;
  final AuthPasswordCredential credential;
}

final class AuthAdminSetBanMutation extends AuthAdminMutation<AuthAdminUser> {
  const AuthAdminSetBanMutation({
    required super.authorization,
    required this.userId,
    required this.banned,
    this.reason,
    this.expiresAt,
  });

  final String userId;
  final bool banned;
  final String? reason;
  final DateTime? expiresAt;
}

enum AuthAdminAccountStateAction { disable, enable, verifyEmail, unlock }

final class AuthAdminSetAccountStateMutation
    extends AuthAdminMutation<AuthAdminUser> {
  const AuthAdminSetAccountStateMutation({
    required super.authorization,
    required this.userId,
    required this.action,
    this.reason,
  });

  final String userId;
  final AuthAdminAccountStateAction action;
  final String? reason;
}

final class AuthAdminDeleteUserMutation extends AuthAdminMutation<bool> {
  const AuthAdminDeleteUserMutation({
    required super.authorization,
    required this.userId,
  });

  final String userId;
}

final class AuthAdminRevokeSessionMutation extends AuthAdminMutation<bool> {
  const AuthAdminRevokeSessionMutation({
    required super.authorization,
    required this.userId,
    required this.sessionId,
  });

  final String userId;
  final String sessionId;
}

final class AuthAdminRevokeSessionsMutation extends AuthAdminMutation<int> {
  const AuthAdminRevokeSessionsMutation({
    required super.authorization,
    required this.userId,
  });

  final String userId;
}

final class AuthAdminImpersonationStartDecision {
  const AuthAdminImpersonationStartDecision({
    required this.actor,
    required this.target,
  });

  final AuthUser actor;
  final AuthAdminUser target;
}

final class AuthAdminPrepareImpersonationMutation
    extends AuthAdminMutation<AuthAdminImpersonationStartDecision> {
  const AuthAdminPrepareImpersonationMutation({
    required super.authorization,
    required this.userId,
    required this.currentSessionId,
  });

  final String userId;
  final String currentSessionId;
}

final class AuthAdminImpersonationStopDecision {
  const AuthAdminImpersonationStopDecision({required this.actor});

  final AuthAdminUser? actor;
}

final class AuthAdminPrepareStopImpersonatingMutation
    extends AuthAdminMutation<AuthAdminImpersonationStopDecision> {
  const AuthAdminPrepareStopImpersonatingMutation({
    required this.currentUserId,
    required this.currentSessionId,
  });

  final String currentUserId;
  final String currentSessionId;
}

/// Stable fault points exposed only by the in-memory test adapter.
enum AuthAdminInMemoryFaultPoint { afterMutation }

typedef AuthAdminInMemoryFaultInjector =
    FutureOr<void> Function(
      AuthAdminInMemoryFaultPoint point,
      AuthAdminMutation<dynamic> mutation,
    );

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
  FutureOr<List<AuthAdminAuditRecord>> listAuditRecords({String? targetUserId});

  /// Re-authorizes and commits one typed operation in the adapter transaction.
  FutureOr<T> execute<T>(AuthAdminMutation<T> mutation);
}

/// Serialized admin store for tests and local development.
///
/// It deliberately requires an [AuthStore] that exposes
/// [AuthAdminStoreCapabilities], ensuring admin mutations update the same user
/// records used by sign-in and session resolution.
final class InMemoryAuthAdminStore
    implements AuthAdminStore, AuthInMemoryUserDeletionStore {
  InMemoryAuthAdminStore(
    AuthStore coreStore, {
    AuthAdminInMemoryFaultInjector? faultInjector,
    DateTime Function()? clock,
  }) : _core = _requireCore(coreStore),
       _faultInjector = faultInjector,
       _clock = clock ?? DateTime.now,
       _capabilities = _requireCapabilities(coreStore);

  final InMemoryAuthStore _core;
  final AuthAdminStoreCapabilities _capabilities;
  final AuthAdminInMemoryFaultInjector? _faultInjector;
  final DateTime Function() _clock;
  final Map<String, AuthAdminUserState> _states = {};
  final List<AuthAdminAuditRecord> _auditRecords = <AuthAdminAuditRecord>[];
  int _auditSequence = 0;
  Future<void> _tail = Future<void>.value();

  @override
  Set<String> get atomicUserDataNamespaces => Set.unmodifiable({
    'core',
    if (_core case AuthUserDeletionCoordinatorHost host)
      ...host.userDeletionCoordinator.requiredUserDeletionNamespaces,
  });

  static AuthAdminStoreCapabilities _requireCapabilities(AuthStore store) {
    if (store is! AuthAdminStoreCapabilities) {
      throw ArgumentError(
        'InMemoryAuthAdminStore requires AuthAdminStoreCapabilities.',
      );
    }
    return store as AuthAdminStoreCapabilities;
  }

  static InMemoryAuthStore _requireCore(AuthStore store) {
    if (store is! InMemoryAuthStore) {
      throw ArgumentError(
        'InMemoryAuthAdminStore requires InMemoryAuthStore so admin commands '
        'can roll back the complete local persistence domain.',
      );
    }
    return store;
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

  @override
  Object captureDeletionState() => Map<String, AuthAdminUserState>.of(_states);

  @override
  void restoreDeletionState(Object state) {
    _states
      ..clear()
      ..addAll(state as Map<String, AuthAdminUserState>);
  }

  @override
  Future<void> deleteUserDataForDeletion(String userId) async {
    _states.remove(userId.trim());
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
  Future<List<AuthAdminAuditRecord>> listAuditRecords({String? targetUserId}) =>
      _atomic(() async {
        final target = targetUserId?.trim();
        return List<AuthAdminAuditRecord>.unmodifiable(
          _auditRecords.where(
            (record) => target == null || record.targetUserId == target,
          ),
        );
      });

  @override
  Future<T> execute<T>(AuthAdminMutation<T> mutation) => _transaction(() async {
    final authorization = mutation.authorization;
    if (authorization != null) await _authorize(authorization);
    final Object? result;
    if (mutation is AuthAdminCreateUserMutation) {
      result = await _createUser(mutation as AuthAdminCreateUserMutation);
    } else if (mutation is AuthAdminUpdateUserMutation) {
      result = await _updateUser(mutation as AuthAdminUpdateUserMutation);
    } else if (mutation is AuthAdminReplaceRolesMutation) {
      result = await _replaceRoles(mutation as AuthAdminReplaceRolesMutation);
    } else if (mutation is AuthAdminTrustedReplaceRolesMutation) {
      final command = mutation as AuthAdminTrustedReplaceRolesMutation;
      result = await _replaceRoles(
        AuthAdminReplaceRolesMutation(
          authorization: AuthAdminMutationAuthorization(
            actorId: command.userId,
            administratorRoles: command.administratorRoles,
            administratorUserIds: command.administratorUserIds,
            rolePermissions: const <String, AuthAdminPermissionSet>{
              'admin': <String, Iterable<String>>{
                '*': <String>['*'],
              },
            },
            requirements: const <AuthAdminPermissionRequirement>[
              AuthAdminPermissionRequirement('*', '*'),
            ],
          ),
          userId: command.userId,
          roles: command.roles,
        ),
        trusted: true,
      );
    } else if (mutation is AuthAdminSetPasswordMutation) {
      result = await _setPassword(mutation as AuthAdminSetPasswordMutation);
    } else if (mutation is AuthAdminSetBanMutation) {
      result = await _setBan(mutation as AuthAdminSetBanMutation);
    } else if (mutation is AuthAdminSetAccountStateMutation) {
      result = await _setAccountState(
        mutation as AuthAdminSetAccountStateMutation,
      );
    } else if (mutation is AuthAdminDeleteUserMutation) {
      result = await _deleteUser(mutation as AuthAdminDeleteUserMutation);
    } else if (mutation is AuthAdminRevokeSessionMutation) {
      result = await _revokeSession(mutation as AuthAdminRevokeSessionMutation);
    } else if (mutation is AuthAdminRevokeSessionsMutation) {
      result = await _revokeSessions(
        mutation as AuthAdminRevokeSessionsMutation,
      );
    } else if (mutation is AuthAdminPrepareImpersonationMutation) {
      result = await _prepareImpersonation(
        mutation as AuthAdminPrepareImpersonationMutation,
      );
    } else if (mutation is AuthAdminPrepareStopImpersonatingMutation) {
      result = await _prepareStopImpersonating(
        mutation as AuthAdminPrepareStopImpersonatingMutation,
      );
    } else {
      throw UnsupportedError(
        'Unsupported admin mutation type: ${mutation.runtimeType}.',
      );
    }
    _recordAudit(mutation);
    if (mutation is! AuthAdminDeleteUserMutation) {
      await _faultInjector?.call(
        AuthAdminInMemoryFaultPoint.afterMutation,
        mutation,
      );
    }
    return result as T;
  });

  Future<T> _transaction<T>(Future<T> Function() operation) =>
      _atomic(() async {
        final coreState = _core.captureDeletionState();
        final adminState = Map<String, AuthAdminUserState>.of(_states);
        final auditState = List<AuthAdminAuditRecord>.of(_auditRecords);
        final auditSequence = _auditSequence;
        try {
          return await operation();
        } catch (error, stackTrace) {
          _core.restoreDeletionState(coreState);
          _states
            ..clear()
            ..addAll(adminState);
          _auditRecords
            ..clear()
            ..addAll(auditState);
          _auditSequence = auditSequence;
          Error.throwWithStackTrace(error, stackTrace);
        }
      });

  void _recordAudit(AuthAdminMutation<dynamic> mutation) {
    _auditRecords.add(
      AuthAdminAuditRecord(
        id: 'admin-audit-${_auditSequence++}',
        operation: _mutationOperation(mutation),
        initiatorUserId: _mutationInitiator(mutation),
        targetUserId: _mutationTarget(mutation),
        occurredAt: _clock(),
      ),
    );
  }

  Future<AuthUser> _authorize(
    AuthAdminMutationAuthorization authorization,
  ) async {
    final actor = await _core.users.findById(authorization.actorId);
    final state = actor == null ? null : _state(actor.id);
    if (actor == null ||
        state!.disabled ||
        state.isBanned() ||
        state.isLocked() ||
        !authorization.allows(actor)) {
      throw AuthFlowException('admin_forbidden');
    }
    return actor;
  }

  Future<AuthAdminUser> _createUser(
    AuthAdminCreateUserMutation mutation,
  ) async {
    final user = mutation.user;
    final credential = mutation.credential;
    if (await _core.users.findById(user.id) != null ||
        user.email == null ||
        await _core.users.findByEmail(user.email!) != null) {
      throw AuthFlowException('user_exists');
    }
    final created = await _core.credentials.register(user, credential);
    if (created == null) throw AuthFlowException('user_exists');
    return AuthAdminUser(user: created, state: _state(created.id));
  }

  Future<AuthAdminUser> _updateUser(
    AuthAdminUpdateUserMutation mutation,
  ) async {
    final user = mutation.user;
    final current = await _core.users.findById(user.id);
    if (current == null) throw AuthFlowException('user_not_found');
    if (!_sameUser(current, mutation.expectedUser)) {
      throw AuthFlowException('stale_user_state');
    }
    final changesEmail = user.email != null && user.email != current.email;
    if (changesEmail) {
      final existing = await _core.users.findByEmail(user.email!);
      if (existing != null && existing.id != user.id) {
        throw AuthFlowException('email_taken');
      }
    }
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
    if (mutation.revokeAccess) await _revoke(updated.id);
    return AuthAdminUser(user: updated, state: _state(updated.id));
  }

  Future<AuthAdminUser> _replaceRoles(
    AuthAdminReplaceRolesMutation mutation, {
    bool trusted = false,
  }) async {
    final authorization = mutation.authorization!;
    final userId = mutation.userId;
    final roles = mutation.roles;
    final current = await _core.users.findById(userId.trim());
    if (current == null) throw AuthFlowException('user_not_found');
    final normalized = normalizeAuthAdminRoles(roles);
    if (normalized.isEmpty) throw AuthFlowException('invalid_role');
    final wasAdmin = _isAdmin(
      current,
      authorization.administratorRoles,
      authorization.administratorUserIds,
    );
    final next = AuthUser(
      id: current.id,
      email: current.email,
      name: current.name,
      image: current.image,
      roles: normalized,
      attributes: current.attributes,
    );
    if (!trusted &&
        authorization.actorId == current.id &&
        !authorization.administratorUserIds.contains(current.id) &&
        !_isAdmin(
          next,
          authorization.administratorRoles,
          authorization.administratorUserIds,
        )) {
      throw AuthFlowException('self_admin_removal');
    }
    if (wasAdmin &&
        !_isAdmin(
          next,
          authorization.administratorRoles,
          authorization.administratorUserIds,
        )) {
      await _requireAnotherAdmin(
        current.id,
        authorization.administratorRoles,
        authorization.administratorUserIds,
      );
    }
    final updated = await _capabilities.updateUserForAdministration(next);
    if (updated == null) throw AuthFlowException('user_not_found');
    await _revoke(updated.id);
    return AuthAdminUser(user: updated, state: _state(updated.id));
  }

  Future<AuthAdminUser> _setPassword(
    AuthAdminSetPasswordMutation mutation,
  ) async {
    final userId = mutation.userId;
    final credential = mutation.credential;
    final user = await _core.users.findById(userId.trim());
    if (user == null) throw AuthFlowException('user_not_found');
    final identifier = user.email;
    if (identifier == null) throw AuthFlowException('email_required');
    final existing = await _capabilities.findCredentialForUser(user.id);
    final value = existing == null
        ? AuthPasswordCredential(
            id: credential.id,
            userId: user.id,
            identifier: identifier,
            passwordHash: credential.passwordHash,
            createdAt: credential.createdAt,
            updatedAt: credential.updatedAt,
            enabled: true,
          )
        : AuthPasswordCredential(
            id: existing.id,
            userId: existing.userId,
            identifier: identifier,
            passwordHash: credential.passwordHash,
            createdAt: existing.createdAt,
            updatedAt: credential.updatedAt,
            enabled: true,
          );
    await _capabilities.upsertCredentialForAdministration(value);
    await _revoke(user.id);
    return AuthAdminUser(user: user, state: _state(user.id));
  }

  Future<AuthAdminUser> _setBan(AuthAdminSetBanMutation mutation) async {
    final userId = mutation.userId;
    final banned = mutation.banned;
    if (banned && mutation.authorization!.actorId == userId.trim()) {
      throw AuthFlowException('self_ban');
    }
    final user = await _core.users.findById(userId.trim());
    if (user == null) throw AuthFlowException('user_not_found');
    final current = _state(user.id);
    final updated = current.copyWith(
      banned: banned,
      banReason: mutation.reason?.trim(),
      banExpiresAt: mutation.expiresAt?.toUtc(),
      clearBanReason: !banned,
      clearBanExpiresAt: !banned,
      updatedAt: DateTime.now().toUtc(),
    );
    _states[user.id] = updated;
    if (banned) await _revoke(user.id);
    return AuthAdminUser(user: user, state: updated);
  }

  Future<bool> _deleteUser(AuthAdminDeleteUserMutation mutation) async {
    final authorization = mutation.authorization!;
    final userId = mutation.userId;
    if (authorization.actorId == userId.trim()) {
      throw AuthFlowException('self_delete');
    }
    final user = await _core.users.findById(userId.trim());
    if (user == null) throw AuthFlowException('user_not_found');
    if (_isAdmin(
      user,
      authorization.administratorRoles,
      authorization.administratorUserIds,
    )) {
      await _requireAnotherAdmin(
        user.id,
        authorization.administratorRoles,
        authorization.administratorUserIds,
      );
    }
    return _core.userDeletionCoordinator.deleteUser(user.id);
  }

  Future<AuthAdminUser> _setAccountState(
    AuthAdminSetAccountStateMutation mutation,
  ) async {
    final userId = mutation.userId;
    if (mutation.action == AuthAdminAccountStateAction.disable &&
        mutation.authorization!.actorId == userId.trim()) {
      throw AuthFlowException('self_disable');
    }
    final user = await _core.users.findById(userId.trim());
    if (user == null) throw AuthFlowException('user_not_found');
    final current = _state(user.id);
    final now = DateTime.now().toUtc();
    final updated = switch (mutation.action) {
      AuthAdminAccountStateAction.disable => current.copyWith(
        disabled: true,
        disabledReason: mutation.reason?.trim(),
        disabledAt: now,
        updatedAt: now,
      ),
      AuthAdminAccountStateAction.enable => current.copyWith(
        clearDisabled: true,
        clearDisabledReason: true,
        updatedAt: now,
      ),
      AuthAdminAccountStateAction.verifyEmail => current.copyWith(
        emailVerified: true,
        updatedAt: now,
      ),
      AuthAdminAccountStateAction.unlock => current.copyWith(
        clearLockedUntil: true,
        failedLoginAttempts: 0,
        updatedAt: now,
      ),
    };
    _states[user.id] = updated;
    await _persistAccountState(updated, operation: mutation.action.name);
    if (mutation.action == AuthAdminAccountStateAction.disable) {
      await _revoke(user.id);
    }
    return AuthAdminUser(user: user, state: updated);
  }

  Future<bool> _revokeSession(AuthAdminRevokeSessionMutation mutation) async {
    await _requireUser(mutation.userId);
    final revoked = await _core.sessions.revokeById(
      mutation.userId,
      mutation.sessionId,
    );
    if (revoked == null) throw AuthFlowException('session_not_found');
    return true;
  }

  Future<int> _revokeSessions(AuthAdminRevokeSessionsMutation mutation) async {
    await _requireUser(mutation.userId);
    final revoked = await _core.sessions.revokeAllForUser(mutation.userId);
    await _core.jwtVersions.rotate(mutation.userId);
    return revoked;
  }

  Future<AuthAdminImpersonationStartDecision> _prepareImpersonation(
    AuthAdminPrepareImpersonationMutation mutation,
  ) async {
    final authorization = mutation.authorization!;
    final actor = await _core.users.findById(authorization.actorId);
    if (actor == null) throw AuthFlowException('admin_forbidden');
    if (actor.id == mutation.userId.trim()) {
      throw AuthFlowException('self_impersonation');
    }
    final target = await _requireUser(mutation.userId);
    if (!target.state.canAuthenticate()) {
      throw AuthFlowException('account_unavailable');
    }
    if (_isAdmin(
          target.user,
          authorization.administratorRoles,
          authorization.administratorUserIds,
        ) &&
        !authorization.allows(
          actor,
          additionalRequirements: const <AuthAdminPermissionRequirement>[
            AuthAdminPermissionRequirement('user', 'impersonate-admins'),
          ],
        )) {
      throw AuthFlowException('admin_impersonation_forbidden');
    }
    final current = (await _core.sessions.listForUser(
      actor.id,
    )).where((session) => session.id == mutation.currentSessionId).firstOrNull;
    if (current == null || !current.isActive()) {
      throw AuthFlowException('session_not_found');
    }
    if (current.impersonatedBy != null) {
      throw AuthFlowException('impersonation_chaining_forbidden');
    }
    final revoked = await _core.sessions.revokeById(actor.id, current.id);
    if (revoked == null) throw AuthFlowException('session_not_found');
    return AuthAdminImpersonationStartDecision(actor: actor, target: target);
  }

  Future<AuthAdminImpersonationStopDecision> _prepareStopImpersonating(
    AuthAdminPrepareStopImpersonatingMutation mutation,
  ) async {
    final record = (await _core.sessions.listForUser(
      mutation.currentUserId,
    )).where((session) => session.id == mutation.currentSessionId).firstOrNull;
    if (record == null || !record.isActive()) {
      throw AuthFlowException('not_impersonating');
    }
    final actorId = record.impersonatedBy;
    if (actorId == null) throw AuthFlowException('not_impersonating');
    final revoked = await _core.sessions.revokeById(
      mutation.currentUserId,
      record.id,
    );
    if (revoked == null) throw AuthFlowException('not_impersonating');
    final actor = await _core.users.findById(actorId);
    if (actor == null) {
      return const AuthAdminImpersonationStopDecision(actor: null);
    }
    final state = _state(actor.id);
    return AuthAdminImpersonationStopDecision(
      actor: state.canAuthenticate()
          ? AuthAdminUser(user: actor, state: state)
          : null,
    );
  }

  Future<AuthAdminUser> _requireUser(String userId) async {
    final user = await _core.users.findById(userId.trim());
    if (user == null) throw AuthFlowException('user_not_found');
    return AuthAdminUser(user: user, state: _state(user.id));
  }

  Future<void> _persistAccountState(
    AuthAdminUserState state, {
    required String operation,
  }) async {
    final AuthAccountStateStore accountStates = _core;
    final current = await accountStates.find(state.userId);
    final base = current ?? AuthAccountState(userId: state.userId);
    final next = switch (operation) {
      'disable' => base.copyWith(
        disabled: true,
        disabledReason: state.disabledReason,
        disabledAt: state.disabledAt,
      ),
      'enable' => base.copyWith(clearDisabled: true),
      'verifyEmail' => base.copyWith(emailVerified: true),
      'unlock' => base.copyWith(clearLockedUntil: true, failedLoginAttempts: 0),
      _ => base,
    };
    await accountStates.upsert(next);
  }

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

  bool _sameUser(AuthUser left, AuthUser right) =>
      left.id == right.id &&
      left.email == right.email &&
      left.name == right.name &&
      left.image == right.image &&
      _sameList(left.roles, right.roles) &&
      _sameMap(left.attributes, right.attributes);

  bool _sameList(List<Object?> left, List<Object?> right) =>
      left.length == right.length &&
      left.indexed.every((entry) => entry.$2 == right[entry.$1]);

  bool _sameMap(Map<String, dynamic> left, Map<String, dynamic> right) =>
      left.length == right.length &&
      left.entries.every((entry) => right[entry.key] == entry.value);
}

String _mutationOperation(AuthAdminMutation<dynamic> mutation) =>
    switch (mutation) {
      AuthAdminCreateUserMutation() => 'admin.createUser',
      AuthAdminUpdateUserMutation() => 'admin.updateUser',
      AuthAdminReplaceRolesMutation() => 'admin.setRole',
      AuthAdminTrustedReplaceRolesMutation() => 'admin.trustedSetRole',
      AuthAdminSetPasswordMutation() => 'admin.setUserPassword',
      AuthAdminSetBanMutation(:final banned) =>
        banned ? 'admin.banUser' : 'admin.unbanUser',
      AuthAdminSetAccountStateMutation(:final action) => switch (action) {
        AuthAdminAccountStateAction.disable => 'admin.disableUser',
        AuthAdminAccountStateAction.enable => 'admin.enableUser',
        AuthAdminAccountStateAction.verifyEmail => 'admin.verifyEmail',
        AuthAdminAccountStateAction.unlock => 'admin.unlockUser',
      },
      AuthAdminDeleteUserMutation() => 'admin.removeUser',
      AuthAdminRevokeSessionMutation() => 'admin.revokeUserSession',
      AuthAdminRevokeSessionsMutation() => 'admin.revokeUserSessions',
      AuthAdminPrepareImpersonationMutation() => 'admin.impersonateUser',
      AuthAdminPrepareStopImpersonatingMutation() => 'admin.stopImpersonating',
    };

String _mutationInitiator(AuthAdminMutation<dynamic> mutation) =>
    mutation.authorization?.actorId ??
    switch (mutation) {
      AuthAdminTrustedReplaceRolesMutation(:final userId) => userId,
      AuthAdminPrepareStopImpersonatingMutation(:final currentUserId) =>
        currentUserId,
      _ => throw StateError('Admin mutation has no initiating user.'),
    };

String _mutationTarget(AuthAdminMutation<dynamic> mutation) =>
    switch (mutation) {
      AuthAdminCreateUserMutation(:final user) => user.id,
      AuthAdminUpdateUserMutation(:final user) => user.id,
      AuthAdminReplaceRolesMutation(:final userId) ||
      AuthAdminTrustedReplaceRolesMutation(:final userId) ||
      AuthAdminSetPasswordMutation(:final userId) ||
      AuthAdminSetBanMutation(:final userId) ||
      AuthAdminSetAccountStateMutation(:final userId) ||
      AuthAdminDeleteUserMutation(:final userId) ||
      AuthAdminRevokeSessionMutation(:final userId) ||
      AuthAdminRevokeSessionsMutation(:final userId) ||
      AuthAdminPrepareImpersonationMutation(:final userId) => userId,
      AuthAdminPrepareStopImpersonatingMutation(:final currentUserId) =>
        currentUserId,
    };
