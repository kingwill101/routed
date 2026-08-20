import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:jose/jose.dart' show JsonWebSignatureBuilder;

import 'exceptions.dart';
import 'account_policy.dart';
import 'deletion_transaction.dart';
import 'models.dart';
import 'plugin.dart';
import 'oauth_client_store.dart';
import 'oauth_provider_models.dart';
import 'rate_limit.dart';
import 'store.dart';
import 'tokens.dart' show hashOpaqueToken, secureRandomToken;
import 'users.dart' show authUserIsDisabled;

const String authOAuthProviderModePluginId = 'oauth_provider_mode';

/// Plugin that enables the application to act as an OAuth/OIDC provider.
///
/// This plugin allows Routed applications to:
/// - Register OAuth clients
/// - Issue authorization codes
/// - Exchange codes for access tokens
/// - Provide userinfo endpoints
/// - Support token introspection
/// - Serve JWKS for JWT verification
final class OAuthProviderModePlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthUserDeletionPlanContributor,
        AuthUserAccessRevocationContributor,
        AuthOAuthTokenEndpointHost<TContext> {
  OAuthProviderModePlugin({
    required this.clientStore,
    required this.authorizationCodeStore,
    required this.accessTokenStore,
    this.options = const OAuthProviderModeOptions(),
  }) {
    if (options.oidc != null && !options.supportedScopes.contains('openid')) {
      throw ArgumentError.value(
        options.supportedScopes,
        'options.supportedScopes',
        'must include openid when OIDC is configured',
      );
    }
  }

  /// Store for OAuth client registrations.
  final OAuthClientStore clientStore;

  /// Store for authorization codes.
  final OAuthAuthorizationCodeStore authorizationCodeStore;

  /// Store for access tokens.
  final OAuthAccessTokenStore accessTokenStore;

  /// Configuration options.
  final OAuthProviderModeOptions options;

  /// Core auth store for user lookups.
  late AuthStore _store;
  late AuthUserDeletionDomain _deletionDomain;
  final Map<String, AuthOAuthTokenGrantHandler<TContext>> _grantHandlers = {};

  @override
  String get userDataNamespace => authOAuthProviderModePluginId;

  @override
  String get userAccessNamespace => authOAuthProviderModePluginId;

  @override
  Future<AuthUserDeletionPlan> createUserDeletionPlan(AuthUser user) {
    if (_deletionDomain is! AuthInMemoryUserDeletionDomain ||
        authorizationCodeStore is! AuthInMemoryUserDeletionStore ||
        accessTokenStore is! AuthInMemoryUserDeletionStore) {
      throw StateError(
        'The OAuth provider adapter has no plan for this domain.',
      );
    }
    return Future.value(
      AuthInMemoryUserDeletionPlan(
        domain: _deletionDomain as AuthInMemoryUserDeletionDomain,
        userId: user.id,
        namespace: userDataNamespace,
        operation: AuthInMemoryCompositeDeletionOperation([
          AuthInMemoryStoreDeletionOperation(
            store: authorizationCodeStore as AuthInMemoryUserDeletionStore,
            userId: user.id,
          ),
          AuthInMemoryStoreDeletionOperation(
            store: accessTokenStore as AuthInMemoryUserDeletionStore,
            userId: user.id,
          ),
        ]),
      ),
    );
  }

  @override
  Future<void> revokeUserAccess(String userId) async {
    await authorizationCodeStore.deleteForUser(userId);
    await accessTokenStore.revokeAllForUser(userId);
  }

  @override
  String get id => authOAuthProviderModePluginId;

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    _store = context.store;
    final host = context.store;
    if (host is! AuthUserDeletionCoordinatorHost) {
      throw StateError(
        'OAuthProviderModePlugin requires a deletion-coordinator host store.',
      );
    }
    _deletionDomain = (host as AuthUserDeletionCoordinatorHost)
        .userDeletionCoordinator
        .domain;
  }

  @override
  void registerOAuthTokenGrant(
    String grantType,
    AuthOAuthTokenGrantHandler<TContext> handler,
  ) {
    final normalized = grantType.trim();
    if (normalized.isEmpty || _grantHandlers.containsKey(normalized)) {
      throw StateError('OAuth token grant "$grantType" is already registered.');
    }
    _grantHandlers[normalized] = handler;
  }

  Map<String, String> get _paths => {
    'oauth_provider.authorize': options.authorizationEndpoint,
    'oauth_provider.token': options.tokenEndpoint,
    'oauth_provider.userinfo': options.userInfoEndpoint,
    'oauth_provider.introspect': options.introspectionEndpoint,
    if (options.oidc case final oidc?) ...<String, String>{
      'oauth_provider.discovery': oidc.discoveryEndpoint,
      'oauth_provider.jwks': oidc.jwksEndpoint,
    },
    'oauth_provider.clients.list': '/oauth/clients/list',
    'oauth_provider.clients.create': '/oauth/clients/create',
    'oauth_provider.clients.delete': '/oauth/clients/delete',
  };

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints => _paths.keys
      .map((operationId) {
        final isRead =
            operationId.endsWith('.authorize') ||
            operationId.endsWith('.list') ||
            operationId.endsWith('.discovery') ||
            operationId.endsWith('.jwks') ||
            operationId.endsWith('.userinfo');
        final method = isRead
            ? AuthOperationMethod.get
            : AuthOperationMethod.post;
        final isProtocolEndpoint =
            operationId == 'oauth_provider.token' ||
            operationId == 'oauth_provider.introspect' ||
            operationId == 'oauth_provider.userinfo' ||
            operationId == 'oauth_provider.discovery' ||
            operationId == 'oauth_provider.jwks';
        return TypedAuthEndpointDescriptor<
          TContext,
          Map<String, dynamic>,
          Object?
        >(
          id: operationId,
          method: method,
          path: _paths[operationId]!,
          semantics: _operationSemantics(operationId),
          requestCodec: const AuthOperationCodec(
            decode: _identityMap,
            encode: _identityMap,
          ),
          responseCodec: const AuthOperationCodec(
            decode: _identityObject,
            encode: _identityObject,
          ),
          authentication: _endpointAuthentication(operationId),
          originPolicy:
              method == AuthOperationMethod.post && !isProtocolEndpoint
              ? AuthOperationOriginPolicy.browser
              : AuthOperationOriginPolicy.none,
          csrfPolicy: method == AuthOperationMethod.post && !isProtocolEndpoint
              ? AuthOperationCsrfPolicy.required
              : AuthOperationCsrfPolicy.none,
          rateLimitOperation: AuthRateLimitOperation(
            'oauth_provider',
            operationId.split('.').last,
          ),
          handler: (invocation, request) =>
              _invokeEndpoint(operationId, invocation, request),
        );
      })
      .toList(growable: false);

  static AuthOperationSemantics _operationSemantics(String operationId) {
    switch (operationId) {
      case 'oauth_provider.userinfo':
      case 'oauth_provider.discovery':
      case 'oauth_provider.jwks':
      case 'oauth_provider.introspect':
      case 'oauth_provider.clients.list':
        return const AuthOperationSemantics.readOnly();
      case 'oauth_provider.authorize':
      case 'oauth_provider.clients.create':
        return const AuthOperationSemantics.mutation(
          persistence: AuthMutationPersistence.durable(
            atomicity: AuthMutationAtomicity.nonAtomic,
            reference: AuthPersistenceOperationReference(
              schemaId: 'oauth_provider_mode',
            ),
          ),
          replaySafety: AuthMutationReplaySafety.repeatable,
        );
      case 'oauth_provider.clients.delete':
        return const AuthOperationSemantics.mutation(
          persistence: AuthMutationPersistence.durable(
            atomicity: AuthMutationAtomicity.nonAtomic,
            reference: AuthPersistenceOperationReference(
              schemaId: 'oauth_provider_mode',
            ),
          ),
          replaySafety: AuthMutationReplaySafety.singleUse,
        );
      case 'oauth_provider.token':
        return const AuthOperationSemantics.mutation(
          persistence: AuthMutationPersistence.durable(
            atomicity: AuthMutationAtomicity.nonAtomic,
            reference: AuthPersistenceOperationReference(
              schemaId: 'oauth_provider_mode',
            ),
          ),
          replaySafety: AuthMutationReplaySafety.unguarded,
        );
    }
    throw StateError('Unknown OAuth provider operation $operationId');
  }

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

  /// Resolves the authentication policy for each endpoint.
  ///
  /// Token, introspect, and JWKS endpoints are called by OAuth clients
  /// without a Routed session. UserInfo validates its own bearer token.
  /// Client management endpoints require a session (admin caller).
  AuthOperationAuthentication _endpointAuthentication(String operationId) {
    switch (operationId) {
      case 'oauth_provider.jwks':
      case 'oauth_provider.discovery':
      case 'oauth_provider.token':
      case 'oauth_provider.introspect':
        return AuthOperationAuthentication.none;
      case 'oauth_provider.userinfo':
        // UserInfo requires a bearer access token, not a session.
        // The handler validates the token itself.
        return AuthOperationAuthentication.none;
      // Client management requires an authenticated admin session.
      case 'oauth_provider.clients.list':
      case 'oauth_provider.clients.create':
      case 'oauth_provider.clients.delete':
        return AuthOperationAuthentication.session;
      default:
        return AuthOperationAuthentication.session;
    }
  }

  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => const [
    AuthPersistenceSchema(
      id: 'oauth_provider_mode',
      entities: [
        AuthEntityDescriptor(
          id: 'oauth_client',
          fields: [
            AuthFieldDescriptor(name: 'clientId', kind: 'id'),
            AuthFieldDescriptor(name: 'clientSecretHash', kind: 'string'),
            AuthFieldDescriptor(name: 'name', kind: 'string'),
            AuthFieldDescriptor(name: 'description', kind: 'nullable_string'),
            AuthFieldDescriptor(name: 'redirectUris', kind: 'string_list'),
            AuthFieldDescriptor(name: 'grantTypes', kind: 'string_list'),
            AuthFieldDescriptor(name: 'scopes', kind: 'string_list'),
            AuthFieldDescriptor(
              name: 'tokenEndpointAuthMethod',
              kind: 'string',
            ),
            AuthFieldDescriptor(name: 'enabled', kind: 'boolean'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'updatedAt', kind: 'datetime'),
          ],
          uniqueConstraints: [
            ['clientId'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'oauth_authorization_code',
          fields: [
            AuthFieldDescriptor(name: 'codeHash', kind: 'secret_digest'),
            AuthFieldDescriptor(name: 'clientId', kind: 'id'),
            AuthFieldDescriptor(name: 'userId', kind: 'id'),
            AuthFieldDescriptor(name: 'redirectUri', kind: 'string'),
            AuthFieldDescriptor(name: 'scope', kind: 'string'),
            AuthFieldDescriptor(name: 'expiresAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'codeChallenge', kind: 'nullable_string'),
            AuthFieldDescriptor(
              name: 'codeChallengeMethod',
              kind: 'nullable_string',
            ),
            AuthFieldDescriptor(name: 'nonce', kind: 'nullable_string'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
          ],
          indexes: [
            ['clientId'],
            ['userId'],
            ['expiresAt'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'oauth_access_token',
          fields: [
            AuthFieldDescriptor(name: 'tokenHash', kind: 'secret_digest'),
            AuthFieldDescriptor(name: 'clientId', kind: 'id'),
            AuthFieldDescriptor(name: 'userId', kind: 'id'),
            AuthFieldDescriptor(name: 'scope', kind: 'string'),
            AuthFieldDescriptor(name: 'expiresAt', kind: 'datetime'),
            AuthFieldDescriptor(
              name: 'refreshTokenHash',
              kind: 'nullable_secret_digest',
            ),
            AuthFieldDescriptor(name: 'issuedAt', kind: 'datetime'),
          ],
          indexes: [
            ['clientId'],
            ['userId'],
            ['expiresAt'],
          ],
        ),
      ],
      atomicOperations: [
        AuthAtomicOperationDescriptor(
          id: 'issueToken',
          description: 'Issue an access token and optionally a refresh token.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'exchangeCode',
          description:
              'Exchange an authorization code for tokens and invalidate the code.',
        ),
      ],
    ),
  ];

  Future<Object?> _invokeEndpoint(
    String operationId,
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    switch (operationId) {
      case 'oauth_provider.authorize':
        return _handleAuthorize(invocation, input);
      case 'oauth_provider.token':
        return _handleToken(invocation, input);
      case 'oauth_provider.userinfo':
        return _handleUserInfo(invocation, input);
      case 'oauth_provider.discovery':
        return _handleDiscovery();
      case 'oauth_provider.jwks':
        return _handleJwks();
      case 'oauth_provider.introspect':
        return _handleIntrospect(invocation, input);
      case 'oauth_provider.clients.list':
        return _handleListClients(invocation);
      case 'oauth_provider.clients.create':
        return _handleCreateClient(invocation, input);
      case 'oauth_provider.clients.delete':
        return _handleDeleteClient(invocation, input);
    }
    throw AuthFlowException('operation_not_found');
  }

  Future<AuthEndpointRedirect> _handleAuthorize(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    final user = invocation.user;
    if (user == null || authUserIsDisabled(user)) {
      throw AuthFlowException('unauthorized');
    }

    final clientId = input['client_id']?.toString();
    final redirectUri = input['redirect_uri']?.toString();
    final responseType = input['response_type']?.toString();
    final scope = input['scope']?.toString();
    final state = input['state']?.toString();
    final codeChallenge = input['code_challenge']?.toString();
    final codeChallengeMethod =
        input['code_challenge_method']?.toString() ?? 'S256';
    final nonce = input['nonce']?.toString();

    if (clientId == null || clientId.isEmpty) {
      throw AuthFlowException('invalid_request');
    }
    if (responseType == null || responseType.isEmpty) {
      throw AuthFlowException('invalid_request');
    }
    if (!options.supportedResponseTypes.contains(responseType) ||
        responseType != 'code') {
      throw AuthFlowException('unsupported_response_type');
    }
    if (redirectUri == null || redirectUri.isEmpty) {
      throw AuthFlowException('invalid_request');
    }

    // Validate client
    final client = await clientStore.findById(clientId);
    if (client == null || !client.enabled) {
      throw AuthFlowException('invalid_client');
    }

    // Validate redirect URI
    if (!client.redirectUris.contains(redirectUri)) {
      throw AuthFlowException('invalid_redirect_uri');
    }

    // Validate requested scopes against the provider and client allow-lists.
    final grantedScope = _resolveGrantedScope(scope, client);

    // OAuth 2.1 authorization codes use S256 PKCE. Optional PKCE means the
    // challenge may be omitted, not that weaker methods are accepted.
    if (options.requirePkce &&
        (codeChallenge == null || codeChallenge.trim().isEmpty)) {
      throw AuthFlowException('invalid_request');
    }
    if (codeChallenge != null &&
        (codeChallenge.trim().isEmpty || codeChallengeMethod != 'S256')) {
      throw AuthFlowException('invalid_request');
    }

    // Generate authorization code
    final code = secureRandomToken();
    final now = DateTime.now().toUtc();
    final authCode = OAuthAuthorizationCode(
      codeHash: hashOpaqueToken(code),
      clientId: clientId,
      userId: user.id,
      redirectUri: redirectUri,
      scope: grantedScope,
      expiresAt: now.add(options.codeLifetime),
      codeChallenge: codeChallenge,
      codeChallengeMethod: codeChallengeMethod,
      nonce: nonce,
      createdAt: now,
    );

    await authorizationCodeStore.create(authCode);

    final target = Uri.parse(redirectUri);
    return AuthEndpointRedirect(
      location: target.replace(
        queryParameters: <String, String>{
          ...target.queryParameters,
          'code': code,
          'state': ?state,
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _handleToken(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    final grantType = input['grant_type']?.toString();
    final credentials = _clientCredentials(input);
    final clientId = credentials.$1 ?? input['client_id']?.toString();

    if (grantType == null || grantType.isEmpty) {
      throw AuthFlowException('invalid_request');
    }
    final contributed = _grantHandlers[grantType];
    if (contributed != null) {
      final result = await contributed(invocation, input);
      if (result is! Map<String, dynamic>) {
        throw StateError('OAuth token grant returned a non-object response.');
      }
      return result;
    }
    if (!options.supportedGrantTypes.contains(grantType)) {
      throw AuthFlowException('unsupported_grant_type');
    }

    // Validate the client and its allowed grant types before dispatching.
    if (clientId != null && clientId.isNotEmpty) {
      final client = await clientStore.findById(clientId);
      if (client == null || !client.enabled) {
        throw AuthFlowException('invalid_client');
      }
      if (!client.grantTypes.contains(grantType)) {
        throw AuthFlowException('unauthorized_client');
      }
      if (grantType == 'client_credentials' ||
          client.tokenEndpointAuthMethod != 'none') {
        final secret = credentials.$2 ?? input['client_secret']?.toString();
        if (secret == null ||
            !await clientStore.validateSecret(clientId, secret)) {
          throw AuthFlowException('invalid_client');
        }
      }
    }

    switch (grantType) {
      case 'authorization_code':
        return _handleAuthorizationCodeGrant(input);
      case 'client_credentials':
        return _handleClientCredentialsGrant(invocation, input);
      case 'refresh_token':
        return _handleRefreshTokenGrant(input);
      default:
        throw AuthFlowException('unsupported_grant_type');
    }
  }

  Future<Map<String, dynamic>> _handleAuthorizationCodeGrant(
    Map<String, dynamic> input,
  ) async {
    final credentials = _clientCredentials(input);
    final code = input['code']?.toString();
    final clientId = credentials.$1 ?? input['client_id']?.toString();
    final redirectUri = input['redirect_uri']?.toString();
    final codeVerifier = input['code_verifier']?.toString();

    if (code == null || clientId == null || redirectUri == null) {
      throw AuthFlowException('invalid_request');
    }

    // Validate client
    final client = await clientStore.findById(clientId);
    if (client == null || !client.enabled) {
      throw AuthFlowException('invalid_client');
    }

    // Atomically consume the authorization code and all of its bindings. A
    // failed binding check still consumes a matching code to prevent retries
    // with captured credentials.
    final authCode = await authorizationCodeStore.consume(
      codeHash: hashOpaqueToken(code),
      clientId: clientId,
      redirectUri: redirectUri,
      codeVerifier: codeVerifier,
    );
    if (authCode == null) {
      throw AuthFlowException('invalid_grant');
    }

    final user = await _activeUser(authCode.userId);
    if (user == null) throw AuthFlowException('invalid_grant');

    // Issue tokens
    return _issueTokens(
      clientId: clientId,
      userId: authCode.userId,
      scope: authCode.scope,
      nonce: authCode.nonce,
      oidcUser: user,
      issueRefreshToken: client.grantTypes.contains('refresh_token'),
    );
  }

  Future<Map<String, dynamic>> _handleClientCredentialsGrant(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    final credentials = _clientCredentials(input);
    final clientId = credentials.$1 ?? input['client_id']?.toString();
    final clientSecret = credentials.$2 ?? input['client_secret']?.toString();
    final scope = input['scope']?.toString();

    if (clientId == null || clientSecret == null) {
      throw AuthFlowException('invalid_request');
    }

    // Validate client
    final client = await clientStore.findById(clientId);
    if (client == null || !client.enabled) {
      throw AuthFlowException('invalid_client');
    }

    // Validate secret
    if (!await clientStore.validateSecret(clientId, clientSecret)) {
      throw AuthFlowException('invalid_client');
    }

    // Validate requested scopes against the provider and client allow-lists.
    final grantedScope = _resolveGrantedScope(scope, client);
    if (_containsScope(grantedScope, 'openid')) {
      throw AuthFlowException('invalid_scope');
    }

    // Client credentials don't have a user context
    // Use a system user ID or the client ID itself
    return _issueTokens(
      clientId: clientId,
      userId: 'system:$clientId',
      scope: grantedScope,
      issueRefreshToken: client.grantTypes.contains('refresh_token'),
    );
  }

  Future<Map<String, dynamic>> _handleRefreshTokenGrant(
    Map<String, dynamic> input,
  ) async {
    final credentials = _clientCredentials(input);
    final refreshToken = input['refresh_token']?.toString();
    final clientId = credentials.$1 ?? input['client_id']?.toString();

    if (refreshToken == null ||
        refreshToken.trim().isEmpty ||
        clientId == null ||
        clientId.trim().isEmpty) {
      throw AuthFlowException('invalid_request');
    }

    // Validate client
    final client = await clientStore.findById(clientId);
    if (client == null || !client.enabled) {
      throw AuthFlowException('invalid_client');
    }

    // Find the original token by its refresh token. A null result means the
    // token was revoked or never existed. We validate the refresh-token
    // lifetime (not the access-token expiry) so refresh remains possible after
    // the access token has expired, which is the entire point of refresh
    // tokens.
    final originalToken = await accessTokenStore.findByRefreshToken(
      refreshToken,
    );
    if (originalToken == null || !originalToken.isRefreshTokenValid()) {
      throw AuthFlowException('invalid_grant');
    }
    final user = originalToken.userId.startsWith('system:')
        ? null
        : await _activeUser(originalToken.userId);
    if (!originalToken.userId.startsWith('system:') && user == null) {
      throw AuthFlowException('invalid_grant');
    }

    final maxUses = options.maxRefreshTokenUses;
    if (maxUses != null &&
        (maxUses <= 0 || originalToken.refreshTokenUses >= maxUses)) {
      throw AuthFlowException('invalid_grant');
    }

    // Validate the token belongs to the requesting client
    if (originalToken.clientId != clientId) {
      throw AuthFlowException('invalid_grant');
    }

    final rotating = options.allowRefreshTokenRotation;
    final now = DateTime.now().toUtc();
    final nextAccessToken = secureRandomToken();
    final nextRefreshToken = rotating ? secureRandomToken() : refreshToken;
    final replacement = OAuthAccessToken(
      tokenHash: hashOpaqueToken(nextAccessToken),
      clientId: clientId,
      userId: originalToken.userId,
      scope: originalToken.scope,
      expiresAt: now.add(options.accessTokenLifetime),
      refreshTokenHash: hashOpaqueToken(nextRefreshToken),
      refreshTokenExpiresAt: originalToken.refreshTokenExpiresAt,
      refreshTokenUses: originalToken.refreshTokenUses + 1,
      issuedAt: now,
    );
    final idToken = _containsScope(replacement.scope, 'openid')
        ? _issueIdToken(
            clientId: clientId,
            user: user!,
            scope: replacement.scope,
          )
        : null;
    final consumed = await accessTokenStore.rotateRefreshToken(
      refreshToken: refreshToken,
      expectedTokenHash: originalToken.tokenHash,
      replacement: replacement,
      maxUses: maxUses,
    );
    if (consumed == null) throw AuthFlowException('invalid_grant');

    return <String, dynamic>{
      'access_token': nextAccessToken,
      'token_type': 'Bearer',
      'expires_in': options.accessTokenLifetime.inSeconds,
      'refresh_token': nextRefreshToken,
      'scope': replacement.scope,
      'id_token': ?idToken,
    };
  }

  Future<Map<String, dynamic>> _handleUserInfo(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    // UserInfo is called with a bearer access token, not a session.
    // The route handler injects the Authorization header as '_authorization'.
    final authHeader = input['_authorization']?.toString();
    final token = _extractBearerToken(authHeader);
    if (token == null || token.isEmpty) {
      throw AuthFlowException('invalid_token');
    }

    final accessToken = await accessTokenStore.findByToken(token);
    if (accessToken == null || !accessToken.isValid()) {
      throw AuthFlowException('invalid_token');
    }
    final client = await clientStore.findById(accessToken.clientId);
    if (client == null || !client.enabled) {
      throw AuthFlowException('invalid_token');
    }

    // Look up the user from the store
    final user = await _activeUser(accessToken.userId);
    if (user == null) {
      throw AuthFlowException('invalid_token');
    }

    return _userInfoClaims(user, accessToken.scope);
  }

  String? _extractBearerToken(String? authorizationHeader) {
    if (authorizationHeader == null) return null;
    const prefix = 'Bearer ';
    if (authorizationHeader.startsWith(prefix)) {
      return authorizationHeader.substring(prefix.length).trim();
    }
    return null;
  }

  Map<String, dynamic> _handleDiscovery() {
    final oidc = options.oidc;
    if (oidc == null) throw StateError('OIDC is not configured.');
    return <String, dynamic>{
      'issuer': oidc.issuer.toString(),
      'authorization_endpoint': _absoluteEndpoint(
        oidc.issuer,
        options.authorizationEndpoint,
      ),
      'token_endpoint': _absoluteEndpoint(oidc.issuer, options.tokenEndpoint),
      'userinfo_endpoint': _absoluteEndpoint(
        oidc.issuer,
        options.userInfoEndpoint,
      ),
      'jwks_uri': _absoluteEndpoint(oidc.issuer, oidc.jwksEndpoint),
      'introspection_endpoint': _absoluteEndpoint(
        oidc.issuer,
        options.introspectionEndpoint,
      ),
      'response_types_supported': options.supportedResponseTypes,
      'grant_types_supported': options.supportedGrantTypes,
      'scopes_supported': _effectiveSupportedScopes,
      'subject_types_supported': const <String>['public'],
      'id_token_signing_alg_values_supported': <String>[oidc.signingAlgorithm],
      'token_endpoint_auth_methods_supported': const <String>[
        'client_secret_basic',
        'client_secret_post',
        'none',
      ],
      'code_challenge_methods_supported': const <String>['S256'],
      'claims_supported': const <String>[
        'iss',
        'sub',
        'aud',
        'exp',
        'iat',
        'nonce',
        'email',
        'name',
        'picture',
      ],
    };
  }

  Map<String, dynamic> _handleJwks() {
    final oidc = options.oidc;
    if (oidc == null) throw StateError('OIDC is not configured.');
    return <String, dynamic>{
      'keys': <Map<String, dynamic>>[oidc.publicJwk],
    };
  }

  Future<Map<String, dynamic>> _handleIntrospect(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    await _requireClientCredentials(input);
    final token = input['token']?.toString();
    if (token == null) {
      throw AuthFlowException('invalid_request');
    }

    final accessToken = await accessTokenStore.findByToken(token);
    if (accessToken == null || !accessToken.isValid()) {
      return {'active': false};
    }
    final tokenClient = await clientStore.findById(accessToken.clientId);
    if (tokenClient == null || !tokenClient.enabled) {
      return {'active': false};
    }
    if (!accessToken.userId.startsWith('system:') &&
        await _activeUser(accessToken.userId) == null) {
      return {'active': false};
    }

    return {
      'active': true,
      'sub': accessToken.userId,
      'client_id': accessToken.clientId,
      'scope': accessToken.scope,
      'exp': accessToken.expiresAt.millisecondsSinceEpoch ~/ 1000,
      'iat': accessToken.issuedAt != null
          ? accessToken.issuedAt!.millisecondsSinceEpoch ~/ 1000
          : null,
      'token_type': 'Bearer',
    };
  }

  Future<List<Map<String, dynamic>>> _handleListClients(
    AuthOperationInvocation<TContext> invocation,
  ) async {
    _requireAdmin(invocation);
    final clients = await clientStore.listAll();
    return clients.map((client) => client.toJson()).toList();
  }

  Future<Map<String, dynamic>> _handleCreateClient(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    _requireAdmin(invocation);
    final name = input['name']?.toString();
    final redirectUris = input['redirect_uris'] as List?;
    final scopes = input['scopes'] as List?;
    final requestedGrantTypes =
        (input['grant_types'] ?? input['grantTypes']) as List?;

    if (name == null || redirectUris == null) {
      throw AuthFlowException('invalid_request');
    }
    final grantTypes = requestedGrantTypes
        ?.map((value) => value.toString())
        .toSet()
        .toList(growable: false);
    final effectiveGrantTypes =
        grantTypes ??
        (options.supportedGrantTypes.contains('authorization_code')
            ? const ['authorization_code']
            : options.supportedGrantTypes.take(1).toList(growable: false));
    if (effectiveGrantTypes.isEmpty ||
        !effectiveGrantTypes.every(options.supportedGrantTypes.contains)) {
      throw AuthFlowException('invalid_client_metadata');
    }

    final clientId = secureRandomToken();
    final clientSecret = secureRandomToken();
    final clientSecretHash = _hashClientSecret(clientSecret);

    final now = DateTime.now().toUtc();
    final effectiveScopes =
        scopes?.map((value) => value.toString()).toList(growable: false) ??
        _effectiveSupportedScopes;
    if (!effectiveScopes.every(_effectiveSupportedScopes.contains)) {
      throw AuthFlowException('invalid_client_metadata');
    }
    final client = OAuthClient(
      clientId: clientId,
      clientSecretHash: clientSecretHash,
      name: name,
      description: input['description']?.toString(),
      redirectUris: redirectUris.map((e) => e.toString()).toList(),
      grantTypes: effectiveGrantTypes,
      scopes: effectiveScopes,
      createdAt: now,
      updatedAt: now,
    );

    await clientStore.create(client);

    // Return the client with the plaintext secret (one-time display)
    return {...client.toJson(), 'client_secret': clientSecret};
  }

  Future<Map<String, dynamic>> _handleDeleteClient(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    _requireAdmin(invocation);
    final clientId = input['client_id']?.toString();
    if (clientId == null) {
      throw AuthFlowException('invalid_request');
    }

    await accessTokenStore.revokeAllForClient(clientId);
    await clientStore.delete(clientId);
    return {'deleted': true};
  }

  /// Validates the caller is an administrator.
  ///
  /// Client management endpoints require an authenticated user with
  /// the `admin` role. This check runs after Routed session resolution
  /// populates `invocation.user`.
  void _requireAdmin(AuthOperationInvocation<TContext> invocation) {
    final user = invocation.user;
    if (user == null) {
      throw AuthFlowException('unauthorized');
    }
    if (!user.roles.contains('admin')) {
      throw AuthFlowException('admin_required');
    }
  }

  Future<AuthUser?> _activeUser(String userId) async {
    final user = await _store.users.findById(userId);
    if (user == null || user.attributes['deletedAt'] != null) return null;
    final states = _store is AuthAccountStateStore
        ? _store as AuthAccountStateStore
        : null;
    final state = await states?.find(userId);
    if (state?.disabled == true || state?.isLocked() == true) return null;
    return user;
  }

  Map<String, dynamic> _userInfoClaims(AuthUser user, String scope) {
    final grantedScopes = scope
        .split(' ')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final claims = <String, dynamic>{'sub': user.id};
    if (grantedScopes.contains('email')) {
      claims['email'] = user.email;
    }
    if (grantedScopes.contains('profile')) {
      claims['name'] = user.name;
      claims['picture'] = user.image;
    }
    for (final scope in grantedScopes) {
      final allowedClaims = options.userInfoClaimsByScope[scope];
      if (allowedClaims == null) continue;
      for (final claim in allowedClaims) {
        final normalizedClaim = claim.trim();
        if (normalizedClaim.isEmpty ||
            _reservedUserInfoClaims.contains(normalizedClaim) ||
            !user.attributes.containsKey(normalizedClaim)) {
          continue;
        }
        claims[normalizedClaim] = user.attributes[normalizedClaim];
      }
    }
    return claims;
  }

  Future<Map<String, dynamic>> _issueTokens({
    required String clientId,
    required String userId,
    required String scope,
    String? nonce,
    AuthUser? oidcUser,
    bool issueRefreshToken = false,
    String? refreshToken,
    DateTime? refreshTokenExpiresAt,
  }) async {
    final now = DateTime.now().toUtc();
    final accessTokenValue = secureRandomToken();
    final refreshTokenValue = refreshToken ?? secureRandomToken();
    final hasRefreshToken =
        issueRefreshToken && options.refreshTokenLifetime > Duration.zero;

    final accessToken = OAuthAccessToken(
      tokenHash: hashOpaqueToken(accessTokenValue),
      clientId: clientId,
      userId: userId,
      scope: scope,
      expiresAt: now.add(options.accessTokenLifetime),
      refreshTokenHash: hasRefreshToken
          ? hashOpaqueToken(refreshTokenValue)
          : null,
      // The refresh token outlives the access token; its own expiry is tracked
      // separately so refresh grants remain valid after the access token has
      // expired.
      refreshTokenExpiresAt: hasRefreshToken
          ? (refreshTokenExpiresAt ?? now.add(options.refreshTokenLifetime))
          : null,
      issuedAt: now,
    );

    final idToken = _containsScope(scope, 'openid')
        ? _issueIdToken(
            clientId: clientId,
            user:
                oidcUser ??
                (throw StateError('OIDC token issuance requires a user.')),
            scope: scope,
            nonce: nonce,
          )
        : null;

    await accessTokenStore.save(accessToken);

    return <String, dynamic>{
      'access_token': accessTokenValue,
      'token_type': 'Bearer',
      'expires_in': options.accessTokenLifetime.inSeconds,
      if (hasRefreshToken) 'refresh_token': refreshTokenValue,
      'scope': scope,
      'id_token': ?idToken,
    };
  }

  String _issueIdToken({
    required String clientId,
    required AuthUser user,
    required String scope,
    String? nonce,
  }) {
    final oidc = options.oidc;
    if (oidc == null) {
      throw AuthFlowException('invalid_scope');
    }
    final now = DateTime.now().toUtc();
    final claims = <String, dynamic>{
      ..._userInfoClaims(user, scope),
      'iss': oidc.issuer.toString(),
      'aud': clientId,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': now.add(oidc.idTokenLifetime).millisecondsSinceEpoch ~/ 1000,
      if (nonce != null && nonce.isNotEmpty) 'nonce': nonce,
    };
    final builder = JsonWebSignatureBuilder()
      ..jsonContent = claims
      ..setProtectedHeader('typ', 'JWT')
      ..setProtectedHeader('kid', oidc.signingKey.keyId)
      ..addRecipient(oidc.signingKey, algorithm: oidc.signingAlgorithm);
    return builder.build().toCompactSerialization();
  }

  /// Resolves and validates a requested scope string against the scopes
  /// supported by this provider ([OAuthProviderModeOptions.supportedScopes])
  /// and the scopes granted to [client].
  ///
  /// Returns the normalized space-joined scope string. Throws
  /// [AuthFlowException] with `invalid_scope` when the request is empty or
  /// asks for a scope that is not allowed for this client.
  String _resolveGrantedScope(String? rawScope, OAuthClient client) {
    final requested = rawScope?.split(' ').where((s) => s.isNotEmpty).toSet();
    final allowed = _effectiveSupportedScopes.toSet().intersection(
      client.scopes.toSet(),
    );
    if (requested == null || requested.isEmpty) {
      // Default to the intersection of provider and client scopes when the
      // request omits the scope parameter.
      return allowed.join(' ');
    }
    if (!requested.every(allowed.contains)) {
      throw AuthFlowException('invalid_scope');
    }
    return requested.join(' ');
  }

  List<String> get _effectiveSupportedScopes => options.supportedScopes
      .where((scope) => scope != 'openid' || options.oidc != null)
      .toList(growable: false);

  String _hashClientSecret(String secret) {
    // In a real implementation, use a proper password hasher
    // For now, use a simple hash
    final bytes = utf8.encode(secret);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<OAuthClient> _requireClientCredentials(
    Map<String, dynamic> input,
  ) async {
    final credentials = _clientCredentials(input);
    final clientId = credentials.$1 ?? input['client_id']?.toString();
    final secret = credentials.$2 ?? input['client_secret']?.toString();
    if (clientId == null || secret == null) {
      throw AuthFlowException('invalid_client');
    }
    final client = await clientStore.findById(clientId);
    if (client == null ||
        !client.enabled ||
        !await clientStore.validateSecret(clientId, secret)) {
      throw AuthFlowException('invalid_client');
    }
    return client;
  }

  (String?, String?) _clientCredentials(Map<String, dynamic> input) {
    final authorization = input['_authorization']?.toString();
    if (authorization == null || !authorization.startsWith('Basic ')) {
      return (null, null);
    }
    try {
      final decoded = utf8.decode(base64.decode(authorization.substring(6)));
      final separator = decoded.indexOf(':');
      if (separator <= 0) return (null, null);
      return (
        Uri.decodeComponent(decoded.substring(0, separator)),
        Uri.decodeComponent(decoded.substring(separator + 1)),
      );
    } on FormatException {
      return (null, null);
    }
  }
}

Map<String, dynamic> _identityMap(Map<String, dynamic> value) => value;
Object? _identityObject(Object? value) => value;

bool _containsScope(String value, String expected) => value
    .split(' ')
    .map((scope) => scope.trim())
    .where((scope) => scope.isNotEmpty)
    .contains(expected);

String _absoluteEndpoint(Uri issuer, String path) =>
    issuer.resolve(path).toString();

const Set<String> _reservedUserInfoClaims = {
  'sub',
  'email',
  'email_verified',
  'name',
  'given_name',
  'family_name',
  'middle_name',
  'nickname',
  'preferred_username',
  'profile',
  'picture',
  'website',
  'gender',
  'birthdate',
  'zoneinfo',
  'locale',
  'updated_at',
  'address',
  'phone_number',
  'phone_number_verified',
};
