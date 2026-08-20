import 'dart:async';
import 'dart:convert';

import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'SCIM conforms without installing an unrelated auth client plugin',
    () async {
      final harness = _Harness();
      final exceptions = <String, String>{
        for (final endpoint in harness.runtime.registry.endpoints)
          endpoint.id:
              'SCIM is consumed directly by an external identity provider.',
      };
      final suite = AuthPluginConformanceSuite<Object>.fromRuntime(
        harness.runtime,
        publicEndpointClientExceptions: exceptions,
      );

      for (final conformanceCase in suite.cases) {
        final result = await conformanceCase.run();
        expect(result.isPassed, isTrue, reason: conformanceCase.id);
      }
      expect(harness.runtime.registry.clientOperations, isEmpty);
    },
  );

  group('ScimPlugin authorization', () {
    test('requires bearer authentication and explicit scopes', () async {
      final harness = _Harness();

      final missing = await harness.request(
        'GET',
        '/scim/v2/ServiceProviderConfig',
      );
      expect(missing.statusCode, 401);
      expect(missing.headers['Content-Type'], authScimMediaType);
      expect(_json(missing)['detail'], 'Unauthorized.');

      final forbidden = await harness.request(
        'GET',
        '/scim/v2/ServiceProviderConfig',
        token: 'no-access',
      );
      expect(forbidden.statusCode, 403);

      final allowed = await harness.request(
        'GET',
        '/scim/v2/ServiceProviderConfig',
        token: 'read-a',
      );
      expect(allowed.statusCode, 200);
      expect(_json(allowed)['patch'], containsPair('supported', true));

      final readOnlyMutation = await harness.request(
        'POST',
        '/scim/v2/Users',
        token: 'read-a',
        body: const <String, Object?>{},
      );
      expect(readOnlyMutation.statusCode, 403);
    });

    test('never exposes rejected bearer tokens or verifier failures', () async {
      const secret = 'secret-bearer-value';
      final failures = <AuthScimInternalFailure>[];
      final harness = _Harness(
        resolver: _Resolver((request) {
          throw StateError('verifier rejected ${request.token}');
        }),
        reportFailure: failures.add,
      );

      final response = await harness.request(
        'GET',
        '/scim/v2/Users',
        token: secret,
      );

      expect(response.statusCode, 500);
      expect(response.body, isNot(contains(secret)));
      expect(response.body, isNot(contains('verifier')));
      expect(failures, hasLength(1));
      expect(failures.single.error.toString(), isNot(contains(secret)));
      expect(failures.single.error.toString(), isNot(contains('verifier')));
    });

    test('rejects expired and revoked credential resolutions', () async {
      final expired = _Harness(
        resolver: _Resolver(
          (_) => AuthScimConnectionIdentity(
            connectionId: 'connection-a',
            credentialId: 'expired-credential',
            tenantId: 'tenant-a',
            organizationId: 'org-a',
            provisioningDomainId: 'domain-a',
            subjectId: 'provisioner',
            scopes: const <AuthScimScope>[AuthScimScope.usersRead],
            expiresAt: DateTime.utc(2020),
          ),
        ),
      );
      final expiredResponse = await expired.request(
        'GET',
        '/scim/v2/Users',
        token: 'expired',
      );
      expect(expiredResponse.statusCode, 401);

      final revoked = _Harness(resolver: _Resolver((_) => null));
      final revokedResponse = await revoked.request(
        'GET',
        '/scim/v2/Users',
        token: 'revoked',
      );
      expect(revokedResponse.statusCode, 401);
    });
  });

  group('ScimPlugin tenant isolation and bounds', () {
    test(
      'isolates resources by connection, tenant, and provisioning domain',
      () async {
        final harness = _Harness();
        await harness.seed(
          connectionId: 'connection-a',
          tenantId: 'tenant-a',
          organizationId: 'org-a',
          provisioningDomainId: 'domain-a',
          resourceId: 'resource-a',
          userName: 'a@example.test',
        );
        await harness.seed(
          connectionId: 'connection-b',
          tenantId: 'tenant-b',
          organizationId: 'org-b',
          provisioningDomainId: 'domain-b',
          resourceId: 'resource-b',
          userName: 'b@example.test',
        );

        final hidden = await harness.request(
          'GET',
          '/scim/v2/Users/resource-b',
          token: 'read-a',
        );
        expect(hidden.statusCode, 404);

        final visible = await harness.request(
          'GET',
          '/scim/v2/Users/resource-b',
          token: 'read-b',
        );
        expect(visible.statusCode, 200);
        expect(_json(visible)['userName'], 'b@example.test');

        final wrongConnection = await harness.request(
          'GET',
          '/scim/v2/Users/resource-a',
          token: 'read-a-other-connection',
        );
        expect(wrongConnection.statusCode, 404);
      },
    );

    test(
      'fails generically if a store returns another tenant resource',
      () async {
        final harness = _Harness();
        await harness.seed(
          connectionId: 'connection-b',
          tenantId: 'tenant-b',
          organizationId: 'org-b',
          provisioningDomainId: 'domain-b',
          resourceId: 'resource-b',
          userName: 'private-b@example.test',
        );
        harness.store.crossTenantListLeak = true;

        final response = await harness.request(
          'GET',
          '/scim/v2/Users',
          token: 'read-a',
        );

        expect(response.statusCode, 500);
        expect(response.body, isNot(contains('private-b@example.test')));
        expect(response.body, isNot(contains('tenant-b')));
        expect(_json(response)['detail'], 'SCIM request failed.');
      },
    );

    test(
      'caps count, bounds startIndex, and parses only supported filters',
      () async {
        final harness = _Harness(
          options: AuthScimOptions(
            defaultPageSize: 1,
            maximumPageSize: 2,
            maximumStartIndex: 10,
          ),
        );
        for (var index = 0; index < 5; index++) {
          await harness.seed(
            connectionId: 'connection-a',
            tenantId: 'tenant-a',
            organizationId: 'org-a',
            provisioningDomainId: 'domain-a',
            resourceId: 'resource-$index',
            userName: 'user-$index@example.test',
          );
        }

        final capped = await harness.request(
          'GET',
          '/scim/v2/Users?count=999',
          token: 'read-a',
        );
        expect(capped.statusCode, 200);
        expect((_json(capped)['Resources'] as List), hasLength(2));
        expect(_json(capped)['totalResults'], 5);
        expect(harness.store.lastQuery!.count, 2);

        final filtered = await harness.request(
          'GET',
          '/scim/v2/Users?filter=${Uri.encodeQueryComponent('userName eq "user-3@example.test"')}',
          token: 'read-a',
        );
        expect(filtered.statusCode, 200);
        expect((_json(filtered)['Resources'] as List), hasLength(1));

        final unsupported = await harness.request(
          'GET',
          '/scim/v2/Users?filter=${Uri.encodeQueryComponent('displayName co "user"')}',
          token: 'read-a',
        );
        expect(unsupported.statusCode, 400);

        final excessiveStart = await harness.request(
          'GET',
          '/scim/v2/Users?startIndex=11',
          token: 'read-a',
        );
        expect(excessiveStart.statusCode, 400);
      },
    );
  });

  group('ScimPlugin user lifecycle', () {
    test(
      'creates, replaces, patches, and deletes through typed contracts',
      () async {
        final harness = _Harness(
          options: AuthScimOptions(maximumPatchOperations: 2),
        );
        final created = await harness.request(
          'POST',
          '/scim/v2/Users',
          token: 'write-a',
          body: _userInput('new@example.test'),
        );
        expect(created.statusCode, 201);
        expect(created.headers['Content-Type'], authScimMediaType);
        expect(created.headers, contains('Location'));
        final resourceId = _json(created)['id']! as String;
        expect(
          await harness.authStore.users.findByEmail('new@example.test'),
          isNull,
          reason: 'SCIM provisioning must not create a sign-in identity',
        );

        final replaced = await harness.request(
          'PUT',
          '/scim/v2/Users/$resourceId',
          token: 'write-a',
          body: <String, Object?>{
            ..._userInput('new@example.test'),
            'displayName': 'Replacement',
          },
        );
        expect(replaced.statusCode, 200);
        expect(_json(replaced)['displayName'], 'Replacement');

        final patched = await harness.request(
          'PATCH',
          '/scim/v2/Users/$resourceId',
          token: 'write-a',
          body: const <String, Object?>{
            'schemas': <String>[authScimPatchOperationSchema],
            'Operations': <Object?>[
              <String, Object?>{
                'op': 'replace',
                'path': 'displayName',
                'value': 'Patched',
              },
              <String, Object?>{
                'op': 'replace',
                'path': 'active',
                'value': false,
              },
            ],
          },
        );
        expect(patched.statusCode, 200);
        expect(_json(patched), containsPair('displayName', 'Patched'));
        expect(_json(patched), containsPair('active', false));

        final invalidPath = await harness.request(
          'PATCH',
          '/scim/v2/Users/$resourceId',
          token: 'write-a',
          body: const <String, Object?>{
            'schemas': <String>[authScimPatchOperationSchema],
            'Operations': <Object?>[
              <String, Object?>{
                'op': 'replace',
                'path': 'password',
                'value': 'must-not-be-accepted',
              },
            ],
          },
        );
        expect(invalidPath.statusCode, 400);
        expect(invalidPath.body, isNot(contains('must-not-be-accepted')));

        final tooMany = await harness.request(
          'PATCH',
          '/scim/v2/Users/$resourceId',
          token: 'write-a',
          body: const <String, Object?>{
            'schemas': <String>[authScimPatchOperationSchema],
            'Operations': <Object?>[
              <String, Object?>{
                'op': 'replace',
                'path': 'displayName',
                'value': 'one',
              },
              <String, Object?>{
                'op': 'replace',
                'path': 'displayName',
                'value': 'two',
              },
              <String, Object?>{
                'op': 'replace',
                'path': 'displayName',
                'value': 'three',
              },
            ],
          },
        );
        expect(tooMany.statusCode, 400);

        final deleted = await harness.request(
          'DELETE',
          '/scim/v2/Users/$resourceId',
          token: 'write-a',
        );
        expect(deleted.statusCode, 204);
        expect(deleted.body, isEmpty);
        expect(harness.store.resources, isEmpty);
        expect(harness.store.tombstones, hasLength(1));
        expect(
          harness.store.tombstones.single.state,
          AuthScimDirectoryUserState.tombstoned,
        );
      },
    );

    test(
      'rejects unknown nested attributes and redacts store failures',
      () async {
        final harness = _Harness();
        final unknown = await harness.request(
          'POST',
          '/scim/v2/Users',
          token: 'write-a',
          body: <String, Object?>{
            ..._userInput('new@example.test'),
            'name': const <String, Object?>{'givenName': 'New', 'secret': 'x'},
          },
        );
        expect(unknown.statusCode, 400);

        harness.store.listFailure = StateError('database-password=hunter2');
        final failed = await harness.request(
          'GET',
          '/scim/v2/Users',
          token: 'read-a',
        );
        expect(failed.statusCode, 500);
        expect(failed.body, isNot(contains('hunter2')));
        expect(failed.body, isNot(contains('database-password')));
      },
    );

    test(
      'never links by email and tombstoning preserves the auth user',
      () async {
        final harness = _Harness();
        await harness.authStore.users.create(
          AuthUser(id: 'existing-user', email: 'same@example.test'),
        );
        final created = await harness.request(
          'POST',
          '/scim/v2/Users',
          token: 'write-a',
          body: _userInput('same@example.test'),
        );
        expect(created.statusCode, 201);
        final resourceId = _json(created)['id']! as String;
        expect(
          await harness.authStore.users.findById('existing-user'),
          isNotNull,
        );

        final deleted = await harness.request(
          'DELETE',
          '/scim/v2/Users/$resourceId',
          token: 'write-a',
        );
        expect(deleted.statusCode, 204);
        expect(
          await harness.authStore.users.findById('existing-user'),
          isNotNull,
        );
        expect(harness.store.tombstones.single.id, resourceId);
      },
    );
  });
}

Map<String, Object?> _userInput(String userName) => <String, Object?>{
  'schemas': const <String>[authScimUserSchema],
  'userName': userName,
  'active': true,
  'emails': <Object?>[
    <String, Object?>{'value': userName, 'primary': true},
  ],
};

Map<String, dynamic> _json(AuthTestHttpResponse response) =>
    Map<String, dynamic>.from(jsonDecode(response.body) as Map);

final class _Harness {
  _Harness({
    AuthScimBearerTokenResolver<Object>? resolver,
    AuthScimOptions? options,
    AuthScimFailureReporter? reportFailure,
  }) : authStore = InMemoryAuthStore() {
    store = _MemoryScimStore();
    plugin = ScimPlugin<Object>(
      store: store,
      tokenResolver: resolver ?? _Resolver(_resolveToken),
      options: options,
      reportFailure: reportFailure,
    );
    runtime = AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: const <AuthProvider>[],
        store: authStore,
        storeMode: AuthStoreMode.ephemeral,
        plugins: <AuthServerPlugin<Object>>[plugin],
      ),
    );
    fixture = AuthPluginEndpointFixture<Object>(
      endpoints: runtime.registry.endpoints,
      invocation: (_) =>
          AuthOperationInvocation<Object>(context: Object(), user: null),
    );
  }

  final InMemoryAuthStore authStore;
  late final _MemoryScimStore store;
  late final ScimPlugin<Object> plugin;
  late final AuthRuntime<Object> runtime;
  late final AuthPluginEndpointFixture<Object> fixture;

  Future<void> seed({
    required String connectionId,
    required String tenantId,
    required String organizationId,
    required String provisioningDomainId,
    required String resourceId,
    required String userName,
  }) async {
    store.seed(
      AuthScimUser(
        connectionId: connectionId,
        tenantId: tenantId,
        organizationId: organizationId,
        provisioningDomainId: provisioningDomainId,
        id: resourceId,
        data: AuthScimUserData(
          userName: userName,
          emails: <AuthScimUserEmail>[
            AuthScimUserEmail(value: userName, primary: true),
          ],
        ),
        meta: AuthScimResourceMeta(
          created: DateTime.utc(2026),
          lastModified: DateTime.utc(2026),
          version: '"1"',
        ),
        state: AuthScimDirectoryUserState.active,
      ),
    );
  }

  Future<AuthTestHttpResponse> request(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? body,
  }) => fixture.respond(
    AuthTestHttpRequest(
      method: method,
      uri: Uri.parse('https://example.test/auth$path'),
      headers: <String, String>{
        if (token != null) 'authorization': 'Bearer $token',
      },
      body: body == null ? '' : jsonEncode(body),
    ),
  );
}

AuthScimConnectionIdentity? _resolveToken(
  AuthScimBearerTokenRequest<Object> request,
) => switch (request.token) {
  'read-a' => _connection(
    connectionId: 'connection-a',
    tenantId: 'tenant-a',
    organizationId: 'org-a',
    provisioningDomainId: 'domain-a',
    scopes: const <AuthScimScope>[AuthScimScope.usersRead],
  ),
  'write-a' => _connection(
    connectionId: 'connection-a',
    tenantId: 'tenant-a',
    organizationId: 'org-a',
    provisioningDomainId: 'domain-a',
    scopes: const <AuthScimScope>[AuthScimScope.usersWrite],
  ),
  'read-b' => _connection(
    connectionId: 'connection-b',
    tenantId: 'tenant-b',
    organizationId: 'org-b',
    provisioningDomainId: 'domain-b',
    scopes: const <AuthScimScope>[AuthScimScope.usersRead],
  ),
  'read-a-other-connection' => _connection(
    connectionId: 'connection-a-other',
    tenantId: 'tenant-a',
    organizationId: 'org-a',
    provisioningDomainId: 'domain-a',
    scopes: const <AuthScimScope>[AuthScimScope.usersRead],
  ),
  'no-access' => _connection(
    connectionId: 'connection-a',
    tenantId: 'tenant-a',
    organizationId: 'org-a',
    provisioningDomainId: 'domain-a',
    scopes: const <AuthScimScope>[],
  ),
  _ => null,
};

AuthScimConnectionIdentity _connection({
  required String connectionId,
  required String tenantId,
  required String organizationId,
  required String provisioningDomainId,
  required Iterable<AuthScimScope> scopes,
}) => AuthScimConnectionIdentity(
  connectionId: connectionId,
  credentialId: 'credential-$connectionId',
  tenantId: tenantId,
  organizationId: organizationId,
  provisioningDomainId: provisioningDomainId,
  subjectId: 'provisioner',
  scopes: scopes,
  expiresAt: DateTime.utc(2030),
);

final class _Resolver implements AuthScimBearerTokenResolver<Object> {
  const _Resolver(this.callback);

  final FutureOr<AuthScimConnectionIdentity?> Function(
    AuthScimBearerTokenRequest<Object>,
  )
  callback;

  @override
  FutureOr<AuthScimConnectionIdentity?> resolve(
    AuthScimBearerTokenRequest<Object> request,
  ) => callback(request);
}

typedef _ResourceKey = (String, String, String, String, String);

final class _MemoryScimStore implements AuthScimProvisioningStore {
  final Map<_ResourceKey, AuthScimUser> _resources =
      <_ResourceKey, AuthScimUser>{};
  var _sequence = 0;
  AuthScimListUsersQuery? lastQuery;
  bool crossTenantListLeak = false;
  Object? listFailure;

  List<AuthScimUser> get resources =>
      _resources.values
          .where(
            (resource) =>
                resource.state != AuthScimDirectoryUserState.tombstoned,
          )
          .toList(growable: false)
        ..sort((a, b) => a.id.compareTo(b.id));

  List<AuthScimUser> get tombstones => _resources.values
      .where(
        (resource) => resource.state == AuthScimDirectoryUserState.tombstoned,
      )
      .toList(growable: false);

  void seed(AuthScimUser resource) {
    _resources[_keyFor(resource)] = resource;
  }

  @override
  Future<AuthScimUserPage> listUsers(
    AuthScimProvisioningContext context,
    AuthScimListUsersQuery query,
  ) async {
    if (listFailure case final failure?) throw failure;
    lastQuery = query;
    var values = crossTenantListLeak
        ? resources
        : resources
              .where(
                (resource) =>
                    resource.connectionId == context.connectionId &&
                    resource.tenantId == context.tenantId &&
                    resource.organizationId == context.organizationId &&
                    resource.provisioningDomainId ==
                        context.provisioningDomainId,
              )
              .toList(growable: false);
    final filter = query.filter;
    if (filter != null) {
      values = values
          .where((resource) => _matches(resource, filter))
          .toList(growable: false);
    }
    final total = values.length;
    final offset = query.startIndex - 1;
    final page = offset >= total
        ? const <AuthScimUser>[]
        : values.skip(offset).take(query.count).toList(growable: false);
    return AuthScimUserPage(resources: page, totalResults: total);
  }

  @override
  Future<AuthScimUser?> findUser(
    AuthScimProvisioningContext context,
    String resourceId,
  ) async {
    final resource = _resources[_key(context, resourceId)];
    if (resource == null ||
        resource.organizationId != context.organizationId ||
        resource.state == AuthScimDirectoryUserState.tombstoned) {
      return null;
    }
    return resource;
  }

  @override
  Future<AuthScimUser> createUser(
    AuthScimProvisioningContext context,
    AuthScimUserData user,
  ) async {
    _ensureUnique(context, user);
    final id = 'scim-${++_sequence}';
    final now = DateTime.utc(2026, 1, 1, 0, 0, _sequence);
    final resource = AuthScimUser(
      connectionId: context.connectionId,
      tenantId: context.tenantId,
      organizationId: context.organizationId,
      provisioningDomainId: context.provisioningDomainId,
      id: id,
      data: user,
      meta: AuthScimResourceMeta(
        created: now,
        lastModified: now,
        location: Uri.parse('/auth/scim/v2/Users/$id'),
        version: '"1"',
      ),
      state: user.active
          ? AuthScimDirectoryUserState.active
          : AuthScimDirectoryUserState.inactive,
    );
    seed(resource);
    return resource;
  }

  @override
  Future<AuthScimUser?> replaceUser(
    AuthScimProvisioningContext context,
    String resourceId,
    AuthScimUserData user,
  ) async {
    final current = await findUser(context, resourceId);
    if (current == null) return null;
    _ensureUnique(context, user, exceptId: resourceId);
    return _replace(current, user);
  }

  @override
  Future<AuthScimUser?> patchUser(
    AuthScimProvisioningContext context,
    String resourceId,
    AuthScimPatchDocument patch,
  ) async {
    final current = await findUser(context, resourceId);
    if (current == null) return null;
    final updated = patch.apply(current.data);
    _ensureUnique(context, updated, exceptId: resourceId);
    return _replace(current, updated);
  }

  Future<AuthScimUser> _replace(
    AuthScimUser current,
    AuthScimUserData data,
  ) async {
    final version = int.parse(current.meta.version!.replaceAll('"', '')) + 1;
    final resource = AuthScimUser(
      connectionId: current.connectionId,
      tenantId: current.tenantId,
      organizationId: current.organizationId,
      provisioningDomainId: current.provisioningDomainId,
      id: current.id,
      data: data,
      meta: AuthScimResourceMeta(
        created: current.meta.created,
        lastModified: current.meta.lastModified.add(const Duration(seconds: 1)),
        version: '"$version"',
      ),
      state: data.active
          ? AuthScimDirectoryUserState.active
          : AuthScimDirectoryUserState.inactive,
    );
    seed(resource);
    return resource;
  }

  void _ensureUnique(
    AuthScimProvisioningContext context,
    AuthScimUserData data, {
    String? exceptId,
  }) {
    final collision = resources.any(
      (resource) =>
          resource.id != exceptId &&
          resource.connectionId == context.connectionId &&
          resource.tenantId == context.tenantId &&
          resource.organizationId == context.organizationId &&
          resource.provisioningDomainId == context.provisioningDomainId &&
          resource.data.userName.toLowerCase() == data.userName.toLowerCase(),
    );
    if (collision) throw const AuthScimConflictException();
  }

  @override
  Future<AuthScimUser?> tombstoneUser(
    AuthScimProvisioningContext context,
    String resourceId,
  ) async {
    final current = await findUser(context, resourceId);
    if (current == null) return null;
    final tombstonedAt = current.meta.lastModified.add(
      const Duration(seconds: 1),
    );
    final tombstone = AuthScimUser(
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
        lastModified: tombstonedAt,
        version: '"tombstone"',
      ),
      state: AuthScimDirectoryUserState.tombstoned,
      tombstonedAt: tombstonedAt,
    );
    seed(tombstone);
    return tombstone;
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

_ResourceKey _key(AuthScimProvisioningContext context, String resourceId) => (
  context.connectionId,
  context.tenantId,
  context.organizationId,
  context.provisioningDomainId,
  resourceId,
);

_ResourceKey _keyFor(AuthScimUser resource) => (
  resource.connectionId,
  resource.tenantId,
  resource.organizationId,
  resource.provisioningDomainId,
  resource.id,
);

bool _matches(AuthScimUser resource, AuthScimUserFilter filter) {
  final expected = filter.value.toLowerCase();
  return switch (filter.attribute) {
    AuthScimUserFilterAttribute.id => resource.id.toLowerCase() == expected,
    AuthScimUserFilterAttribute.userName =>
      resource.data.userName.toLowerCase() == expected,
    AuthScimUserFilterAttribute.externalId =>
      resource.data.externalId?.toLowerCase() == expected,
    AuthScimUserFilterAttribute.email => resource.data.emails.any(
      (email) => email.value.toLowerCase() == expected,
    ),
  };
}
