import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

void main() {
  test('Routed mounts every SCIM verb and preserves SCIM responses', () async {
    final authStore = InMemoryAuthStore();
    final plugin = ScimPlugin<EngineContext>(
      store: _EmptyScimStore(),
      tokenResolver: const _RouteTokenResolver(),
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: authStore,
        storeMode: AuthStoreMode.ephemeral,
        providers: const <AuthProvider>[],
        plugins: <AuthServerPlugin<EngineContext>>[plugin],
      ),
    );
    final engine = testEngine();
    AuthRoutes(manager).register(engine.defaultRouter);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);
    const headers = <String, List<String>>{
      'authorization': <String>['Bearer route-token'],
    };

    final discovery = await client.get(
      '/auth/scim/v2/ServiceProviderConfig',
      headers: headers,
    );
    discovery.assertStatus(200);
    expect(discovery.headerValue('content-type'), contains(authScimMediaType));

    final listed = await client.get(
      '/auth/scim/v2/Users?count=1',
      headers: headers,
    );
    listed.assertStatus(200);
    expect(listed.json()['totalResults'], 0);

    final created = await client.postJson(
      '/auth/scim/v2/Users',
      const <String, Object?>{},
      headers: headers,
    );
    created.assertStatus(400);
    expect(created.json()['schemas'], <String>[authScimErrorSchema]);

    final malformed = await client.post(
      '/auth/scim/v2/Users',
      '{not-json',
      headers: <String, List<String>>{
        ...headers,
        'content-type': const <String>[authScimMediaType],
      },
    );
    malformed.assertStatus(400);
    expect(malformed.headerValue('content-type'), contains(authScimMediaType));
    expect(malformed.json()['schemas'], <String>[authScimErrorSchema]);

    final replaced = await client.putJson(
      '/auth/scim/v2/Users/missing',
      _userInput,
      headers: headers,
    );
    replaced.assertStatus(404);

    final patched = await client.patchJson(
      '/auth/scim/v2/Users/missing',
      const <String, Object?>{
        'schemas': <String>[authScimPatchOperationSchema],
        'Operations': <Object?>[
          <String, Object?>{
            'op': 'replace',
            'path': 'displayName',
            'value': 'Missing',
          },
        ],
      },
      headers: headers,
    );
    patched.assertStatus(404);

    final deleted = await client.delete(
      '/auth/scim/v2/Users/missing',
      headers: headers,
    );
    deleted.assertStatus(404);

    final groups = await client.get(
      '/auth/scim/v2/Groups?count=1',
      headers: headers,
    );
    groups.assertStatus(200);
    expect(groups.json()['totalResults'], 0);

    final groupCreated = await client.postJson(
      '/auth/scim/v2/Groups',
      const <String, Object?>{},
      headers: headers,
    );
    groupCreated.assertStatus(400);

    final groupReplaced = await client.putJson(
      '/auth/scim/v2/Groups/missing',
      const <String, Object?>{
        'schemas': <String>[authScimGroupSchema],
        'displayName': 'Missing',
      },
      headers: headers,
    );
    groupReplaced.assertStatus(404);

    final groupPatched = await client.patchJson(
      '/auth/scim/v2/Groups/missing',
      const <String, Object?>{
        'schemas': <String>[authScimPatchOperationSchema],
        'Operations': <Object?>[
          <String, Object?>{
            'op': 'replace',
            'path': 'displayName',
            'value': 'Missing',
          },
        ],
      },
      headers: headers,
    );
    groupPatched.assertStatus(404);

    final groupDeleted = await client.delete(
      '/auth/scim/v2/Groups/missing',
      headers: headers,
    );
    groupDeleted.assertStatus(404);

    for (final response in <TestResponse>[
      discovery,
      listed,
      created,
      malformed,
      replaced,
      patched,
      deleted,
      groups,
      groupCreated,
      groupReplaced,
      groupPatched,
      groupDeleted,
    ]) {
      expect(response.headerValue('content-type'), contains(authScimMediaType));
    }
  });

  test('Routed does not turn SCIM bearer tokens into user sessions', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: const <AuthProvider>[],
        plugins: <AuthServerPlugin<EngineContext>>[
          ScimPlugin<EngineContext>(
            store: _EmptyScimStore(),
            tokenResolver: const _RouteTokenResolver(),
          ),
        ],
      ),
    );
    final engine = testEngine();
    AuthRoutes(manager).register(engine.defaultRouter);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final response = await client.get(
      '/auth/scim/v2/Users',
      headers: const <String, List<String>>{
        'authorization': <String>['Bearer route-token'],
      },
    );

    response.assertStatus(200);
    expect(
      response.headers.keys.map((name) => name.toLowerCase()),
      isNot(contains('set-cookie')),
    );
  });

  test('Routed preserves an atomic SCIM tombstone response', () async {
    final store = _EmptyScimStore(
      resource: AuthScimUser(
        connectionId: 'connection-route',
        tenantId: 'tenant-route',
        organizationId: 'organization-route',
        provisioningDomainId: 'domain-route',
        id: 'directory-user',
        data: AuthScimUserData(userName: 'directory@example.test'),
        meta: AuthScimResourceMeta(
          created: DateTime.utc(2026),
          lastModified: DateTime.utc(2026),
        ),
        state: AuthScimDirectoryUserState.active,
      ),
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: const <AuthProvider>[],
        plugins: <AuthServerPlugin<EngineContext>>[
          ScimPlugin<EngineContext>(
            store: store,
            tokenResolver: const _RouteTokenResolver(),
          ),
        ],
      ),
    );
    final engine = testEngine();
    AuthRoutes(manager).register(engine.defaultRouter);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);
    const headers = <String, List<String>>{
      'authorization': <String>['Bearer route-token'],
    };

    final deleted = await client.delete(
      '/auth/scim/v2/Users/directory-user',
      headers: headers,
    );
    deleted.assertStatus(204);
    expect(deleted.body, isEmpty);
    expect(
      deleted.headers.keys.map((name) => name.toLowerCase()),
      isNot(contains('content-type')),
    );
    expect(store.resource!.state, AuthScimDirectoryUserState.tombstoned);

    final missing = await client.get(
      '/auth/scim/v2/Users/directory-user',
      headers: headers,
    );
    missing.assertStatus(404);
  });
}

const Map<String, Object?> _userInput = <String, Object?>{
  'schemas': <String>[authScimUserSchema],
  'userName': 'missing@example.test',
  'active': true,
};

final class _RouteTokenResolver
    implements AuthScimBearerTokenResolver<EngineContext> {
  const _RouteTokenResolver();

  @override
  AuthScimConnectionIdentity? resolve(
    AuthScimBearerTokenRequest<EngineContext> request,
  ) => request.token == 'route-token'
      ? AuthScimConnectionIdentity(
          connectionId: 'connection-route',
          credentialId: 'credential-route',
          tenantId: 'tenant-route',
          organizationId: 'organization-route',
          provisioningDomainId: 'domain-route',
          subjectId: 'route-test',
          scopes: const <AuthScimScope>[
            AuthScimScope.usersWrite,
            AuthScimScope.groupsWrite,
          ],
          expiresAt: DateTime.utc(2030),
        )
      : null;
}

final class _EmptyScimStore implements AuthScimProvisioningStore {
  _EmptyScimStore({this.resource});

  AuthScimUser? resource;

  @override
  AuthScimUserPage listUsers(
    AuthScimProvisioningContext context,
    AuthScimListUsersQuery query,
  ) {
    final current = _findLive(context);
    return AuthScimUserPage(
      resources: current == null
          ? const <AuthScimUser>[]
          : <AuthScimUser>[current],
      totalResults: current == null ? 0 : 1,
    );
  }

  @override
  AuthScimUser? findUser(
    AuthScimProvisioningContext context,
    String resourceId,
  ) {
    final current = _findLive(context);
    return current?.id == resourceId ? current : null;
  }

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
  ) {
    final current = findUser(context, resourceId);
    if (current == null) return null;
    final deletedAt = current.meta.lastModified.add(const Duration(seconds: 1));
    return resource = AuthScimUser(
      connectionId: current.connectionId,
      tenantId: current.tenantId,
      organizationId: current.organizationId,
      provisioningDomainId: current.provisioningDomainId,
      id: current.id,
      data: AuthScimUserData(
        userName: current.data.userName,
        externalId: current.data.externalId,
        active: false,
        name: current.data.name,
        displayName: current.data.displayName,
        emails: current.data.emails,
      ),
      meta: AuthScimResourceMeta(
        created: current.meta.created,
        lastModified: deletedAt,
      ),
      state: AuthScimDirectoryUserState.tombstoned,
      tombstonedAt: deletedAt,
    );
  }

  AuthScimUser? _findLive(AuthScimProvisioningContext context) {
    final current = resource;
    if (current == null ||
        current.state == AuthScimDirectoryUserState.tombstoned ||
        current.connectionId != context.connectionId ||
        current.tenantId != context.tenantId ||
        current.organizationId != context.organizationId ||
        current.provisioningDomainId != context.provisioningDomainId) {
      return null;
    }
    return current;
  }

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
