import 'package:routed_openapi/server_auth.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('SCIM publishes typed bearer and HTTP response contracts', () {
    final runtime = AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: const <AuthProvider>[],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        plugins: <AuthServerPlugin<Object>>[
          ScimPlugin<Object>(
            store: const _NoopScimStore(),
            tokenResolver: const _NoopResolver(),
          ),
        ],
      ),
    );

    final spec = runtime.registry.toOpenApi31(
      info: const OpenApiInfo(title: 'SCIM', version: '1.0.0'),
    );

    expect(
      spec.paths.keys,
      containsAll(<String>[
        '/auth/scim/v2/ServiceProviderConfig',
        '/auth/scim/v2/ResourceTypes',
        '/auth/scim/v2/Schemas',
        '/auth/scim/v2/Users',
        '/auth/scim/v2/Users/{id}',
        '/auth/scim/v2/Groups',
        '/auth/scim/v2/Groups/{id}',
      ]),
    );
    final users = spec.paths['/auth/scim/v2/Users']!;
    final byId = spec.paths['/auth/scim/v2/Users/{id}']!;
    final groups = spec.paths['/auth/scim/v2/Groups']!;
    final groupById = spec.paths['/auth/scim/v2/Groups/{id}']!;
    expect(users.get, isNotNull);
    expect(users.post, isNotNull);
    expect(byId.get, isNotNull);
    expect(byId.put, isNotNull);
    expect(byId.patch, isNotNull);
    expect(byId.delete, isNotNull);
    expect(groups.get, isNotNull);
    expect(groups.post, isNotNull);
    expect(groupById.get, isNotNull);
    expect(groupById.put, isNotNull);
    expect(groupById.patch, isNotNull);
    expect(groupById.delete, isNotNull);

    for (final operation in <OpenApiOperation>[
      users.get!,
      users.post!,
      byId.get!,
      byId.put!,
      byId.patch!,
      byId.delete!,
      groups.get!,
      groups.post!,
      groupById.get!,
      groupById.put!,
      groupById.patch!,
      groupById.delete!,
    ]) {
      expect(operation.security, <Map<String, List<String>>>[
        <String, List<String>>{
          AuthPluginOpenApiGenerator.bearerSecurityScheme: <String>[],
        },
      ]);
      expect(operation.responses['401']!.content, contains(authScimMediaType));
      expect(
        operation.responses['401']!.content![authScimMediaType]!.schema,
        authScimErrorJsonSchema,
      );
    }

    expect(users.post!.responses, contains('201'));
    expect(users.post!.responses, isNot(contains('200')));
    expect(users.post!.requestBody!.content, contains(authScimMediaType));
    expect(byId.put!.requestBody!.content, contains(authScimMediaType));
    expect(byId.patch!.requestBody!.content, contains(authScimMediaType));
    expect(byId.delete!.requestBody, isNull);
    expect(byId.delete!.responses['204']!.content, isNull);
    expect(groups.post!.responses, contains('201'));
    expect(groups.post!.requestBody!.content, contains(authScimMediaType));
    expect(groupById.put!.requestBody!.content, contains(authScimMediaType));
    expect(groupById.patch!.requestBody!.content, contains(authScimMediaType));
    expect(groupById.delete!.responses['204']!.content, isNull);
    expect(
      byId.get!.parameters.singleWhere((value) => value.name == 'id').location,
      'path',
    );
    expect(
      spec
          .components!
          .securitySchemes[AuthPluginOpenApiGenerator.bearerSecurityScheme]!
          .description,
      contains('selected auth plugin'),
    );

    final createSchema =
        spec.components!.schemas['AuthScimUsersCreateRequest']!;
    expect(createSchema['additionalProperties'], isFalse);
    final properties = createSchema['properties']! as Map<String, Object?>;
    expect(
      (properties['name']! as Map<String, Object?>)['additionalProperties'],
      isFalse,
    );
    expect(
      ((properties['emails']! as Map<String, Object?>)['items']!
          as Map<String, Object?>)['additionalProperties'],
      isFalse,
    );
    final groupCreateSchema =
        spec.components!.schemas['AuthScimGroupsCreateRequest']!;
    expect(groupCreateSchema['additionalProperties'], isFalse);
    final groupProperties =
        groupCreateSchema['properties']! as Map<String, Object?>;
    expect(
      ((groupProperties['members']! as Map<String, Object?>)['items']!
          as Map<String, Object?>)['additionalProperties'],
      isFalse,
    );
    expect(runtime.registry.clientOperations, isEmpty);
  });
}

final class _NoopResolver implements AuthScimBearerTokenResolver<Object> {
  const _NoopResolver();

  @override
  AuthScimConnectionIdentity? resolve(
    AuthScimBearerTokenRequest<Object> request,
  ) => null;
}

final class _NoopScimStore implements AuthScimProvisioningStore {
  const _NoopScimStore();

  @override
  AuthScimUserPage listUsers(
    AuthScimProvisioningContext context,
    AuthScimListUsersQuery query,
  ) => AuthScimUserPage(resources: const <AuthScimUser>[], totalResults: 0);

  @override
  AuthScimUser? findUser(
    AuthScimProvisioningContext context,
    String resourceId,
  ) => null;

  @override
  AuthScimUser createUser(
    AuthScimProvisioningContext context,
    AuthScimUserData user,
  ) => throw const AuthScimConflictException();

  @override
  AuthScimUser? replaceUser(
    AuthScimProvisioningContext context,
    String resourceId,
    AuthScimUserData user,
  ) => null;

  @override
  AuthScimUser? patchUser(
    AuthScimProvisioningContext context,
    String resourceId,
    AuthScimPatchDocument patch,
  ) => null;

  @override
  AuthScimUser? tombstoneUser(
    AuthScimProvisioningContext context,
    String resourceId,
  ) => null;

  @override
  AuthScimGroupPage listGroups(
    AuthScimProvisioningContext context,
    AuthScimListGroupsQuery query,
  ) => AuthScimGroupPage(resources: const <AuthScimGroup>[], totalResults: 0);

  @override
  AuthScimGroup? findGroup(
    AuthScimProvisioningContext context,
    String resourceId,
  ) => null;

  @override
  AuthScimGroup createGroup(
    AuthScimProvisioningContext context,
    AuthScimGroupData group,
  ) => throw const AuthScimConflictException();

  @override
  AuthScimGroup? replaceGroup(
    AuthScimProvisioningContext context,
    String resourceId,
    AuthScimGroupData group,
  ) => null;

  @override
  AuthScimGroup? patchGroup(
    AuthScimProvisioningContext context,
    String resourceId,
    AuthScimGroupPatchDocument patch,
  ) => null;

  @override
  AuthScimGroup? mutateGroupMembership(
    AuthScimProvisioningContext context,
    AuthScimGroupMembershipMutation mutation,
  ) => null;

  @override
  AuthScimGroup? tombstoneGroup(
    AuthScimProvisioningContext context,
    String resourceId,
  ) => null;
}
