import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;

import 'exceptions.dart';
import 'account_policy.dart';
import 'models.dart';
import 'plugin.dart';
import 'oauth_client_store.dart';
import 'oauth_provider_models.dart';
import 'rate_limit.dart';
import 'store.dart';
import 'tokens.dart' show secureRandomToken;

const String authOAuthProviderModePluginId = 'oauth_provider_mode';

@Deprecated('Use authOAuthProviderModePluginId.')
const String authOAuthProviderModeFeatureId = authOAuthProviderModePluginId;

/// Feature that enables the application to act as an OAuth/OIDC provider.
///
/// This feature allows Routed applications to:
/// - Register OAuth clients
/// - Issue authorization codes
/// - Exchange codes for access tokens
/// - Provide userinfo endpoints
/// - Support token introspection
/// - Serve JWKS for JWT verification
class OAuthProviderModePlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthUserDataDeletionContributor,
        AuthUserAccessRevocationContributor {
  OAuthProviderModePlugin({
    required this.clientStore,
    required this.authorizationCodeStore,
    required this.accessTokenStore,
    this.options = const OAuthProviderModeOptions(),
  });

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

  @override
  String get userDataNamespace => authOAuthProviderModePluginId;

  @override
  String get userAccessNamespace => authOAuthProviderModePluginId;

  @override
  Future<void> validateUserDeletion(String userId) async {}

  @override
  Future<void> deleteUserData(String userId) async {
    await accessTokenStore.revokeAllForUser(userId);
  }

  @override
  Future<void> revokeUserAccess(String userId) async {
    await accessTokenStore.revokeAllForUser(userId);
  }

  @override
  String get id => authOAuthProviderModePluginId;

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    _store = context.store;
  }

  Map<String, String> get _paths => {
    'oauth_provider.authorize': options.authorizationEndpoint,
    'oauth_provider.token': options.tokenEndpoint,
    'oauth_provider.userinfo': options.userInfoEndpoint,
    'oauth_provider.jwks': options.jwksEndpoint,
    'oauth_provider.introspect': options.introspectionEndpoint,
    'oauth_provider.clients.list': '/oauth/clients/list',
    'oauth_provider.clients.create': '/oauth/clients/create',
    'oauth_provider.clients.delete': '/oauth/clients/delete',
  };

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints => _paths.keys
      .map((operationId) {
        final isRead =
            operationId.endsWith('.list') ||
            operationId.endsWith('.jwks') ||
            operationId.endsWith('.userinfo');
        final method = isRead
            ? AuthOperationMethod.get
            : AuthOperationMethod.post;
        final isProtocolEndpoint =
            operationId == 'oauth_provider.token' ||
            operationId == 'oauth_provider.introspect' ||
            operationId == 'oauth_provider.userinfo' ||
            operationId == 'oauth_provider.jwks';
        return TypedAuthEndpointDescriptor<
          TContext,
          Map<String, dynamic>,
          Object?
        >(
          id: operationId,
          method: method,
          path: _paths[operationId]!,
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
            AuthFieldDescriptor(name: 'code', kind: 'id'),
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
            AuthFieldDescriptor(name: 'token', kind: 'id'),
            AuthFieldDescriptor(name: 'clientId', kind: 'id'),
            AuthFieldDescriptor(name: 'userId', kind: 'id'),
            AuthFieldDescriptor(name: 'scope', kind: 'string'),
            AuthFieldDescriptor(name: 'expiresAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'refreshToken', kind: 'nullable_string'),
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

  Future<Map<String, dynamic>> _handleAuthorize(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    final user = invocation.user;
    if (user == null) throw AuthFlowException('unauthorized');

    final clientId = input['client_id']?.toString();
    final redirectUri = input['redirect_uri']?.toString();
    final responseType = input['response_type']?.toString();
    final scope = input['scope']?.toString() ?? 'openid';
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

    // Validate PKCE if required
    if (options.requirePkce && codeChallenge == null) {
      throw AuthFlowException('invalid_request');
    }

    // Generate authorization code
    final code = secureRandomToken();
    final now = DateTime.now().toUtc();
    final authCode = OAuthAuthorizationCode(
      code: code,
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

    await authorizationCodeStore.save(authCode);

    final response = <String, dynamic>{'code': code};
    if (state != null) response['state'] = state;
    return response;
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

    if (code == null || clientId == null) {
      throw AuthFlowException('invalid_request');
    }

    // Validate client
    final client = await clientStore.findById(clientId);
    if (client == null || !client.enabled) {
      throw AuthFlowException('invalid_client');
    }

    // Consume authorization code
    final authCode = await authorizationCodeStore.consume(code);
    if (authCode == null) {
      throw AuthFlowException('invalid_grant');
    }

    // Validate code belongs to client
    if (authCode.clientId != clientId) {
      throw AuthFlowException('invalid_grant');
    }

    // Validate redirect URI
    if (authCode.redirectUri != redirectUri) {
      throw AuthFlowException('invalid_grant');
    }

    // Validate PKCE
    if (authCode.codeChallenge != null) {
      if (codeVerifier == null) {
        throw AuthFlowException('invalid_grant');
      }
      if (!validatePkce(
        authCode.codeChallenge!,
        codeVerifier,
        authCode.codeChallengeMethod ?? 'S256',
      )) {
        throw AuthFlowException('invalid_grant');
      }
    }

    // Issue tokens
    return _issueTokens(
      clientId: clientId,
      userId: authCode.userId,
      scope: authCode.scope,
      nonce: authCode.nonce,
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
    final nextRefreshToken = rotating
        ? secureRandomToken()
        : originalToken.refreshToken!;
    final replacement = OAuthAccessToken(
      token: secureRandomToken(),
      clientId: clientId,
      userId: originalToken.userId,
      scope: originalToken.scope,
      expiresAt: now.add(options.accessTokenLifetime),
      refreshToken: nextRefreshToken,
      refreshTokenExpiresAt: originalToken.refreshTokenExpiresAt,
      refreshTokenUses: originalToken.refreshTokenUses + 1,
      issuedAt: now,
    );
    final consumed = await accessTokenStore.rotateRefreshToken(
      refreshToken: refreshToken,
      expectedToken: originalToken.token,
      replacement: replacement,
      maxUses: maxUses,
    );
    if (consumed == null) throw AuthFlowException('invalid_grant');

    return {
      'access_token': replacement.token,
      'token_type': 'Bearer',
      'expires_in': options.accessTokenLifetime.inSeconds,
      'refresh_token': nextRefreshToken,
      'scope': replacement.scope,
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

  Map<String, dynamic> _handleJwks() {
    // In a real implementation, this would return the public keys
    // For now, return an empty key set
    return {'keys': []};
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
    final client = OAuthClient(
      clientId: clientId,
      clientSecretHash: clientSecretHash,
      name: name,
      description: input['description']?.toString(),
      redirectUris: redirectUris.map((e) => e.toString()).toList(),
      grantTypes: effectiveGrantTypes,
      scopes:
          scopes?.map((e) => e.toString()).toList() ??
          ['openid', 'profile', 'email'],
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
      token: accessTokenValue,
      clientId: clientId,
      userId: userId,
      scope: scope,
      expiresAt: now.add(options.accessTokenLifetime),
      refreshToken: hasRefreshToken ? refreshTokenValue : null,
      // The refresh token outlives the access token; its own expiry is tracked
      // separately so refresh grants remain valid after the access token has
      // expired.
      refreshTokenExpiresAt: hasRefreshToken
          ? (refreshTokenExpiresAt ?? now.add(options.refreshTokenLifetime))
          : null,
      issuedAt: now,
    );

    await accessTokenStore.save(accessToken);

    return {
      'access_token': accessTokenValue,
      'token_type': 'Bearer',
      'expires_in': options.accessTokenLifetime.inSeconds,
      if (hasRefreshToken) 'refresh_token': refreshTokenValue,
      'scope': scope,
    };
  }

  /// Validates PKCE code challenge.
  bool validatePkce(String codeChallenge, String codeVerifier, String method) {
    if (method == 'S256') {
      final hash = sha256.convert(utf8.encode(codeVerifier));
      final encoded = base64Url.encode(hash.bytes).replaceAll('=', '');
      return encoded == codeChallenge;
    } else if (method == 'plain') {
      return codeVerifier == codeChallenge;
    }
    return false;
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
    final allowed = options.supportedScopes.toSet().intersection(
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

/// Backwards-compatible name retained for applications created before the
/// client/plugin terminology migration.
@Deprecated('Use OAuthProviderModePlugin.')
typedef OAuthProviderModeFeature<TContext> = OAuthProviderModePlugin<TContext>;

Map<String, dynamic> _identityMap(Map<String, dynamic> value) => value;
Object? _identityObject(Object? value) => value;

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
