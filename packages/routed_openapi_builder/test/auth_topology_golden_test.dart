import 'dart:convert';
import 'dart:io';

import 'package:routed_openapi/server_auth.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('auth OpenAPI generated-client contract', () {
    test('matches the frozen opt-in topology golden', () {
      final spec = _authSpec();
      final rendered = spec.toJsonString(pretty: true);
      final goldenFile = _goldenFile();
      if (Platform.environment['UPDATE_GOLDENS'] == '1') {
        goldenFile.writeAsStringSync('$rendered\n');
      }
      final golden = goldenFile.readAsStringSync();

      expect(rendered, golden.trimRight());
    });

    test('emits client-safe operation IDs and resolvable schemas', () {
      final spec = _authSpec();
      final components = spec.components!;
      final operationIds = <String>{};

      for (final pathItem in spec.paths.values) {
        for (final method in <String>['get', 'post']) {
          final operation = pathItem.operationFor(method);
          if (operation == null) continue;

          final operationId = operation.operationId;
          expect(operationId, isNotNull);
          expect(operationId, matches(RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$')));
          expect(operationIds.add(operationId!), isTrue);
          expect(operation.responses, contains('200'));

          for (final response in operation.responses.values) {
            _expectSchemaReferencesResolve(response.content, components);
          }
          _expectSchemaReferencesResolve(
            operation.requestBody?.content,
            components,
          );

          for (final requirement in operation.security ?? const []) {
            for (final scheme in requirement.keys) {
              expect(components.securitySchemes, contains(scheme));
            }
          }
        }
      }

      final roundTripped = OpenApiSpec.fromJson(
        jsonDecode(spec.toJsonString()) as Map<String, Object?>,
      );
      expect(roundTripped.toJson(), spec.toJson());
    });

    test('omits unselected plugin operations from generated output', () {
      final registry = _registry(<AuthServerPlugin<Object>>[
        AnonymousPlugin<Object>(),
      ]);
      final spec = registry.toOpenApi31(info: _info);

      expect(spec.paths.length, registry.endpoints.length);
      expect(spec.paths.keys, everyElement(isNot(contains('api-keys'))));
      expect(spec.tags.map((tag) => tag.name), isNot(contains('api_key')));
      expect(spec.tags.map((tag) => tag.name), isNot(contains('two_factor')));
    });

    test('keeps cookie and bearer session alternatives selectable', () {
      final registry = _registry(<AuthServerPlugin<Object>>[
        AnonymousPlugin<Object>(),
      ]);
      final cookieSpec = registry.toOpenApi31(
        info: _info,
        config: const AuthPluginOpenApiConfig(
          sessionSecurity: AuthOpenApiSessionSecurity.cookie,
        ),
      );
      final bearerSpec = registry.toOpenApi31(
        info: _info,
        config: const AuthPluginOpenApiConfig(
          sessionSecurity: AuthOpenApiSessionSecurity.bearer,
        ),
      );

      expect(
        cookieSpec.paths['/auth/delete-anonymous-user']!.post!.security,
        const <Map<String, List<String>>>[
          <String, List<String>>{
            AuthPluginOpenApiGenerator.sessionCookieSecurityScheme: <String>[],
          },
        ],
      );
      expect(
        bearerSpec.paths['/auth/delete-anonymous-user']!.post!.security,
        const <Map<String, List<String>>>[
          <String, List<String>>{
            AuthPluginOpenApiGenerator.bearerSecurityScheme: <String>[],
          },
        ],
      );
    });

    test('has no public auth metadata gaps', () {
      final registry = _registry(<AuthServerPlugin<Object>>[
        AnonymousPlugin<Object>(),
        AuthApiKeyPlugin<Object>(
          store: InMemoryAuthApiKeyStore(),
          sessionExchangeEnabled: true,
        ),
        _twoFactorPlugin(),
      ]);
      final spec = registry.toOpenApi31(info: _info);
      final gaps = <String>[];

      final apiKeyEndpointIds = registry.publicEndpoints
          .where(
            (endpoint) =>
                registry.pluginIdForEndpoint(endpoint.id) == authApiKeyPluginId,
          )
          .map((endpoint) => endpoint.id)
          .toList(growable: false);
      expect(apiKeyEndpointIds, isNotEmpty);
      final exchange = spec.paths['/auth/api-keys/exchange']?.post;
      final hasApiKeySecurity = exchange?.security?.any(
        (alternative) => alternative.containsKey(
          AuthPluginOpenApiGenerator.apiKeySecurityScheme,
        ),
      );
      if (hasApiKeySecurity != true) {
        gaps.add('api-key transport security is not in endpoint metadata');
      }

      final responseSchemas = spec.components!.schemas.entries
          .where((entry) => entry.key.endsWith('Response'))
          .map((entry) => entry.value)
          .toList(growable: false);
      if (responseSchemas.any((schema) => schema.isEmpty)) {
        gaps.add('typed response schemas are empty for built-in descriptors');
      }

      final hasSessionOrJwtData = responseSchemas.any((schema) {
        final properties = schema['properties'];
        return properties is Map &&
            const <String>{
              'user',
              'expires',
              'strategy',
              'token',
            }.any(properties.containsKey);
      });
      if (!hasSessionOrJwtData) {
        gaps.add(
          'optional session/JWT response data is not in endpoint schemas',
        );
      }

      final hasGenericPublicErrors = spec.paths.values.every((pathItem) {
        for (final method in <String>['get', 'post']) {
          final operation = pathItem.operationFor(method);
          if (operation == null) continue;
          for (final status in <String>['400', '401']) {
            final response = operation.responses[status];
            final reference =
                response?.content?['application/json']?.schema?[r'$ref'];
            if (reference != '#/components/schemas/AuthError') return false;
          }
        }
        return true;
      });
      if (!hasGenericPublicErrors ||
          spec.components!.schemas['AuthError'] == null) {
        gaps.add('generic error response schema is not advertised');
      }

      if (registry.find(authTwoFactorPluginId) != null &&
          registry.publicEndpoints.every(
            (endpoint) =>
                registry.pluginIdForEndpoint(endpoint.id) !=
                authTwoFactorPluginId,
          )) {
        gaps.add('two-factor alternatives have no public endpoint descriptors');
      }

      expect(gaps, isEmpty);

      final schemas = spec.components!.schemas;
      final issuedKeyProperties =
          schemas['AuthApiKeyCreateResponse']!['properties']! as Map;
      expect(issuedKeyProperties['apiKey'], containsPair('readOnly', true));
      final challengeProperties =
          schemas['AuthTwoFactorChallenge']!['properties']! as Map;
      expect(
        challengeProperties['challengeToken'],
        containsPair('readOnly', true),
      );
    });
  });
}

const _info = OpenApiInfo(title: 'Auth API', version: '1.0.0');

File _goldenFile() {
  final packageRelative = File('test/goldens/auth_topology.openapi.json');
  if (packageRelative.existsSync()) return packageRelative;
  return File(
    'packages/routed_openapi_builder/test/goldens/auth_topology.openapi.json',
  );
}

OpenApiSpec _authSpec() => _registry(<AuthServerPlugin<Object>>[
  AnonymousPlugin<Object>(),
  AuthApiKeyPlugin<Object>(
    store: InMemoryAuthApiKeyStore(),
    sessionExchangeEnabled: true,
  ),
  _twoFactorPlugin(),
]).toOpenApi31(info: _info);

AuthServerPluginRegistry<Object> _registry(
  Iterable<AuthServerPlugin<Object>> plugins,
) {
  final store = InMemoryAuthStore();
  final registry = AuthServerPluginRegistry<Object>(
    store: store,
    authenticationMethods: AuthAuthenticationMethodService(store: store),
  );
  for (final plugin in plugins) {
    registry.register(plugin);
  }
  registry.freeze();
  return registry;
}

TwoFactorPlugin<Object> _twoFactorPlugin() {
  return TwoFactorPlugin<Object>(
    backend: InMemoryAuthTwoFactorBackend(),
    secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
  );
}

void _expectSchemaReferencesResolve(
  Map<String, OpenApiMediaType>? content,
  OpenApiComponents components,
) {
  if (content == null) return;
  for (final mediaType in content.values) {
    final reference = mediaType.schema?[r'$ref'];
    if (reference is! String) continue;

    const prefix = '#/components/schemas/';
    expect(reference, startsWith(prefix));
    expect(components.schemas, contains(reference.substring(prefix.length)));
  }
}
