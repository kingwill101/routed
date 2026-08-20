import 'dart:async';

import 'account_policy.dart';
import 'deletion_transaction.dart';
import 'exceptions.dart';
import 'plugin.dart';
import 'models.dart';
import 'rate_limit.dart';
import 'store.dart';
import 'tokens.dart' show secureRandomToken;
import 'users.dart' show authUserIsDisabled;
import 'device_authorization_store.dart';

const String authDeviceAuthorizationPluginId = 'device_authorization';

typedef AuthDeviceAuthorizationClientValidator<TContext> =
    FutureOr<bool> Function(
      TContext context,
      String clientId,
      List<String> scopes,
    );

typedef AuthDeviceAuthorizationTokenIssuer<TContext> =
    FutureOr<AuthDeviceAccessToken> Function({
      required TContext context,
      required AuthUser user,
      required String clientId,
      required List<String> scopes,
      required String authorizationId,
    });

/// A token response produced by the application's access-token issuer.
final class AuthDeviceAccessToken {
  const AuthDeviceAccessToken({
    required this.accessToken,
    required this.expiresIn,
    this.tokenType = 'Bearer',
    this.refreshToken,
    this.scopes = const <String>[],
  });

  final String accessToken;
  final Duration expiresIn;
  final String tokenType;
  final String? refreshToken;
  final List<String> scopes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'access_token': accessToken,
    'token_type': tokenType,
    'expires_in': expiresIn.inSeconds,
    if (refreshToken != null) 'refresh_token': refreshToken,
    if (scopes.isNotEmpty) 'scope': scopes.join(' '),
  };
}

/// Raw values returned once when a device starts authorization.
final class AuthDeviceAuthorizationRequest {
  const AuthDeviceAuthorizationRequest({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final Duration expiresIn;
  final Duration interval;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'device_code': deviceCode,
    'user_code': userCode,
    'verification_uri': verificationUri,
    'expires_in': expiresIn.inSeconds,
    'interval': interval.inSeconds,
  };
}

/// RFC 8628 device authorization flow.
///
/// The plugin owns the one-time approval transaction and delegates actual
/// access-token creation to [issueToken]. Applications should persist and
/// validate those tokens in their own API-token boundary; this plugin never
/// stores raw access or refresh tokens.
final class DeviceAuthorizationPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthUserDeletionPlanContributor,
        AuthUserAccessRevocationContributor,
        AuthServerPluginTopologyAware<TContext> {
  DeviceAuthorizationPlugin({
    required this.verificationUri,
    required this.validateClient,
    required this.issueToken,
    this.deviceCodeTtl = const Duration(minutes: 10),
    this.pollInterval = const Duration(seconds: 5),
  }) : assert(deviceCodeTtl > Duration.zero),
       assert(pollInterval > Duration.zero),
       _authStore = null;

  final String verificationUri;
  final AuthDeviceAuthorizationClientValidator<TContext> validateClient;
  final AuthDeviceAuthorizationTokenIssuer<TContext> issueToken;
  final Duration deviceCodeTtl;
  final Duration pollInterval;

  late AuthDeviceAuthorizationStore _store;
  late AuthUserDeletionDomain _deletionDomain;
  AuthStore? _authStore;
  bool _contributesTokenEndpoint = true;
  bool _configured = false;

  @override
  String get id => authDeviceAuthorizationPluginId;

  @override
  String get userDataNamespace => 'device_authorization';

  @override
  String get userAccessNamespace => 'device_authorization';

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    _store = context.store.deviceAuthorizations;
    _authStore = context.store;
    final host = context.store;
    if (host is! AuthUserDeletionCoordinatorHost) {
      throw StateError(
        'DeviceAuthorizationPlugin requires a deletion-coordinator host store.',
      );
    }
    _deletionDomain = (host as AuthUserDeletionCoordinatorHost)
        .userDeletionCoordinator
        .domain;
    _configured = true;
  }

  @override
  Future<AuthUserDeletionPlan> createUserDeletionPlan(AuthUser user) {
    _ensureConfigured();
    final deletionStore = _store;
    if (deletionStore is AuthUserDeletionPlanFactory) {
      return Future.sync(
        () => (deletionStore as AuthUserDeletionPlanFactory).createDeletionPlan(
          domain: _deletionDomain,
          user: user,
          namespace: userDataNamespace,
        ),
      );
    }
    if (_deletionDomain is! AuthInMemoryUserDeletionDomain ||
        deletionStore is! AuthInMemoryUserDeletionStore) {
      throw StateError(
        'The device-authorization adapter has no plan for this domain.',
      );
    }
    return Future.value(
      AuthInMemoryUserDeletionPlan(
        domain: _deletionDomain as AuthInMemoryUserDeletionDomain,
        userId: user.id,
        namespace: userDataNamespace,
        operation: AuthInMemoryStoreDeletionOperation(
          store: deletionStore as AuthInMemoryUserDeletionStore,
          userId: user.id,
        ),
      ),
    );
  }

  @override
  Future<void> revokeUserAccess(String userId) async {
    await _store.deleteForUser(userId);
  }

  @override
  void composePluginTopology(Iterable<AuthServerPlugin<TContext>> plugins) {
    final hosts = plugins
        .where((plugin) => !identical(plugin, this))
        .whereType<AuthOAuthTokenEndpointHost<TContext>>()
        .toList(growable: false);
    if (hosts.length > 1) {
      throw StateError(
        'Device authorization found multiple OAuth token hosts.',
      );
    }
    if (hosts.isEmpty) return;
    hosts.single.registerOAuthTokenGrant(
      'urn:ietf:params:oauth:grant-type:device_code',
      (invocation, request) => _deviceTokenGrant(invocation, request),
    );
    _contributesTokenEndpoint = false;
  }

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints => [
    _endpoint(
      id: 'deviceAuthorization.request',
      method: AuthOperationMethod.post,
      path: '/oauth/device/authorize',
      authentication: AuthOperationAuthentication.none,
      originPolicy: AuthOperationOriginPolicy.none,
      csrfPolicy: AuthOperationCsrfPolicy.none,
      operationName: 'request',
    ),
    _endpoint(
      id: 'deviceAuthorization.approve',
      method: AuthOperationMethod.post,
      path: '/oauth/device/approve',
      authentication: AuthOperationAuthentication.session,
      operationName: 'approve',
    ),
    _endpoint(
      id: 'deviceAuthorization.deny',
      method: AuthOperationMethod.post,
      path: '/oauth/device/deny',
      authentication: AuthOperationAuthentication.session,
      operationName: 'deny',
    ),
    if (_contributesTokenEndpoint)
      _endpoint(
        id: 'deviceAuthorization.token',
        method: AuthOperationMethod.post,
        path: '/oauth/token',
        authentication: AuthOperationAuthentication.none,
        originPolicy: AuthOperationOriginPolicy.none,
        csrfPolicy: AuthOperationCsrfPolicy.none,
        operationName: 'token',
      ),
  ];

  AuthEndpointDescriptor<TContext> _endpoint({
    required String id,
    required AuthOperationMethod method,
    required String path,
    required AuthOperationAuthentication authentication,
    required String operationName,
    AuthOperationOriginPolicy originPolicy = AuthOperationOriginPolicy.browser,
    AuthOperationCsrfPolicy csrfPolicy = AuthOperationCsrfPolicy.required,
  }) => TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
    id: id,
    method: method,
    path: path,
    semantics: AuthOperationSemantics.mutation(
      persistence: const AuthMutationPersistence.durable(
        atomicity: AuthMutationAtomicity.nonAtomic,
        reference: AuthPersistenceOperationReference(
          schemaId: authDeviceAuthorizationPluginId,
        ),
      ),
      replaySafety: id == 'deviceAuthorization.request'
          ? AuthMutationReplaySafety.repeatable
          : AuthMutationReplaySafety.singleUse,
    ),
    requestCodec: _mapCodec,
    responseCodec: _objectCodec,
    authentication: authentication,
    originPolicy: originPolicy,
    csrfPolicy: csrfPolicy,
    rateLimitOperation: AuthRateLimitOperation(
      'device_authorization',
      operationName,
    ),
    handler: (invocation, request) => _invokeEndpoint(id, invocation, request),
  );

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
      id: authDeviceAuthorizationPluginId,
      entities: <AuthEntityDescriptor>[
        AuthEntityDescriptor(
          id: 'auth_device_authorization',
          fields: <AuthFieldDescriptor>[
            AuthFieldDescriptor(name: 'id', kind: 'id'),
            AuthFieldDescriptor(name: 'deviceCodeHash', kind: 'secret_digest'),
            AuthFieldDescriptor(name: 'userCodeHash', kind: 'secret_digest'),
            AuthFieldDescriptor(name: 'clientId', kind: 'string'),
            AuthFieldDescriptor(name: 'scopes', kind: 'string_list'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'expiresAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'interval', kind: 'duration'),
            AuthFieldDescriptor(name: 'status', kind: 'enum'),
            AuthFieldDescriptor(name: 'userId', kind: 'nullable_id'),
            AuthFieldDescriptor(name: 'approvedAt', kind: 'nullable_datetime'),
            AuthFieldDescriptor(name: 'deniedAt', kind: 'nullable_datetime'),
            AuthFieldDescriptor(
              name: 'lastPolledAt',
              kind: 'nullable_datetime',
            ),
          ],
          relationships: <AuthRelationshipDescriptor>[
            AuthRelationshipDescriptor(field: 'userId', targetEntity: 'user'),
          ],
          uniqueConstraints: <List<String>>[
            <String>['deviceCodeHash'],
            <String>['userCodeHash'],
          ],
          indexes: <List<String>>[
            <String>['expiresAt'],
            <String>['userId'],
          ],
        ),
      ],
      atomicOperations: <AuthAtomicOperationDescriptor>[
        AuthAtomicOperationDescriptor(
          id: 'deviceAuthorization.poll',
          description:
              'Atomically enforce polling intervals and expose approval state.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'deviceAuthorization.claim',
          description:
              'Claim an approved device request exactly once for token issuance.',
        ),
      ],
    ),
  ];

  Future<AuthDeviceAuthorizationRequest> authorizeDevice({
    required TContext context,
    required String clientId,
    Iterable<String> scopes = const <String>[],
    DateTime? now,
  }) async {
    _ensureConfigured();
    final normalizedClientId = _requiredClientId(clientId);
    final normalizedScopes = _normalizeScopes(scopes);
    if (!await validateClient(context, normalizedClientId, normalizedScopes)) {
      throw AuthFlowException('invalid_client');
    }
    final createdAt = (now ?? DateTime.now()).toUtc();
    final deviceCode = secureRandomToken(length: 32);
    final rawUserCode = _generateUserCode();
    await _store.create(
      AuthDeviceAuthorization(
        id: secureRandomToken(length: 16),
        deviceCodeHash: hashAuthDeviceAuthorizationCode(deviceCode),
        userCodeHash: hashAuthDeviceAuthorizationCode(rawUserCode),
        clientId: normalizedClientId,
        scopes: normalizedScopes,
        createdAt: createdAt,
        expiresAt: createdAt.add(deviceCodeTtl),
        interval: pollInterval,
      ),
    );
    return AuthDeviceAuthorizationRequest(
      deviceCode: deviceCode,
      userCode: _formatUserCode(rawUserCode),
      verificationUri: verificationUri,
      expiresIn: deviceCodeTtl,
      interval: pollInterval,
    );
  }

  Future<void> approveDevice({
    required String userId,
    required String userCode,
    DateTime? now,
  }) async {
    _ensureConfigured();
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) throw AuthFlowException('unauthorized');
    final normalizedCode = _normalizeUserCode(userCode);
    final approved = await _store.approve(
      hashAuthDeviceAuthorizationCode(normalizedCode),
      normalizedUserId,
      now: now,
    );
    if (approved == null) {
      throw AuthFlowException('invalid_user_code');
    }
  }

  Future<void> denyDevice({required String userCode, DateTime? now}) async {
    _ensureConfigured();
    final normalizedCode = _normalizeUserCode(userCode);
    final denied = await _store.deny(
      hashAuthDeviceAuthorizationCode(normalizedCode),
      now: now,
    );
    if (denied == null) throw AuthFlowException('invalid_user_code');
  }

  Future<AuthDeviceAccessToken> pollDeviceToken({
    required TContext context,
    required String clientId,
    required String deviceCode,
    DateTime? now,
  }) async {
    _ensureConfigured();
    final normalizedClientId = _requiredClientId(clientId);
    if (deviceCode.trim().isEmpty) throw AuthFlowException('invalid_grant');
    final hash = hashAuthDeviceAuthorizationCode(deviceCode);
    final result = await _store.poll(hash, now: now);
    switch (result.status) {
      case AuthDeviceAuthorizationPollStatus.pending:
        throw AuthFlowException('authorization_pending');
      case AuthDeviceAuthorizationPollStatus.slowDown:
        throw AuthFlowException('slow_down');
      case AuthDeviceAuthorizationPollStatus.denied:
        throw AuthFlowException('access_denied');
      case AuthDeviceAuthorizationPollStatus.expired:
        throw AuthFlowException('expired_token');
      case AuthDeviceAuthorizationPollStatus.consumed:
      case AuthDeviceAuthorizationPollStatus.invalid:
        throw AuthFlowException('invalid_grant');
      case AuthDeviceAuthorizationPollStatus.approved:
        break;
    }
    final approvedUserId = result.authorization?.userId;
    if (approvedUserId == null ||
        await _findCredentialEligibleUser(approvedUserId) == null) {
      throw AuthFlowException('invalid_grant');
    }
    final claimed = await _store.claimApproved(
      hash,
      clientId: normalizedClientId,
      now: now,
    );
    final userId = claimed?.userId;
    if (claimed == null || userId == null) {
      throw AuthFlowException('invalid_grant');
    }
    final user = await _findCredentialEligibleUser(userId);
    if (user == null) {
      throw AuthFlowException('invalid_grant');
    }
    return issueToken(
      context: context,
      user: user,
      clientId: normalizedClientId,
      scopes: List<String>.unmodifiable(claimed.scopes),
      authorizationId: claimed.id,
    );
  }

  Future<AuthUser?> _findCredentialEligibleUser(String userId) async {
    final store = _authStore!;
    final user = await store.users.findById(userId);
    if (user == null || authUserIsDisabled(user)) return null;
    final states = store is AuthAccountStateStore
        ? store as AuthAccountStateStore
        : null;
    final state = await states?.find(userId);
    if (state?.disabled == true || state?.isLocked() == true) return null;
    return user;
  }

  Future<Object?> _deviceTokenGrant(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) => pollDeviceToken(
    context: invocation.context,
    clientId: _string(input, 'client_id'),
    deviceCode: _string(input, 'device_code'),
  ).then((token) => token.toJson());

  Future<Object?> _invokeEndpoint(
    String id,
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    switch (id) {
      case 'deviceAuthorization.request':
        return (await authorizeDevice(
          context: invocation.context,
          clientId: _string(input, 'client_id'),
          scopes: _scopes(input['scope']),
        )).toJson();
      case 'deviceAuthorization.approve':
        final user = invocation.user;
        if (user == null) throw AuthFlowException('unauthorized');
        await approveDevice(
          userId: user.id,
          userCode: _string(input, 'user_code'),
        );
        return const <String, dynamic>{'status': 'approved'};
      case 'deviceAuthorization.deny':
        final user = invocation.user;
        if (user == null) throw AuthFlowException('unauthorized');
        await denyDevice(userCode: _string(input, 'user_code'));
        return const <String, dynamic>{'status': 'denied'};
      case 'deviceAuthorization.token':
        return (await pollDeviceToken(
          context: invocation.context,
          clientId: _string(input, 'client_id'),
          deviceCode: _string(input, 'device_code'),
        )).toJson();
      default:
        throw StateError('Unknown device authorization endpoint $id');
    }
  }

  void _ensureConfigured() {
    if (!_configured) {
      throw StateError(
        'DeviceAuthorizationPlugin must be registered with AuthRuntime',
      );
    }
  }

  static final AuthOperationCodec<Map<String, dynamic>> _mapCodec =
      AuthOperationCodec<Map<String, dynamic>>(
        decode: (value) => Map<String, dynamic>.from(value),
        encode: (value) => value,
      );

  static final AuthOperationCodec<Object?> _objectCodec =
      AuthOperationCodec<Object?>(
        decode: (value) => value,
        encode: (value) => value,
      );

  static String _requiredClientId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 256) {
      throw AuthFlowException('invalid_client');
    }
    return normalized;
  }

  static List<String> _normalizeScopes(Iterable<String> values) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final scope = value.trim();
      if (scope.isEmpty || scope.contains(RegExp(r'\s'))) {
        throw AuthFlowException('invalid_scope');
      }
      if (seen.add(scope)) normalized.add(scope);
    }
    return List<String>.unmodifiable(normalized);
  }

  static Iterable<String> _scopes(Object? value) {
    if (value == null) return const <String>[];
    if (value is String) return value.split(RegExp(r'\s+'));
    if (value is List && value.every((item) => item is String)) {
      return value.cast<String>();
    }
    throw AuthFlowException('invalid_scope');
  }

  static String _string(Map<String, dynamic> input, String key) {
    final value = input[key];
    if (value is! String || value.trim().isEmpty) {
      throw AuthFlowException('invalid_request');
    }
    return value.trim();
  }

  static String _generateUserCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = secureRandomToken(length: 16);
    return String.fromCharCodes(
      List<int>.generate(
        8,
        (index) =>
            alphabet.codeUnitAt(random.codeUnitAt(index) % alphabet.length),
      ),
    );
  }

  static String _formatUserCode(String value) =>
      '${value.substring(0, 4)}-${value.substring(4)}';

  static String _normalizeUserCode(String value) {
    final normalized = value.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (normalized.length != 8 ||
        !RegExp(r'^[A-Z2-9]+$').hasMatch(normalized)) {
      throw AuthFlowException('invalid_user_code');
    }
    return normalized;
  }
}
