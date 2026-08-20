import 'package:routed_openapi/server_auth.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('managed SCIM connections publish session and atomicity contracts', () {
    final runtime = AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: const <AuthProvider>[],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        plugins: <AuthServerPlugin<Object>>[
          AuthScimConnectionPlugin<Object>(
            store: InMemoryAuthScimConnectionStore(),
            authorize: (_) => AuthScimConnectionManagementPrincipal(
              tenantId: 'tenant-a',
              organizationId: 'organization-a',
              subjectId: 'user-a',
            ),
          ),
        ],
      ),
    );

    final spec = runtime.registry.toOpenApi31(
      info: const OpenApiInfo(
        title: 'Managed SCIM connections',
        version: '1.0.0',
      ),
    );

    expect(
      spec.paths.keys,
      containsAll(<String>[
        '/auth/scim/connections',
        '/auth/scim/connections/create',
        '/auth/scim/connections/update',
        '/auth/scim/connections/disable',
        '/auth/scim/connections/credentials',
        '/auth/scim/connections/credentials/issue',
        '/auth/scim/connections/credentials/rotate',
        '/auth/scim/connections/credentials/revoke',
      ]),
    );
    final create = spec.paths['/auth/scim/connections/create']!.post!;
    final rotate =
        spec.paths['/auth/scim/connections/credentials/rotate']!.post!;
    final list = spec.paths['/auth/scim/connections']!.get!;

    for (final operation in <OpenApiOperation>[create, rotate, list]) {
      expect(operation.security, const <Map<String, List<String>>>[
        <String, List<String>>{
          AuthPluginOpenApiGenerator.sessionCookieSecurityScheme: <String>[],
        },
        <String, List<String>>{
          AuthPluginOpenApiGenerator.bearerSecurityScheme: <String>[],
        },
      ]);
    }
    expect(
      create.parameters.map((value) => value.name),
      containsAll(<String>['Origin', 'x-csrf-token']),
    );
    expect(
      create.extensions[AuthPluginOpenApiGenerator.operationSemanticsExtension],
      <String, Object?>{
        'effect': 'mutation',
        'persistence': 'durable',
        'atomicity': 'atomic',
        'replaySafety': 'idempotent',
        'persistenceReference': <String, Object?>{
          'schemaId': 'scim.connections',
          'atomicOperationId': 'createConnection',
        },
      },
    );
    expect(
      rotate.extensions[AuthPluginOpenApiGenerator.operationSemanticsExtension],
      containsPair('replaySafety', 'idempotent'),
    );
    expect(list.requestBody, isNull);
    expect(
      list.parameters.map((value) => value.name),
      contains('organizationId'),
    );
    expect(runtime.registry.clientOperations, hasLength(8));
    expect(spec.toJson().toString(), isNot(contains('secretDigest')));
  });
}
