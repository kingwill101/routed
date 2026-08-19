import 'feature.dart';

const String authMcpFeatureId = 'mcp_auth';

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

/// Publishes MCP protected-resource and OAuth authorization-server metadata.
final class McpAuthFeature<TContext>
    implements AuthFeature<TContext>, AuthEndpointContributor<TContext> {
  McpAuthFeature({
    required AuthOAuthProtectedResourceMetadata protectedResource,
    required AuthOAuthAuthorizationServerMetadata authorizationServer,
  }) : protectedResource = _validatedResource(protectedResource),
       authorizationServer = _validatedAuthorizationServer(authorizationServer);

  final AuthOAuthProtectedResourceMetadata protectedResource;
  final AuthOAuthAuthorizationServerMetadata authorizationServer;

  @override
  String get id => authMcpFeatureId;

  @override
  void configure(AuthFeatureContext<TContext> context) {}

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints => [
    _metadataEndpoint(
      id: 'mcpAuth.protectedResourceMetadata',
      path: '/.well-known/oauth-protected-resource',
      payload: protectedResource.toJson(),
    ),
    _metadataEndpoint(
      id: 'mcpAuth.authorizationServerMetadata',
      path: '/.well-known/oauth-authorization-server',
      payload: authorizationServer.toJson(),
    ),
  ];

  AuthEndpointDescriptor<TContext> _metadataEndpoint({
    required String id,
    required String path,
    required Map<String, dynamic> payload,
  }) => TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
    id: id,
    method: AuthOperationMethod.get,
    path: path,
    requestCodec: _requestCodec,
    responseCodec: _responseCodec,
    authentication: AuthOperationAuthentication.none,
    originPolicy: AuthOperationOriginPolicy.none,
    csrfPolicy: AuthOperationCsrfPolicy.none,
    handler: (invocation, request) => payload,
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
