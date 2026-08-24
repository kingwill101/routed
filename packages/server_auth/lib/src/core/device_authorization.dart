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

/// Registry identifier for the RFC 8628 device-authorization plugin.
const String authDeviceAuthorizationPluginId = 'device_authorization';

/// Validates a device-flow client and its requested scopes.
///
/// Receives application [context], a normalized [clientId], and normalized,
/// de-duplicated [scopes]. Returning false rejects the request with
/// `invalid_client`; the callback may complete synchronously or asynchronously.
typedef AuthDeviceAuthorizationClientValidator<TContext> =
    FutureOr<bool> Function(
      TContext context,
      String clientId,
      List<String> scopes,
    );

/// Immutable input to an application-owned idempotent token issuer.
///
/// Implementations must use [authorizationId] as their idempotency key and
/// bind the cached logical grant to [clientId], [user], and [scopes]. A retry
/// after an ambiguous failure must return that same logical grant rather than
/// minting another one.
final class AuthDeviceAuthorizationTokenIssuanceRequest<TContext> {
  /// Creates an immutable token-issuance request.
  ///
  /// [authorizationId] is the durable idempotency key. [scopes] is copied into
  /// an unmodifiable list; [user] must still be eligible for credentials when
  /// the issuer handles the request.
  AuthDeviceAuthorizationTokenIssuanceRequest({
    required this.context,
    required this.user,
    required this.clientId,
    required Iterable<String> scopes,
    required this.authorizationId,
  }) : scopes = List<String>.unmodifiable(scopes);

  /// Application context associated with the device-flow request.
  final TContext context;

  /// Credential-eligible user authorized by the device flow.
  final AuthUser user;

  /// Normalized OAuth client identifier.
  final String clientId;

  /// Normalized, de-duplicated scopes granted to the client.
  final List<String> scopes;

  /// Durable identifier used to make token issuance idempotent.
  final String authorizationId;
}

/// Application-owned, authorization-ID-idempotent device token issuer.
///
/// Routed deliberately does not persist the returned token material. The
/// implementation owns durable idempotency records and token lookup.
abstract interface class AuthDeviceAuthorizationTokenIssuer<TContext> {
  /// Issues or retrieves the same logical token grant for [request].
  ///
  /// The application owns token persistence and lookup. It must key retries by
  /// [AuthDeviceAuthorizationTokenIssuanceRequest.authorizationId]; Routed
  /// does not persist the returned raw access or refresh token values.
  FutureOr<AuthDeviceAccessToken> issue(
    AuthDeviceAuthorizationTokenIssuanceRequest<TContext> request,
  );
}

/// A token response produced by the application's access-token issuer.
final class AuthDeviceAccessToken {
  /// Creates an access-token response for the device grant.
  ///
  /// [expiresIn] is serialized as whole seconds. [tokenType] defaults to
  /// `Bearer`, and an optional [refreshToken] is omitted from JSON when null.
  const AuthDeviceAccessToken({
    required this.accessToken,
    required this.expiresIn,
    this.tokenType = 'Bearer',
    this.refreshToken,
    this.scopes = const <String>[],
  });

  /// Raw access token returned to the token client.
  final String accessToken;

  /// Lifetime of [accessToken].
  final Duration expiresIn;

  /// OAuth token type, `Bearer` by default.
  final String tokenType;

  /// Optional raw refresh token returned to the token client.
  final String? refreshToken;

  /// Scopes granted with the access token.
  final List<String> scopes;

  /// Serializes the response using OAuth token endpoint field names.
  ///
  /// Non-empty [scopes] become one space-separated `scope` value.
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
  /// Creates the one-time response that starts a device authorization flow.
  ///
  /// Raw [deviceCode] and formatted [userCode] are delivery credentials and
  /// should be returned only to the device client or verification UI.
  const AuthDeviceAuthorizationRequest({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  /// Raw device code presented when polling for a token.
  final String deviceCode;

  /// Human-entered code used by the verification UI.
  final String userCode;

  /// URI where the user enters [userCode].
  final String verificationUri;

  /// Time until the device code expires.
  final Duration expiresIn;

  /// Minimum polling interval recommended to the device client.
  final Duration interval;

  /// Serializes this response with RFC 8628 field names and second values.
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
/// The plugin owns the bounded issuance lease and delegates actual token
/// creation to [tokenIssuer]. Applications persist and validate those tokens
/// in their own API-token boundary; this plugin never stores raw access or
/// refresh tokens.
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
  /// Creates a device-authorization plugin.
  ///
  /// All duration settings must be positive. [clock] is injectable for
  /// deterministic tests; [validateClient] controls client and scope access,
  /// while [tokenIssuer] owns durable, idempotent token issuance.
  DeviceAuthorizationPlugin({
    required this.verificationUri,
    required this.validateClient,
    required this.tokenIssuer,
    this.deviceCodeTtl = const Duration(minutes: 10),
    this.pollInterval = const Duration(seconds: 5),
    this.issuanceLeaseTtl = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : assert(deviceCodeTtl > Duration.zero),
       assert(pollInterval > Duration.zero),
       assert(issuanceLeaseTtl > Duration.zero),
       _clock = clock ?? DateTime.now,
       _authStore = null;

  /// Verification URI shown to the user with each authorization request.
  final String verificationUri;

  /// Application callback that validates clients and requested scopes.
  final AuthDeviceAuthorizationClientValidator<TContext> validateClient;

  /// Application-owned idempotent token issuer.
  final AuthDeviceAuthorizationTokenIssuer<TContext> tokenIssuer;

  /// Lifetime of an issued device authorization request.
  final Duration deviceCodeTtl;

  /// Initial minimum interval between device polling attempts.
  final Duration pollInterval;

  /// Maximum lifetime of one token-issuance lease.
  final Duration issuanceLeaseTtl;
  final DateTime Function() _clock;

  late AuthDeviceAuthorizationStore _store;
  late AuthUserDeletionDomain _deletionDomain;
  AuthStore? _authStore;
  bool _contributesTokenEndpoint = true;
  bool _configured = false;

  /// Stable plugin identifier used by runtime configuration.
  @override
  String get id => authDeviceAuthorizationPluginId;

  /// Declares the user data namespace persisted by this plugin.
  @override
  AuthServerPluginDataContract get dataContract =>
      const AuthServerPluginDataContract(
        userDataNamespace: 'device_authorization',
      );

  /// Namespace used when planning deletion of a user's device records.
  @override
  String get userDataNamespace => 'device_authorization';

  /// Namespace used when revoking a user's device-flow access.
  @override
  String get userAccessNamespace => 'device_authorization';

  /// Binds the plugin to the configured store and deletion coordinator.
  ///
  /// Throws [StateError] when the store cannot host coordinated user deletion.
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

  /// Creates a deletion plan for all device authorizations owned by [user].
  ///
  /// Uses an adapter-provided plan when available, otherwise supports the
  /// in-memory deletion domain and store. Throws [StateError] when neither
  /// deletion integration is available.
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

  /// Removes pending and completed device authorizations for [userId].
  @override
  Future<void> revokeUserAccess(String userId) async {
    await _store.deleteForUser(userId);
  }

  /// Registers the device grant with one OAuth token endpoint host.
  ///
  /// When a host is present, this plugin omits its standalone `/oauth/token`
  /// endpoint. Multiple token hosts are rejected with [StateError].
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

  /// Describes device authorization, approval, denial, and token endpoints.
  ///
  /// The request endpoint is unauthenticated and repeatable; approval and
  /// denial require a session and are single-use. The token endpoint is
  /// omitted when another OAuth token host accepts the device grant.
  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints => [
    _endpoint(
      id: 'deviceAuthorization.request',
      method: AuthOperationMethod.post,
      path: const AuthRoutePath('/oauth/device/authorize'),
      authentication: AuthOperationAuthentication.none,
      originPolicy: AuthOperationOriginPolicy.none,
      csrfPolicy: AuthOperationCsrfPolicy.none,
      operationName: 'request',
    ),
    _endpoint(
      id: 'deviceAuthorization.approve',
      method: AuthOperationMethod.post,
      path: const AuthRoutePath('/oauth/device/approve'),
      authentication: AuthOperationAuthentication.session,
      operationName: 'approve',
    ),
    _endpoint(
      id: 'deviceAuthorization.deny',
      method: AuthOperationMethod.post,
      path: const AuthRoutePath('/oauth/device/deny'),
      authentication: AuthOperationAuthentication.session,
      operationName: 'deny',
    ),
    if (_contributesTokenEndpoint)
      _endpoint(
        id: 'deviceAuthorization.token',
        method: AuthOperationMethod.post,
        path: const AuthRoutePath('/oauth/token'),
        authentication: AuthOperationAuthentication.none,
        originPolicy: AuthOperationOriginPolicy.none,
        csrfPolicy: AuthOperationCsrfPolicy.none,
        operationName: 'token',
      ),
  ];

  AuthEndpointDescriptor<TContext> _endpoint({
    required String id,
    required AuthOperationMethod method,
    required AuthRoutePath path,
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

  /// Exposes client-operation descriptors for the configured endpoints.
  @override
  Iterable<AuthClientOperationDescriptor> get clientOperations => endpoints.map(
    (endpoint) => AuthClientOperationDescriptor(
      id: endpoint.id,
      method: endpoint.method,
      path: endpoint.path,
      mount: endpoint.mount,
      serverOnly: endpoint.serverOnly,
    ),
  );

  /// Exposes rate-limit operations for the configured endpoints.
  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations => endpoints
      .map((endpoint) => endpoint.rateLimitOperation)
      .whereType<AuthRateLimitOperation>();

  /// Describes hash-only device records and their atomic store operations.
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
            AuthFieldDescriptor(
              name: 'issuanceLeaseDigest',
              kind: 'nullable_secret_digest',
            ),
            AuthFieldDescriptor(
              name: 'issuanceLeaseExpiresAt',
              kind: 'nullable_datetime',
            ),
            AuthFieldDescriptor(name: 'consumedAt', kind: 'nullable_datetime'),
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
          id: 'deviceAuthorization.beginIssuance',
          description:
              'Atomically acquire one bounded issuance lease for an approved request.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'deviceAuthorization.completeIssuance',
          description:
              'Consume an approved request only for its matching active lease.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'deviceAuthorization.releaseIssuance',
          description:
              'Release only the matching lease after an issuance failure.',
        ),
      ],
    ),
  ];

  /// Starts a device authorization request for [clientId].
  ///
  /// The client and normalized scopes are checked by [validateClient]. On
  /// success, raw device and user codes are returned once while only digests
  /// are stored. Throws `invalid_client` for rejected clients or
  /// `invalid_scope` when scope normalization fails.
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
    final createdAt = (now ?? _clock()).toUtc();
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

  /// Approves a pending device request for [userId].
  ///
  /// User-code formatting is normalized by trimming spaces, hyphens, and
  /// case. Empty user IDs throw `unauthorized`; missing, expired, or already
  /// transitioned requests throw `invalid_user_code`.
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

  /// Denies a pending device request identified by [userCode].
  ///
  /// Missing, expired, or already transitioned requests throw
  /// `invalid_user_code`; successful denial is terminal.
  Future<void> denyDevice({required String userCode, DateTime? now}) async {
    _ensureConfigured();
    final normalizedCode = _normalizeUserCode(userCode);
    final denied = await _store.deny(
      hashAuthDeviceAuthorizationCode(normalizedCode),
      now: now,
    );
    if (denied == null) throw AuthFlowException('invalid_user_code');
  }

  /// Polls for and issues the token for an approved device request.
  ///
  /// Maps store states to RFC 8628 errors such as `authorization_pending`,
  /// `slow_down`, `access_denied`, `expired_token`, and `invalid_grant`.
  /// Approved requests are bound to [clientId], leased for bounded idempotent
  /// issuance, rechecked for account eligibility, and consumed only after the
  /// issuer succeeds. Failed issuance releases the lease when possible;
  /// expired leases remain recoverable.
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
    final pollNow = (now ?? _clock()).toUtc();
    final result = await _store.poll(hash, now: pollNow);
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
    final leaseRaw = secureRandomToken(length: 32);
    final leaseDigest = hashAuthDeviceAuthorizationIssuanceLease(leaseRaw);
    final leaseNow = (now ?? _clock()).toUtc();
    final leaseResult = await _store.beginIssuance(
      hash,
      clientId: normalizedClientId,
      leaseDigest: leaseDigest,
      leaseExpiresAt: leaseNow.add(issuanceLeaseTtl),
      now: leaseNow,
    );
    if (leaseResult.status == AuthDeviceAuthorizationIssuanceLeaseStatus.busy) {
      throw AuthFlowException('authorization_pending');
    }
    final lease = leaseResult.lease;
    final authorization = lease?.authorization;
    final userId = authorization?.userId;
    if (leaseResult.status !=
            AuthDeviceAuthorizationIssuanceLeaseStatus.acquired ||
        lease == null ||
        authorization == null ||
        userId == null) {
      throw AuthFlowException('invalid_grant');
    }
    final user = await _findCredentialEligibleUser(userId);
    if (user == null) {
      await _releaseIssuanceLease(hash, normalizedClientId, leaseDigest, now);
      throw AuthFlowException('invalid_grant');
    }
    try {
      final token = await tokenIssuer.issue(
        AuthDeviceAuthorizationTokenIssuanceRequest<TContext>(
          context: context,
          user: user,
          clientId: normalizedClientId,
          scopes: authorization.scopes,
          authorizationId: authorization.id,
        ),
      );
      if (await _findCredentialEligibleUser(userId) == null) {
        throw AuthFlowException('invalid_grant');
      }
      final completed = await _store.completeIssuance(
        hash,
        clientId: normalizedClientId,
        leaseDigest: leaseDigest,
        now: (now ?? _clock()).toUtc(),
      );
      if (!completed) throw AuthFlowException('invalid_grant');
      return token;
    } catch (error, stackTrace) {
      await _releaseIssuanceLease(hash, normalizedClientId, leaseDigest, now);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _releaseIssuanceLease(
    String deviceCodeHash,
    String clientId,
    String leaseDigest,
    DateTime? now,
  ) async {
    try {
      await _store.releaseIssuance(
        deviceCodeHash,
        clientId: clientId,
        leaseDigest: leaseDigest,
        now: (now ?? _clock()).toUtc(),
      );
    } catch (_) {
      // Preserve the issuance failure. The bounded lease remains recoverable
      // after expiry even when the backing store is temporarily unavailable.
    }
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
