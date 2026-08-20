import 'dart:async';

import 'admin_models.dart';
import 'admin_store.dart';
import 'exceptions.dart';
import 'plugin.dart';
import 'models.dart';
import 'password_hasher.dart';
import 'password_policy.dart';
import 'rate_limit.dart';
import 'store.dart';
import 'tokens.dart' show secureRandomToken;
import 'users.dart' show normalizeAuthEmail;

const String authAdminPluginId = 'admin';

typedef AuthAdminPermissionSet = Map<String, Iterable<String>>;
typedef AuthAdminFailureReporter =
    FutureOr<void> Function(AuthAdminInternalFailure failure);
typedef AuthAdminEventSink =
    FutureOr<void> Function(AuthAdminLifecycleEvent event);
typedef AuthAdminDeletionGuard = FutureOr<void> Function(String userId);

final class AuthAdminOptions<TContext> {
  const AuthAdminOptions({
    this.adminRoles = const {'admin'},
    this.adminUserIds = const {},
    this.roles,
    this.defaultRole = 'user',
    this.defaultBanReason = 'No reason provided',
    this.impersonationDuration = const Duration(hours: 1),
    this.maximumPageSize = 100,
    this.hooks = const AuthAdminHooks(),
    this.validateDeletion,
    this.reportFailure,
    this.emitEvent,
  });

  final Set<String> adminRoles;
  final Set<String> adminUserIds;
  final Map<String, AuthAdminPermissionSet>? roles;
  final String defaultRole;
  final String defaultBanReason;
  final Duration impersonationDuration;
  final int maximumPageSize;
  final AuthAdminHooks<TContext> hooks;
  final AuthAdminDeletionGuard? validateDeletion;
  final AuthAdminFailureReporter? reportFailure;
  final AuthAdminEventSink? emitEvent;
}

final class AuthAdminAccessControl {
  AuthAdminAccessControl({Map<String, AuthAdminPermissionSet>? roles})
    : roles = Map<String, Map<String, List<String>>>.unmodifiable({
        for (final entry in {...defaultRoles, ...?roles}.entries)
          entry.key.trim().toLowerCase(): _normalizePermissions(entry.value),
      });

  static const Map<String, AuthAdminPermissionSet> defaultRoles = {
    'admin': {
      'user': [
        'create',
        'list',
        'get',
        'update',
        'set-role',
        'set-password',
        'set-email',
        'ban',
        'delete',
        'impersonate',
      ],
      'session': ['list', 'revoke'],
    },
    'user': <String, Iterable<String>>{},
  };

  final Map<String, Map<String, List<String>>> roles;

  bool allows(Iterable<String> userRoles, String resource, String action) {
    final normalizedResource = resource.trim().toLowerCase();
    final normalizedAction = action.trim().toLowerCase();
    if (normalizedResource.isEmpty || normalizedAction.isEmpty) return false;
    for (final role in normalizeAuthAdminRoles(userRoles)) {
      final permissions = roles[role];
      final actions = permissions?[normalizedResource] ?? permissions?['*'];
      if (actions?.any((value) => value == normalizedAction || value == '*') ==
          true) {
        return true;
      }
    }
    return false;
  }
}

final class AdminPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthAuthenticationPolicyContributor<TContext>,
        AuthServerPluginTopologyAware<TContext> {
  AdminPlugin({required this.store, AuthAdminOptions<TContext>? options})
    : options = options ?? AuthAdminOptions<TContext>(),
      accessControl = AuthAdminAccessControl(roles: options?.roles) {
    if (this.options.impersonationDuration <= Duration.zero) {
      throw ArgumentError.value(
        this.options.impersonationDuration,
        'impersonationDuration',
      );
    }
    if (this.options.maximumPageSize < 1) {
      throw ArgumentError.value(
        this.options.maximumPageSize,
        'maximumPageSize',
      );
    }
  }

  @override
  String get id => authAdminPluginId;

  final AuthAdminStore store;
  final AuthAdminOptions<TContext> options;
  final AuthAdminAccessControl accessControl;
  late AuthStore _coreStore;
  late PasswordHasher _passwordHasher;
  late PasswordPolicy _passwordPolicy;
  late AuthSessionStrategy _sessionStrategy;

  Set<String> get _adminRoles =>
      normalizeAuthAdminRoles(options.adminRoles).toSet();
  Set<String> get _adminUserIds => options.adminUserIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    _coreStore = context.store;
    _passwordHasher = context.passwordHasher ?? Argon2idPasswordHasher();
    _passwordPolicy = context.passwordPolicy;
    _sessionStrategy = context.sessionStrategy;
  }

  @override
  void composePluginTopology(Iterable<AuthServerPlugin<TContext>> plugins) {
    final target = store;
    final contributors = plugins
        .whereType<AuthUserDataDeletionContributor>()
        .where((plugin) => !identical(plugin, this))
        .toList(growable: false);
    if (target is InMemoryAuthAdminStore) {
      target.composeUserDataContributors(contributors);
    }
    final required = {
      'core',
      'admin',
      ...contributors.map((value) => value.userDataNamespace),
    };
    if (!target.atomicUserDataNamespaces.containsAll(required)) {
      final missing = required.difference(target.atomicUserDataNamespaces);
      throw StateError(
        'AuthAdminStore does not atomically cover user data namespaces: '
        '${missing.join(', ')}.',
      );
    }
  }

  static const Map<String, String> _paths = {
    'admin.listUsers': '/admin/list-users',
    'admin.getUser': '/admin/get-user',
    'admin.createUser': '/admin/create-user',
    'admin.updateUser': '/admin/update-user',
    'admin.setRole': '/admin/set-role',
    'admin.setUserPassword': '/admin/set-user-password',
    'admin.banUser': '/admin/ban-user',
    'admin.unbanUser': '/admin/unban-user',
    'admin.listUserSessions': '/admin/list-user-sessions',
    'admin.revokeUserSession': '/admin/revoke-user-session',
    'admin.revokeUserSessions': '/admin/revoke-user-sessions',
    'admin.impersonateUser': '/admin/impersonate-user',
    'admin.stopImpersonating': '/admin/stop-impersonating',
    'admin.removeUser': '/admin/remove-user',
    'admin.hasPermission': '/admin/has-permission',
  };

  static const Set<String> _reads = {'admin.listUsers', 'admin.getUser'};

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints => _paths.keys
      .map((operation) {
        final method = _reads.contains(operation)
            ? AuthOperationMethod.get
            : AuthOperationMethod.post;
        return TypedAuthEndpointDescriptor<
          TContext,
          Map<String, dynamic>,
          Object?
        >(
          id: operation,
          method: method,
          path: _paths[operation]!,
          requestCodec: _mapCodec,
          responseCodec: _objectCodec,
          authentication: AuthOperationAuthentication.session,
          originPolicy: method == AuthOperationMethod.post
              ? AuthOperationOriginPolicy.browser
              : AuthOperationOriginPolicy.none,
          csrfPolicy: method == AuthOperationMethod.post
              ? AuthOperationCsrfPolicy.required
              : AuthOperationCsrfPolicy.none,
          rateLimitOperation: AuthRateLimitOperation(
            'admin',
            operation.substring('admin.'.length),
          ),
          handler: (invocation, request) =>
              _invokeEndpoint(operation, invocation, request),
        );
      })
      .toList(growable: false);

  @override
  Iterable<AuthClientOperationDescriptor> get clientOperations => endpoints.map(
    (endpoint) => AuthClientOperationDescriptor(
      id: endpoint.id,
      method: endpoint.method,
      path: endpoint.path,
      serverOnly: endpoint.serverOnly,
    ),
  );

  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations => endpoints
      .map((endpoint) => endpoint.rateLimitOperation)
      .whereType<AuthRateLimitOperation>();

  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => const [
    AuthPersistenceSchema(
      id: 'admin',
      entities: [
        AuthEntityDescriptor(
          id: 'admin_user_state',
          fields: [
            AuthFieldDescriptor(name: 'userId', kind: 'id'),
            AuthFieldDescriptor(name: 'banned', kind: 'boolean'),
            AuthFieldDescriptor(name: 'banReason', kind: 'nullable_string'),
            AuthFieldDescriptor(
              name: 'banExpiresAt',
              kind: 'nullable_datetime',
            ),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'updatedAt', kind: 'datetime'),
          ],
          relationships: [
            AuthRelationshipDescriptor(
              field: 'userId',
              targetEntity: 'user',
              cascadeDelete: true,
            ),
          ],
          uniqueConstraints: [
            ['userId'],
          ],
          indexes: [
            ['banned', 'banExpiresAt'],
          ],
        ),
      ],
      atomicOperations: [
        AuthAtomicOperationDescriptor(
          id: 'createUserWithCredential',
          description:
              'Create a normalized unique user and password credential.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'mutateUserAndRevokeAccess',
          description:
              'Change sensitive user state, revoke sessions, and rotate JWT version.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'preserveAdministrator',
          description:
              'Preserve at least one effective administrator under concurrency.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'hardDeleteUser',
          description:
              'Delete the user and every composed user-owned namespace together.',
        ),
      ],
    ),
  ];

  bool isAdministrator(AuthUser user) =>
      _adminUserIds.contains(user.id) ||
      normalizeAuthAdminRoles(user.roles).any(_adminRoles.contains);

  bool localRoleAllows(
    Iterable<String> roles,
    String resource,
    String action,
  ) => accessControl.allows(roles, resource, action);

  Future<bool> hasPermission(
    String actorId,
    String resource,
    String action,
  ) async {
    final actor = await _authoritativeUser(actorId);
    return isAdministrator(actor) &&
        accessControl.allows(_effectiveRoles(actor), resource, action);
  }

  @override
  Future<void> enforceAuthenticationPolicy(
    AuthAuthenticationPolicyRequest<TContext> request,
  ) async {
    final adminUser = await store.findUser(request.user.id);
    if (adminUser?.state.isBanned() == true) {
      throw AuthFlowException('account_unavailable');
    }
  }

  /// Trusted Dart-only bootstrap operation; never contributed as a route.
  Future<AuthAdminUser> trustedGrantAdministrator(String userId) async {
    final current = await store.findUser(userId);
    if (current == null) throw AuthFlowException('user_not_found');
    final role = _adminRoles.firstOrNull ?? 'admin';
    return store.replaceRoles(
      userId,
      {...current.user.roles, role},
      administratorRoles: _adminRoles,
      administratorUserIds: _adminUserIds,
    );
  }

  Future<Object?> _invokeEndpoint(
    String operation,
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    final actor = invocation.user;
    if (actor == null) throw AuthFlowException('unauthorized');
    switch (operation) {
      case 'admin.listUsers':
        await _require(actor.id, 'user', 'list');
        return (await _listUsers(input)).toJson();
      case 'admin.getUser':
        await _require(actor.id, 'user', 'get');
        return (await _requiredUser(_string(input, 'userId'))).toJson();
      case 'admin.createUser':
        await _require(actor.id, 'user', 'create');
        return (await _createUser(
          invocation.context,
          actor,
          input,
        )).toJson((value) => value.toJson());
      case 'admin.updateUser':
        return (await _updateUser(
          invocation.context,
          actor,
          input,
        )).toJson((value) => value.toJson());
      case 'admin.setRole':
        await _require(actor.id, 'user', 'set-role');
        return (await _setRoles(
          invocation.context,
          actor,
          input,
        )).toJson((value) => value.toJson());
      case 'admin.setUserPassword':
        await _require(actor.id, 'user', 'set-password');
        return (await _setPassword(
          invocation.context,
          actor,
          input,
        )).toJson((value) => value.toJson());
      case 'admin.banUser':
        await _require(actor.id, 'user', 'ban');
        return (await _setBan(
          invocation.context,
          actor,
          input,
          true,
        )).toJson((value) => value.toJson());
      case 'admin.unbanUser':
        await _require(actor.id, 'user', 'ban');
        return (await _setBan(
          invocation.context,
          actor,
          input,
          false,
        )).toJson((value) => value.toJson());
      case 'admin.listUserSessions':
        await _require(actor.id, 'session', 'list');
        final userId = _string(input, 'userId');
        await _requiredUser(userId);
        return {
          'sessions': (await _coreStore.sessions.listForUser(userId))
              .map(AuthAdminSession.fromRecord)
              .map((session) => session.toJson())
              .toList(),
        };
      case 'admin.revokeUserSession':
        await _require(actor.id, 'session', 'revoke');
        final userId = _string(input, 'userId');
        final value = await _coreStore.sessions.revokeById(
          userId,
          _string(input, 'sessionId'),
        );
        if (value == null) throw AuthFlowException('session_not_found');
        return {'revoked': true};
      case 'admin.revokeUserSessions':
        await _require(actor.id, 'session', 'revoke');
        final userId = _string(input, 'userId');
        await _requiredUser(userId);
        return {'revoked': await _coreStore.sessions.revokeAllForUser(userId)};
      case 'admin.impersonateUser':
        return _impersonate(invocation, actor, input);
      case 'admin.stopImpersonating':
        return _stopImpersonating(invocation, actor);
      case 'admin.removeUser':
        await _require(actor.id, 'user', 'delete');
        return (await _removeUser(
          invocation.context,
          actor,
          input,
        )).toJson((value) => value);
      case 'admin.hasPermission':
        final targetId = _optionalString(input, 'userId') ?? actor.id;
        if (targetId != actor.id) await _require(actor.id, 'user', 'get');
        return AuthAdminPermissionResult(
          allowed: await hasPermission(
            targetId,
            _string(input, 'resource'),
            _string(input, 'action'),
          ),
        ).toJson();
    }
    throw AuthFlowException('operation_not_found');
  }

  Future<AuthAdminUserPage> _listUsers(Map<String, dynamic> input) async {
    final query = AuthAdminUserQuery(
      search: _optionalString(input, 'search'),
      id: _optionalString(input, 'id'),
      email: _optionalString(input, 'email'),
      name: _optionalString(input, 'name'),
      role: _optionalString(input, 'role')?.toLowerCase(),
      banned: _optionalBool(input, 'banned'),
      sortBy: AuthAdminUserSortField.values.firstWhere(
        (value) => value.name == (_optionalString(input, 'sortBy') ?? 'id'),
        orElse: () => AuthAdminUserSortField.id,
      ),
      descending: _optionalString(input, 'sortDirection') == 'desc',
      limit: _integer(input, 'limit', 100).clamp(1, options.maximumPageSize),
      offset: _integer(input, 'offset', 0).clamp(0, 1 << 31),
    );
    var values = await store.listUsers();
    final search = query.search?.toLowerCase();
    values = values.where((value) {
      final user = value.user;
      if (query.id != null && user.id != query.id) return false;
      if (query.email != null &&
          user.email != normalizeAuthEmail(query.email!)) {
        return false;
      }
      if (query.name != null && user.name != query.name) return false;
      if (query.role != null &&
          !normalizeAuthAdminRoles(user.roles).contains(query.role)) {
        return false;
      }
      if (query.banned != null && value.state.isBanned() != query.banned) {
        return false;
      }
      return search == null ||
          user.id.toLowerCase().contains(search) ||
          (user.email?.toLowerCase().contains(search) ?? false) ||
          (user.name?.toLowerCase().contains(search) ?? false);
    }).toList();
    int compare(AuthAdminUser a, AuthAdminUser b) => switch (query.sortBy) {
      AuthAdminUserSortField.id => a.user.id.compareTo(b.user.id),
      AuthAdminUserSortField.email => (a.user.email ?? '').compareTo(
        b.user.email ?? '',
      ),
      AuthAdminUserSortField.name => (a.user.name ?? '').compareTo(
        b.user.name ?? '',
      ),
    };
    values.sort((a, b) => query.descending ? -compare(a, b) : compare(a, b));
    final total = values.length;
    final page = values.skip(query.offset).take(query.limit).toList();
    return AuthAdminUserPage(
      items: List.unmodifiable(page),
      total: total,
      limit: query.limit,
      offset: query.offset,
    );
  }

  Future<AuthAdminMutationResult<AuthAdminUser>> _createUser(
    TContext context,
    AuthUser actor,
    Map<String, dynamic> input,
  ) async {
    final password = _string(input, 'password');
    final passwordError = _passwordPolicy.validateRegistration(password);
    if (passwordError != null) throw AuthFlowException(passwordError);
    var draft = AuthAdminCreateUserDraft(
      id: _optionalString(input, 'id') ?? secureRandomToken(length: 16),
      email: _requiredEmail(input, 'email'),
      name: _string(input, 'name'),
      image: _optionalString(input, 'image'),
      roles: _roles(input, fallback: [options.defaultRole]),
      attributes: _jsonMap(input['attributes']),
    );
    draft =
        await _before(
              options.hooks.beforeUser,
              context,
              'create',
              actor,
              draft,
              draft.id,
            )
            as AuthAdminCreateUserDraft;
    final now = DateTime.now().toUtc();
    final user = await store.createUser(
      draft.toUser(),
      AuthPasswordCredential(
        id: secureRandomToken(length: 16),
        userId: draft.id,
        identifier: draft.email,
        passwordHash: _passwordHasher.hash(password),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return _completeMutation(
      context,
      actor,
      'user.created',
      user.user.id,
      user,
      options.hooks.afterUser,
    );
  }

  Future<AuthAdminMutationResult<AuthAdminUser>> _updateUser(
    TContext context,
    AuthUser actor,
    Map<String, dynamic> input,
  ) async {
    final userId = _string(input, 'userId');
    await _require(actor.id, 'user', 'update');
    final current = await _requiredUser(userId);
    final requestedEmail = _optionalString(input, 'email');
    final email = requestedEmail == null
        ? current.user.email
        : normalizeAuthEmail(requestedEmail);
    final emailChanged = email != current.user.email;
    if (emailChanged) await _require(actor.id, 'user', 'set-email');
    var draft = AuthAdminUpdateUserDraft(
      user: current.user,
      name: _optionalString(input, 'name'),
      image: _optionalString(input, 'image'),
      clearImage: input['image'] == null && input.containsKey('image'),
      attributes: input.containsKey('attributes')
          ? _jsonMap(input['attributes'])
          : null,
    );
    draft =
        await _before(
              options.hooks.beforeUser,
              context,
              'update',
              actor,
              draft,
              userId,
            )
            as AuthAdminUpdateUserDraft;
    final updated = AuthUser(
      id: current.user.id,
      email: email,
      name: draft.name ?? current.user.name,
      image: draft.clearImage ? null : draft.image ?? current.user.image,
      roles: current.user.roles,
      attributes: draft.attributes ?? current.user.attributes,
    );
    final stored = await store.updateUser(updated, revokeAccess: emailChanged);
    return _completeMutation(
      context,
      actor,
      'user.updated',
      userId,
      stored,
      options.hooks.afterUser,
    );
  }

  Future<AuthAdminMutationResult<AuthAdminUser>> _setRoles(
    TContext context,
    AuthUser actor,
    Map<String, dynamic> input,
  ) async {
    final userId = _string(input, 'userId');
    final roles = _roles(input);
    if (actor.id == userId &&
        !_adminUserIds.contains(actor.id) &&
        !roles.any(_adminRoles.contains)) {
      throw AuthFlowException('self_admin_removal');
    }
    final transformed = await _before(
      options.hooks.beforeRole,
      context,
      'set-role',
      actor,
      roles,
      userId,
    );
    final stored = await store.replaceRoles(
      userId,
      (transformed as Iterable).map((value) => '$value'),
      administratorRoles: _adminRoles,
      administratorUserIds: _adminUserIds,
    );
    return _completeMutation(
      context,
      actor,
      'user.roles.updated',
      userId,
      stored,
      options.hooks.afterRole,
    );
  }

  Future<AuthAdminMutationResult<AuthAdminUser>> _setPassword(
    TContext context,
    AuthUser actor,
    Map<String, dynamic> input,
  ) async {
    final userId = _string(input, 'userId');
    final password = _string(input, 'newPassword');
    final error = _passwordPolicy.validateRegistration(password);
    if (error != null) throw AuthFlowException(error);
    final target = await _requiredUser(userId);
    final email = target.user.email;
    if (email == null) throw AuthFlowException('email_required');
    final now = DateTime.now().toUtc();
    final stored = await store.setPassword(
      userId,
      AuthPasswordCredential(
        id: secureRandomToken(length: 16),
        userId: userId,
        identifier: email,
        passwordHash: _passwordHasher.hash(password),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return _completeMutation(
      context,
      actor,
      'user.password.updated',
      userId,
      stored,
      options.hooks.afterUser,
    );
  }

  Future<AuthAdminMutationResult<AuthAdminUser>> _setBan(
    TContext context,
    AuthUser actor,
    Map<String, dynamic> input,
    bool banned,
  ) async {
    final userId = _string(input, 'userId');
    if (banned && actor.id == userId) throw AuthFlowException('self_ban');
    final expiresAt = _optionalDate(input['banExpiresAt']);
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now().toUtc())) {
      throw AuthFlowException('invalid_ban_expiry');
    }
    final transformed = await _before(
      options.hooks.beforeBan,
      context,
      banned ? 'ban' : 'unban',
      actor,
      <String, Object?>{
        'banned': banned,
        'reason': banned
            ? (_optionalString(input, 'banReason') ?? options.defaultBanReason)
            : null,
        'expiresAt': expiresAt,
      },
      userId,
    );
    final data = Map<String, Object?>.from(transformed as Map);
    final stored = await store.setBan(
      userId,
      banned: data['banned'] == true,
      reason: data['reason']?.toString(),
      expiresAt: data['expiresAt'] as DateTime?,
    );
    return _completeMutation(
      context,
      actor,
      banned ? 'user.banned' : 'user.unbanned',
      userId,
      stored,
      options.hooks.afterBan,
    );
  }

  Future<Object?> _impersonate(
    AuthOperationInvocation<TContext> invocation,
    AuthUser actor,
    Map<String, dynamic> input,
  ) async {
    await _require(actor.id, 'user', 'impersonate');
    if (_sessionStrategy != AuthSessionStrategy.session ||
        invocation.sessionControl?.strategy != AuthSessionStrategy.session) {
      throw AuthFlowException('impersonation_requires_server_session');
    }
    final userId = _string(input, 'userId');
    if (userId == actor.id) throw AuthFlowException('self_impersonation');
    final target = await _requiredUser(userId);
    if (target.state.isBanned()) throw AuthFlowException('account_unavailable');
    if (isAdministrator(target.user) &&
        !await hasPermission(actor.id, 'user', 'impersonate-admins')) {
      throw AuthFlowException('admin_impersonation_forbidden');
    }
    final currentId = invocation.sessionControl!.currentSessionId;
    if (currentId != null) {
      final current = (await _coreStore.sessions.listForUser(
        actor.id,
      )).where((session) => session.id == currentId).firstOrNull;
      if (current?.impersonatedBy != null) {
        throw AuthFlowException('impersonation_chaining_forbidden');
      }
    }
    await _before(
      options.hooks.beforeImpersonation,
      invocation.context,
      'start',
      actor,
      target.user.redacted(),
      userId,
    );
    final session = await invocation.sessionControl!.replaceIdentity(
      target.user,
      authenticationMethod: 'impersonation',
      maximumAge: options.impersonationDuration,
      impersonatedBy: actor.id,
    );
    final warnings = await _afterAndEmit(
      options.hooks.afterImpersonation,
      invocation.context,
      'impersonation.started',
      actor,
      userId,
      target.user.redacted(),
    );
    return AuthAdminMutationResult(
      data: session,
      warnings: warnings,
    ).toJson((value) => value.toJson());
  }

  Future<Object?> _stopImpersonating(
    AuthOperationInvocation<TContext> invocation,
    AuthUser currentUser,
  ) async {
    final control = invocation.sessionControl;
    if (control == null || control.strategy != AuthSessionStrategy.session) {
      throw AuthFlowException('impersonation_requires_server_session');
    }
    final currentId = control.currentSessionId;
    if (currentId == null) throw AuthFlowException('not_impersonating');
    final record = (await _coreStore.sessions.listForUser(
      currentUser.id,
    )).where((session) => session.id == currentId).firstOrNull;
    final actorId = record?.impersonatedBy;
    if (actorId == null) throw AuthFlowException('not_impersonating');
    final actor = await store.findUser(actorId);
    if (actor == null || actor.state.isBanned()) {
      await control.signOut();
      return const AuthAdminMutationResult<AuthAdminStopImpersonatingResult>(
        data: AuthAdminStopImpersonatingResult(signedOut: true),
      ).toJson((value) => value.toJson());
    }
    final session = await control.replaceIdentity(
      actor.user,
      authenticationMethod: 'impersonation-return',
    );
    final warnings = await _afterAndEmit(
      options.hooks.afterImpersonation,
      invocation.context,
      'impersonation.stopped',
      actor.user,
      currentUser.id,
      currentUser.redacted(),
    );
    return AuthAdminMutationResult(
      data: AuthAdminStopImpersonatingResult(
        signedOut: false,
        session: session,
      ),
      warnings: warnings,
    ).toJson((value) => value.toJson());
  }

  Future<AuthAdminMutationResult<bool>> _removeUser(
    TContext context,
    AuthUser actor,
    Map<String, dynamic> input,
  ) async {
    final userId = _string(input, 'userId');
    if (actor.id == userId) throw AuthFlowException('self_delete');
    await _before(
      options.hooks.beforeDelete,
      context,
      'delete',
      actor,
      userId,
      userId,
    );
    await options.validateDeletion?.call(userId);
    final deleted = await store.deleteUser(
      userId,
      administratorRoles: _adminRoles,
      administratorUserIds: _adminUserIds,
    );
    return _completeMutation(
      context,
      actor,
      'user.deleted',
      userId,
      deleted,
      options.hooks.afterDelete,
    );
  }

  Future<AuthUser> _authoritativeUser(String userId) async {
    final value = await _coreStore.users.findById(userId.trim());
    if (value == null) throw AuthFlowException('unauthorized');
    final state = await store.findUser(value.id);
    if (state?.state.isBanned() == true) {
      throw AuthFlowException('account_unavailable');
    }
    return value;
  }

  Future<void> _require(String actorId, String resource, String action) async {
    final actor = await _authoritativeUser(actorId);
    if (!isAdministrator(actor) ||
        !accessControl.allows(_effectiveRoles(actor), resource, action)) {
      throw AuthFlowException('admin_forbidden');
    }
  }

  Iterable<String> _effectiveRoles(AuthUser user) =>
      _adminUserIds.contains(user.id) ? {...user.roles, 'admin'} : user.roles;

  Future<AuthAdminUser> _requiredUser(String userId) async {
    final value = await store.findUser(userId);
    if (value == null) throw AuthFlowException('user_not_found');
    return value;
  }

  Future<AuthAdminMutationResult<T>> _completeMutation<T>(
    TContext context,
    AuthUser actor,
    String event,
    String targetUserId,
    T value,
    AuthAdminAfterHook<TContext, Object>? hook,
  ) async => AuthAdminMutationResult(
    data: value,
    warnings: await _afterAndEmit(
      hook,
      context,
      event,
      actor,
      targetUserId,
      value as Object,
    ),
  );

  Future<List<AuthAdminWarning>> _afterAndEmit(
    AuthAdminAfterHook<TContext, Object>? hook,
    TContext context,
    String event,
    AuthUser actor,
    String targetUserId,
    Object value,
  ) async {
    final warnings = <AuthAdminWarning>[];
    if (hook != null) {
      try {
        await hook(
          AuthAdminHookContext(
            context: context,
            action: event,
            actor: actor.redacted(),
            data: value,
            targetUserId: targetUserId,
          ),
        );
      } catch (error, stackTrace) {
        warnings.add(const AuthAdminWarning(code: 'after_hook_failed'));
        await _report(event, error, stackTrace, targetUserId);
      }
    }
    final sink = options.emitEvent;
    if (sink != null) {
      try {
        await sink(
          AuthAdminLifecycleEvent(
            type: event,
            actorId: actor.id,
            targetUserId: targetUserId,
            occurredAt: DateTime.now().toUtc(),
          ),
        );
      } catch (error, stackTrace) {
        warnings.add(const AuthAdminWarning(code: 'event_delivery_failed'));
        await _report(event, error, stackTrace, targetUserId);
      }
    }
    return warnings;
  }

  Future<Object> _before(
    AuthAdminBeforeHook<TContext, Object>? hook,
    TContext context,
    String action,
    AuthUser actor,
    Object value,
    String targetUserId,
  ) async {
    if (hook == null) return value;
    return hook(
      AuthAdminHookContext(
        context: context,
        action: action,
        actor: actor.redacted(),
        data: value,
        targetUserId: targetUserId,
      ),
    );
  }

  Future<void> _report(
    String operation,
    Object error,
    StackTrace stackTrace,
    String userId,
  ) async {
    try {
      await options.reportFailure?.call(
        AuthAdminInternalFailure(
          operation: operation,
          error: error,
          stackTrace: stackTrace,
          targetUserId: userId,
        ),
      );
    } catch (_) {
      // A reporter must not change committed mutation semantics.
    }
  }
}

const AuthOperationCodec<Map<String, dynamic>> _mapCodec = AuthOperationCodec(
  decode: _identityMap,
  encode: _identityMap,
);
const AuthOperationCodec<Object?> _objectCodec = AuthOperationCodec(
  decode: _identityObject,
  encode: _identityObject,
);

Map<String, dynamic> _identityMap(Map<String, dynamic> value) => value;
Object? _identityObject(Object? value) => value;

Map<String, List<String>> _normalizePermissions(
  AuthAdminPermissionSet permissions,
) => Map<String, List<String>>.unmodifiable({
  for (final entry in permissions.entries)
    entry.key.trim().toLowerCase(): normalizeAuthAdminRoles(entry.value),
});

String _string(Map<String, dynamic> input, String key) {
  final value = input[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw AuthFlowException('invalid_request');
  return value;
}

String _requiredEmail(Map<String, dynamic> input, String key) {
  final value = normalizeAuthEmail(_string(input, key));
  if (!value.contains('@')) throw AuthFlowException('invalid_email');
  return value;
}

String? _optionalString(Map<String, dynamic> input, String key) {
  final value = input[key]?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

int _integer(Map<String, dynamic> input, String key, int fallback) {
  final value = input[key];
  return value is int ? value : int.tryParse('$value') ?? fallback;
}

bool? _optionalBool(Map<String, dynamic> input, String key) {
  if (!input.containsKey(key)) return null;
  final value = input[key];
  if (value is bool) return value;
  if ('$value'.toLowerCase() == 'true') return true;
  if ('$value'.toLowerCase() == 'false') return false;
  throw AuthFlowException('invalid_request');
}

DateTime? _optionalDate(Object? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse('$value');
  if (parsed == null) throw AuthFlowException('invalid_request');
  return parsed.toUtc();
}

List<String> _roles(Map<String, dynamic> input, {Iterable<String>? fallback}) {
  final value = input['roles'];
  if (value == null && fallback != null) {
    return normalizeAuthAdminRoles(fallback);
  }
  if (value is! List) throw AuthFlowException('invalid_role');
  final roles = normalizeAuthAdminRoles(value.map((item) => '$item'));
  if (roles.isEmpty) throw AuthFlowException('invalid_role');
  return roles;
}

Map<String, dynamic> _jsonMap(Object? value) => value is Map
    ? sanitizeAuthAdminAttributes(Map<String, dynamic>.from(value))
    : const <String, dynamic>{};
