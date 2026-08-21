import 'dart:async';

import 'exceptions.dart';
import 'plugin.dart';
import 'rate_limit.dart';

const String authMcpPluginId = 'mcp_auth';

/// RFC 9728 protected-resource metadata for an MCP HTTP server.
final class AuthOAuthProtectedResourceMetadata {
  const AuthOAuthProtectedResourceMetadata({
    required this.resource,
    required this.authorizationServers,
    this.resourceName,
    this.resourceDocumentation,
    this.scopesSupported = const <String>[],
    this.bearerMethodsSupported = const ['header'],
  });

  final Uri resource;
  final List<Uri> authorizationServers;
  final String? resourceName;
  final Uri? resourceDocumentation;
  final List<String> scopesSupported;
  final List<String> bearerMethodsSupported;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'resource': resource.toString(),
    'authorization_servers': authorizationServers
        .map((server) => server.toString())
        .toList(growable: false),
    if (resourceName != null) 'resource_name': resourceName,
    if (resourceDocumentation != null)
      'resource_documentation': resourceDocumentation.toString(),
    if (scopesSupported.isNotEmpty) 'scopes_supported': scopesSupported,
    if (bearerMethodsSupported.isNotEmpty)
      'bearer_methods_supported': bearerMethodsSupported,
  };
}

/// RFC 8414 authorization-server metadata advertised to MCP clients.
final class AuthOAuthAuthorizationServerMetadata {
  const AuthOAuthAuthorizationServerMetadata({
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.jwksUri,
    this.introspectionEndpoint,
    this.registrationEndpoint,
    this.scopesSupported = const <String>[],
    this.grantTypesSupported = const ['authorization_code'],
    this.responseTypesSupported = const ['code'],
    this.codeChallengeMethodsSupported = const ['S256'],
  });

  final Uri issuer;
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final Uri? jwksUri;
  final Uri? introspectionEndpoint;
  final Uri? registrationEndpoint;
  final List<String> scopesSupported;
  final List<String> grantTypesSupported;
  final List<String> responseTypesSupported;
  final List<String> codeChallengeMethodsSupported;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'issuer': issuer.toString(),
    'authorization_endpoint': authorizationEndpoint.toString(),
    'token_endpoint': tokenEndpoint.toString(),
    if (jwksUri != null) 'jwks_uri': jwksUri.toString(),
    if (introspectionEndpoint != null)
      'introspection_endpoint': introspectionEndpoint.toString(),
    if (registrationEndpoint != null)
      'registration_endpoint': registrationEndpoint.toString(),
    if (scopesSupported.isNotEmpty) 'scopes_supported': scopesSupported,
    if (grantTypesSupported.isNotEmpty)
      'grant_types_supported': grantTypesSupported,
    if (responseTypesSupported.isNotEmpty)
      'response_types_supported': responseTypesSupported,
    if (codeChallengeMethodsSupported.isNotEmpty)
      'code_challenge_methods_supported': codeChallengeMethodsSupported,
  };
}

/// A validated dynamic-client-registration request.
///
/// The registrar callback remains responsible for persistence, client ID
/// allocation, and any secret generation. The framework only validates the
/// protocol shape and redirect URI security boundary.
final class AuthOAuthClientRegistrationRequest {
  const AuthOAuthClientRegistrationRequest({
    required this.clientName,
    required this.redirectUris,
    required this.grantTypes,
    required this.responseTypes,
    required this.tokenEndpointAuthMethod,
    this.scope,
    this.clientUri,
    this.softwareId,
  });

  final String clientName;
  final List<Uri> redirectUris;
  final List<String> grantTypes;
  final List<String> responseTypes;
  final String tokenEndpointAuthMethod;
  final String? scope;
  final Uri? clientUri;
  final String? softwareId;
}

/// The application-owned result of registering an OAuth client.
final class AuthOAuthClientRegistration {
  const AuthOAuthClientRegistration({
    required this.clientId,
    required this.redirectUris,
    required this.grantTypes,
    required this.responseTypes,
    required this.tokenEndpointAuthMethod,
    this.clientSecret,
    this.clientName,
  });

  final String clientId;
  final String? clientSecret;
  final String? clientName;
  final List<Uri> redirectUris;
  final List<String> grantTypes;
  final List<String> responseTypes;
  final String tokenEndpointAuthMethod;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'client_id': clientId,
    if (clientSecret != null) 'client_secret': clientSecret,
    if (clientName != null) 'client_name': clientName,
    'redirect_uris': redirectUris
        .map((uri) => uri.toString())
        .toList(growable: false),
    'grant_types': grantTypes,
    'response_types': responseTypes,
    'token_endpoint_auth_method': tokenEndpointAuthMethod,
  };
}

/// Application-owned dynamic client registration boundary.
typedef AuthOAuthClientRegistrar<TContext> =
    FutureOr<AuthOAuthClientRegistration> Function(
      TContext context,
      AuthOAuthClientRegistrationRequest request,
    );

/// Publishes MCP protected-resource and OAuth authorization-server metadata.
final class McpAuthPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthClientOperationContributor,
        AuthRateLimitContributor {
  McpAuthPlugin({
    required AuthOAuthProtectedResourceMetadata protectedResource,
    required AuthOAuthAuthorizationServerMetadata authorizationServer,
    AuthOAuthClientRegistrar<TContext>? registerClient,
  }) : protectedResource = _validatedResource(protectedResource),
       authorizationServer = _validatedAuthorizationServer(authorizationServer),
       _registerClient = registerClient;

  final AuthOAuthProtectedResourceMetadata protectedResource;
  final AuthOAuthAuthorizationServerMetadata authorizationServer;
  final AuthOAuthClientRegistrar<TContext>? _registerClient;

  @override
  String get id => authMcpPluginId;

  @override
  AuthServerPluginDataContract get dataContract =>
      const AuthServerPluginDataContract.none();

  @override
  void configure(AuthServerPluginContext<TContext> context) {}

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints => [
    _metadataEndpoint(
      id: 'mcpAuth.protectedResourceMetadata',
      path: const AuthRoutePath('/.well-known/oauth-protected-resource'),
      payload: protectedResource.toJson(),
    ),
    _metadataEndpoint(
      id: 'mcpAuth.authorizationServerMetadata',
      path: const AuthRoutePath('/.well-known/oauth-authorization-server'),
      payload: authorizationServer.toJson(),
    ),
    if (_registerClient != null) _registrationEndpoint(),
  ];

  @override
  Iterable<AuthClientOperationDescriptor> get clientOperations => [
    const AuthClientOperationDescriptor(
      id: 'mcpAuth.protectedResourceMetadata',
      method: AuthOperationMethod.get,
      path: AuthRoutePath('/.well-known/oauth-protected-resource'),
      mount: AuthEndpointMount.root,
    ),
    const AuthClientOperationDescriptor(
      id: 'mcpAuth.authorizationServerMetadata',
      method: AuthOperationMethod.get,
      path: AuthRoutePath('/.well-known/oauth-authorization-server'),
      mount: AuthEndpointMount.root,
    ),
    if (_registerClient != null)
      const AuthClientOperationDescriptor(
        id: 'mcpAuth.registerClient',
        method: AuthOperationMethod.post,
        path: AuthRoutePath('/oauth/register'),
      ),
  ];

  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations => endpoints
      .map((endpoint) => endpoint.rateLimitOperation)
      .whereType<AuthRateLimitOperation>();

  AuthEndpointDescriptor<TContext> _metadataEndpoint({
    required String id,
    required AuthRoutePath path,
    required Map<String, dynamic> payload,
  }) => TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
    id: id,
    method: AuthOperationMethod.get,
    path: path,
    mount: AuthEndpointMount.root,
    semantics: const AuthOperationSemantics.readOnly(),
    requestCodec: _requestCodec,
    responseCodec: _responseCodec,
    authentication: AuthOperationAuthentication.none,
    originPolicy: AuthOperationOriginPolicy.none,
    csrfPolicy: AuthOperationCsrfPolicy.none,
    handler: (invocation, request) => payload,
  );

  AuthEndpointDescriptor<TContext> _registrationEndpoint() =>
      TypedAuthEndpointDescriptor<
        TContext,
        Map<String, dynamic>,
        Map<String, dynamic>
      >(
        id: 'mcpAuth.registerClient',
        method: AuthOperationMethod.post,
        path: const AuthRoutePath('/oauth/register'),
        semantics: const AuthOperationSemantics.mutation(
          persistence: AuthMutationPersistence.external(),
          replaySafety: AuthMutationReplaySafety.unguarded,
        ),
        requestCodec: AuthOperationCodec<Map<String, dynamic>>(
          decode: (value) => value,
          encode: (value) => value,
        ),
        responseCodec: AuthOperationCodec<Map<String, dynamic>>(
          decode: (value) => value,
          encode: (value) => value,
        ),
        authentication: AuthOperationAuthentication.none,
        originPolicy: AuthOperationOriginPolicy.none,
        csrfPolicy: AuthOperationCsrfPolicy.none,
        rateLimitOperation: const AuthRateLimitOperation(
          'mcp_auth',
          'register_client',
        ),
        handler: (invocation, input) async {
          final registrar = _registerClient;
          if (registrar == null) throw StateError('Registrar is unavailable.');
          final request = _parseRegistration(input);
          final registration = await registrar(invocation.context, request);
          return registration.toJson();
        },
      );

  static final AuthOperationCodec<Map<String, dynamic>> _requestCodec =
      AuthOperationCodec<Map<String, dynamic>>(
        decode: (value) => Map<String, dynamic>.from(value),
        encode: (value) => value,
      );

  static final AuthOperationCodec<Object?> _responseCodec =
      AuthOperationCodec<Object?>(
        decode: (value) => value,
        encode: (value) => value,
      );
}

AuthOAuthClientRegistrationRequest _parseRegistration(
  Map<String, dynamic> input,
) {
  final redirectUris = _requiredUris(input, 'redirect_uris');
  final grantTypes =
      _stringList(input, 'grant_types') ?? const ['authorization_code'];
  final responseTypes = _stringList(input, 'response_types') ?? const ['code'];
  final authMethod =
      _requiredString(input, 'token_endpoint_auth_method') ?? 'none';
  if (authMethod != 'none') {
    throw AuthFlowException('unsupported_token_endpoint_auth_method');
  }
  if (!grantTypes.contains('authorization_code') ||
      !responseTypes.contains('code')) {
    throw AuthFlowException('unsupported_client_configuration');
  }
  final clientUriValue = input['client_uri'];
  Uri? clientUri;
  if (clientUriValue != null) {
    clientUri = _parseAbsoluteUri(clientUriValue, 'client_uri');
  }
  return AuthOAuthClientRegistrationRequest(
    clientName: _requiredString(input, 'client_name') ?? 'MCP client',
    redirectUris: redirectUris,
    grantTypes: List<String>.unmodifiable(grantTypes),
    responseTypes: List<String>.unmodifiable(responseTypes),
    tokenEndpointAuthMethod: authMethod,
    scope: input['scope'] is String ? input['scope'] as String : null,
    clientUri: clientUri,
    softwareId: input['software_id'] is String
        ? input['software_id'] as String
        : null,
  );
}

String? _requiredString(Map<String, dynamic> input, String key) {
  final value = input[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw AuthFlowException('invalid_$key');
  }
  return value.trim();
}

List<Uri> _requiredUris(Map<String, dynamic> input, String key) {
  final value = input[key];
  if (value is! List || value.isEmpty) {
    throw AuthFlowException('invalid_$key');
  }
  return List<Uri>.unmodifiable(
    value.map((entry) => _parseRedirectUri(entry, key)),
  );
}

Uri _parseRedirectUri(Object? value, String key) {
  final uri = _parseAbsoluteUri(value, key);
  final isLocalHttp =
      uri.scheme == 'http' &&
      (uri.host == 'localhost' || uri.host == '127.0.0.1');
  if (uri.scheme != 'https' && !isLocalHttp) {
    throw AuthFlowException('invalid_$key');
  }
  return uri;
}

Uri _parseAbsoluteUri(Object? value, String key) {
  if (value is! String) throw AuthFlowException('invalid_$key');
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.isAbsolute ||
      uri.host.isEmpty ||
      uri.fragment.isNotEmpty) {
    throw AuthFlowException('invalid_$key');
  }
  return uri;
}

List<String>? _stringList(Map<String, dynamic> input, String key) {
  final value = input[key];
  if (value == null) return null;
  if (value is! List ||
      value.any((entry) => entry is! String || entry.trim().isEmpty)) {
    throw AuthFlowException('invalid_$key');
  }
  final result = value.cast<String>();
  if (result.isEmpty) throw AuthFlowException('invalid_$key');
  return result;
}

AuthOAuthProtectedResourceMetadata _validatedResource(
  AuthOAuthProtectedResourceMetadata metadata,
) {
  _requireAbsoluteUri(metadata.resource, 'resource');
  if (metadata.authorizationServers.isEmpty) {
    throw ArgumentError('MCP metadata requires an authorization server');
  }
  for (final server in metadata.authorizationServers) {
    _requireAbsoluteUri(server, 'authorization server');
  }
  return metadata;
}

AuthOAuthAuthorizationServerMetadata _validatedAuthorizationServer(
  AuthOAuthAuthorizationServerMetadata metadata,
) {
  _requireAbsoluteUri(metadata.issuer, 'issuer');
  _requireAbsoluteUri(metadata.authorizationEndpoint, 'authorization endpoint');
  _requireAbsoluteUri(metadata.tokenEndpoint, 'token endpoint');
  return metadata;
}

void _requireAbsoluteUri(Uri value, String name) {
  if (!value.isAbsolute || value.host.isEmpty || value.fragment.isNotEmpty) {
    throw ArgumentError('$name must be an absolute URI without a fragment');
  }
}
