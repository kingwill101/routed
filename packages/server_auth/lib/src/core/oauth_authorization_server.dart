import 'dart:async';

import 'deletion_transaction.dart';
import 'device_authorization.dart' show AuthDeviceAccessToken;
import 'exceptions.dart';
import 'plugin.dart';
import 'oauth_authorization_code_store.dart';
import 'rate_limit.dart';
import 'tokens.dart' show secureRandomToken;
import 'users.dart' show authUserIsDisabled;

const String authOAuthAuthorizationServerPluginId =
    'oauth_authorization_server';

/// An OAuth client accepted by the application authorization server.
final class AuthOAuthAuthorizationClient {
  const AuthOAuthAuthorizationClient({
    required this.clientId,
    required this.redirectUris,
    this.scopes = const <String>[],
  });

  final String clientId;
  final List<Uri> redirectUris;
  final List<String> scopes;
}

typedef AuthOAuthClientResolver<TContext> =
    FutureOr<AuthOAuthAuthorizationClient?> Function(
      TContext context,
      String clientId,
    );

typedef AuthOAuthAccessTokenIssuer<TContext> =
    FutureOr<AuthDeviceAccessToken> Function(
      TContext context,
      AuthOAuthAuthorizationCode authorizationCode,
    );

/// OAuth 2.1 authorization-code provider mode with mandatory S256 PKCE.
///
/// Client registration, token signing, refresh-token persistence, and user
/// consent remain application-owned callbacks. This plugin owns only the
/// protocol validation and one-time authorization-code transaction.
final class OAuthAuthorizationServerPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthClientOperationContributor,
        AuthPersistenceContributor,
        AuthRateLimitContributor,
        AuthReversibleUserDataDeletionContributor {
  OAuthAuthorizationServerPlugin({
    required this.authorizationCodes,
    required this.resolveClient,
    required this.issueAccessToken,
    this.codeLifetime = const Duration(minutes: 1),
  }) : _codeService = AuthOAuthAuthorizationCodeService(
         store: authorizationCodes,
         codeLifetime: codeLifetime,
       );

  final AuthOAuthAuthorizationCodeStore authorizationCodes;
  final AuthOAuthClientResolver<TContext> resolveClient;
  final AuthOAuthAccessTokenIssuer<TContext> issueAccessToken;
  final Duration codeLifetime;
  final AuthOAuthAuthorizationCodeService _codeService;

  @override
  String get id => authOAuthAuthorizationServerPluginId;

  @override
  void configure(AuthServerPluginContext<TContext> context) {}

  @override
  String get userDataNamespace => 'oauth_authorization_server';

  @override
  Future<void> validateUserDeletion(String userId) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must be non-empty');
    }
  }

  @override
  Future<void> deleteUserData(String userId) async {
    await authorizationCodes.deleteForUser(userId);
  }

  @override
  AuthUserDataDeletionCheckpoint checkpointUserData(String userId) =>
      AuthUserDataDeletionCheckpoint.capture([authorizationCodes]);

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints => [
    _endpoint(
      id: 'oauthAuthorizationServer.authorize',
      method: AuthOperationMethod.get,
      path: '/oauth/authorize',
      authentication: AuthOperationAuthentication.session,
      csrfPolicy: AuthOperationCsrfPolicy.none,
      operationName: 'authorize',
    ),
    _endpoint(
      id: 'oauthAuthorizationServer.token',
      method: AuthOperationMethod.post,
      path: '/oauth/token',
      authentication: AuthOperationAuthentication.none,
      originPolicy: AuthOperationOriginPolicy.none,
      csrfPolicy: AuthOperationCsrfPolicy.none,
      operationName: 'token',
    ),
  ];

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
  Iterable<AuthRateLimitOperation> get rateLimitOperations => const [
    AuthRateLimitOperation('oauth_authorization_server', 'authorize'),
    AuthRateLimitOperation('oauth_authorization_server', 'token'),
  ];

  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => const [
    AuthPersistenceSchema(
      id: authOAuthAuthorizationServerPluginId,
      entities: <AuthEntityDescriptor>[
        AuthEntityDescriptor(
          id: 'auth_oauth_authorization_code',
          fields: <AuthFieldDescriptor>[
            AuthFieldDescriptor(name: 'id', kind: 'id'),
            AuthFieldDescriptor(name: 'codeHash', kind: 'secret_digest'),
            AuthFieldDescriptor(name: 'clientId', kind: 'id'),
            AuthFieldDescriptor(name: 'userId', kind: 'id'),
            AuthFieldDescriptor(name: 'redirectUri', kind: 'uri'),
            AuthFieldDescriptor(name: 'scopes', kind: 'string_list'),
            AuthFieldDescriptor(name: 'codeChallenge', kind: 'string'),
            AuthFieldDescriptor(name: 'codeChallengeMethod', kind: 'enum'),
            AuthFieldDescriptor(name: 'createdAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'expiresAt', kind: 'datetime'),
            AuthFieldDescriptor(name: 'nonce', kind: 'nullable_string'),
            AuthFieldDescriptor(name: 'resource', kind: 'nullable_uri'),
          ],
          relationships: <AuthRelationshipDescriptor>[
            AuthRelationshipDescriptor(field: 'userId', targetEntity: 'user'),
          ],
          uniqueConstraints: <List<String>>[
            <String>['codeHash'],
          ],
          indexes: <List<String>>[
            <String>['expiresAt'],
            <String>['userId'],
          ],
        ),
      ],
      atomicOperations: <AuthAtomicOperationDescriptor>[
        AuthAtomicOperationDescriptor(
          id: 'oauthAuthorizationCode.consume',
          description:
              'Atomically validate client, redirect, expiry, and S256 PKCE before deleting a code.',
        ),
      ],
    ),
  ];

  AuthEndpointDescriptor<TContext> _endpoint({
    required String id,
    required AuthOperationMethod method,
    required String path,
    required AuthOperationAuthentication authentication,
    required AuthOperationCsrfPolicy csrfPolicy,
    required String operationName,
    AuthOperationOriginPolicy originPolicy = AuthOperationOriginPolicy.browser,
  }) => TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
    id: id,
    method: method,
    path: path,
    requestCodec: _mapCodec,
    responseCodec: _objectCodec,
    authentication: authentication,
    originPolicy: originPolicy,
    csrfPolicy: csrfPolicy,
    rateLimitOperation: AuthRateLimitOperation(
      authOAuthAuthorizationServerPluginId,
      operationName,
    ),
    handler: (invocation, request) => _invoke(id, invocation, request),
  );

  Future<Object?> _invoke(
    String id,
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> request,
  ) async {
    switch (id) {
      case 'oauthAuthorizationServer.authorize':
        return _authorize(invocation, request);
      case 'oauthAuthorizationServer.token':
        return _token(invocation, request);
      default:
        throw StateError('Unknown OAuth authorization endpoint $id');
    }
  }

  Future<AuthEndpointRedirect> _authorize(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> request,
  ) async {
    final user = invocation.user;
    if (user == null || authUserIsDisabled(user)) {
      throw AuthFlowException('unauthorized');
    }
    final clientId = _required(request, 'client_id');
    final redirectUri = _parseUri(_required(request, 'redirect_uri'));
    final client = await resolveClient(invocation.context, clientId);
    if (client == null || client.clientId != clientId) {
      throw AuthFlowException('invalid_client');
    }
    if (!client.redirectUris.contains(redirectUri)) {
      throw AuthFlowException('invalid_redirect_uri');
    }
    if (_required(request, 'response_type') != 'code') {
      throw AuthFlowException('unsupported_response_type');
    }
    final scopes = _parseScopes(request['scope']);
    if (client.scopes.isNotEmpty &&
        scopes.any((scope) => !client.scopes.contains(scope))) {
      throw AuthFlowException('invalid_scope');
    }
    final state = _optional(request, 'state');
    if (state != null && state.length > 1024) {
      throw AuthFlowException('invalid_request');
    }
    final resourceValue = _optional(request, 'resource');
    final resource = resourceValue == null ? null : _parseUri(resourceValue);
    final challenge = _required(request, 'code_challenge');
    final challengeMethod = _required(request, 'code_challenge_method');
    if (challengeMethod != 'S256') {
      throw AuthFlowException('invalid_request');
    }
    final rawCode = secureRandomToken();
    await _codeService.issue(
      rawCode: rawCode,
      clientId: clientId,
      userId: user.id,
      redirectUri: redirectUri,
      scopes: scopes,
      codeChallenge: challenge,
      codeChallengeMethod: challengeMethod,
      nonce: _optional(request, 'nonce'),
      resource: resource,
    );
    final query = <String, String>{
      ...redirectUri.queryParameters,
      'code': rawCode,
      'state': ?state,
    };
    return AuthEndpointRedirect(
      location: redirectUri.replace(queryParameters: query),
    );
  }

  Future<Map<String, dynamic>> _token(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> request,
  ) async {
    if (_required(request, 'grant_type') != 'authorization_code') {
      throw AuthFlowException('unsupported_grant_type');
    }
    final clientId = _required(request, 'client_id');
    final client = await resolveClient(invocation.context, clientId);
    if (client == null || client.clientId != clientId) {
      throw AuthFlowException('invalid_client');
    }
    final record = await _codeService.exchange(
      rawCode: _required(request, 'code'),
      clientId: clientId,
      redirectUri: _parseUri(_required(request, 'redirect_uri')),
      codeVerifier: _required(request, 'code_verifier'),
    );
    if (record == null) throw AuthFlowException('invalid_grant');
    final token = await issueAccessToken(invocation.context, record);
    return token.toJson();
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
}

String _required(Map<String, dynamic> request, String key) {
  final value = request[key];
  if (value is! String || value.trim().isEmpty) {
    throw AuthFlowException('invalid_request');
  }
  return value.trim();
}

String? _optional(Map<String, dynamic> request, String key) {
  final value = request[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw AuthFlowException('invalid_request');
  }
  return value.trim();
}

Uri _parseUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.isAbsolute ||
      uri.host.isEmpty ||
      uri.fragment.isNotEmpty) {
    throw AuthFlowException('invalid_request');
  }
  return uri;
}

List<String> _parseScopes(Object? value) {
  if (value == null) return const <String>[];
  if (value is! String) throw AuthFlowException('invalid_scope');
  return List<String>.unmodifiable(
    value.split(RegExp(r'\s+')).where((scope) => scope.isNotEmpty),
  );
}
