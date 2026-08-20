import 'dart:async';
import 'dart:convert';

import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  group('SCIM Groups authorization and discovery', () {
    test('uses exact Group scopes and permits group-only discovery', () async {
      final harness = _GroupHarness();

      expect(
        (await harness.request(
          'GET',
          '/scim/v2/ServiceProviderConfig',
          token: 'groups-read-a',
        )).statusCode,
        200,
      );
      expect(
        (await harness.request(
          'GET',
          '/scim/v2/Groups',
          token: 'users-write-a',
        )).statusCode,
        403,
      );
      expect(
        (await harness.request(
          'POST',
          '/scim/v2/Groups',
          token: 'groups-read-a',
          body: _groupInput('Readers'),
        )).statusCode,
        403,
      );
      expect(
        (await harness.request(
          'GET',
          '/scim/v2/Groups',
          token: 'groups-write-a',
        )).statusCode,
        200,
      );
    });
  });

  group('SCIM Groups lifecycle', () {
    test(
      'creates, filters, replaces, patches, and tombstones a Group',
      () async {
        final harness = _GroupHarness();
        harness.store.seedUser(_directoryUser('user-1', 'one@example.test'));
        harness.store.seedUser(_directoryUser('user-2', 'two@example.test'));

        final created = await harness.request(
          'POST',
          '/scim/v2/Groups',
          token: 'groups-write-a',
          body: _groupInput(
            'Operators',
            externalId: 'directory-operators',
            members: <Map<String, Object?>>[_member('user-1')],
          ),
        );
        expect(created.statusCode, 201);
        expect(created.headers['Content-Type'], authScimMediaType);
        final createdJson = _json(created);
        final groupId = createdJson['id']! as String;
        expect(createdJson['displayName'], 'Operators');
        expect(
          (createdJson['meta']! as Map<String, dynamic>)['resourceType'],
          'Group',
        );

        final listed = await harness.request(
          'GET',
          '/scim/v2/Groups?count=1&filter=displayName%20eq%20%22Operators%22',
          token: 'groups-read-a',
        );
        expect(listed.statusCode, 200);
        expect(_json(listed)['totalResults'], 1);
        expect(_json(listed)['itemsPerPage'], 1);

        final isolated = await harness.request(
          'GET',
          '/scim/v2/Groups/$groupId',
          token: 'groups-read-b',
        );
        expect(isolated.statusCode, 404);

        final replaced = await harness.request(
          'PUT',
          '/scim/v2/Groups/$groupId',
          token: 'groups-write-a',
          body: _groupInput(
            'Platform operators',
            members: <Map<String, Object?>>[_member('user-1')],
          ),
        );
        expect(replaced.statusCode, 200);
        expect(_json(replaced)['displayName'], 'Platform operators');

        final patched = await harness.request(
          'PATCH',
          '/scim/v2/Groups/$groupId',
          token: 'groups-write-a',
          body: <String, Object?>{
            'schemas': const <String>[authScimPatchOperationSchema],
            'Operations': <Object?>[
              <String, Object?>{
                'op': 'add',
                'path': 'members',
                'value': <Object?>[_member('user-2')],
              },
            ],
          },
        );
        expect(patched.statusCode, 200);
        expect((_json(patched)['members']! as List), hasLength(2));

        final deleted = await harness.request(
          'DELETE',
          '/scim/v2/Groups/$groupId',
          token: 'groups-write-a',
        );
        expect(deleted.statusCode, 204);
        expect(deleted.body, isEmpty);
        expect(harness.store.liveGroups, isEmpty);
        expect(harness.store.tombstones.single.data.members, isEmpty);

        final replay = await harness.request(
          'DELETE',
          '/scim/v2/Groups/$groupId',
          token: 'groups-write-a',
        );
        expect(replay.statusCode, 404);
        expect(harness.store.tombstones, hasLength(1));
      },
    );

    test(
      'rejects member overflow, duplicates, conflicts, and unknown members',
      () async {
        final harness = _GroupHarness(maximumGroupMembers: 2);
        harness.store.seedUser(_directoryUser('user-1', 'one@example.test'));
        harness.store.seedUser(_directoryUser('user-2', 'two@example.test'));

        for (final members in <List<Map<String, Object?>>>[
          <Map<String, Object?>>[_member('user-1'), _member('user-1')],
          <Map<String, Object?>>[
            _member('user-1'),
            _member('user-1', type: 'Group'),
          ],
          <Map<String, Object?>>[
            _member('user-1'),
            _member('user-2'),
            _member('missing'),
          ],
        ]) {
          final response = await harness.request(
            'POST',
            '/scim/v2/Groups',
            token: 'groups-write-a',
            body: _groupInput('Rejected', members: members),
          );
          expect(response.statusCode, 400);
          expect(response.body, isNot(contains('user-1')));
        }

        final missing = await harness.request(
          'POST',
          '/scim/v2/Groups',
          token: 'groups-write-a',
          body: _groupInput(
            'Unknown member',
            members: <Map<String, Object?>>[_member('not-provisioned')],
          ),
        );
        expect(missing.statusCode, 409);
        expect(_json(missing)['detail'], 'SCIM resource conflict.');
      },
    );

    test('rejects malformed filters and patches with generic errors', () async {
      final harness = _GroupHarness();
      for (final filter in <String>[
        'displayName co "admin"',
        'members.value eq "user-1"',
        'displayName eq "unterminated',
      ]) {
        final response = await harness.request(
          'GET',
          '/scim/v2/Groups?filter=${Uri.encodeQueryComponent(filter)}',
          token: 'groups-read-a',
        );
        expect(response.statusCode, 400);
        expect(response.body, isNot(contains(filter)));
      }

      final created = await harness.request(
        'POST',
        '/scim/v2/Groups',
        token: 'groups-write-a',
        body: _groupInput('Patch target'),
      );
      final id = _json(created)['id']! as String;
      for (final operation in <Map<String, Object?>>[
        <String, Object?>{'op': 'remove', 'path': 'displayName'},
        <String, Object?>{'op': 'replace', 'path': 'roles', 'value': 'admin'},
        <String, Object?>{'op': 'add', 'path': 'members'},
      ]) {
        final response = await harness.request(
          'PATCH',
          '/scim/v2/Groups/$id',
          token: 'groups-write-a',
          body: <String, Object?>{
            'schemas': const <String>[authScimPatchOperationSchema],
            'Operations': <Object?>[operation],
          },
        );
        expect(response.statusCode, 400);
        expect(response.body, isNot(contains('admin')));
      }
    });

    test('direct membership boundary is atomic and connection scoped', () {
      final harness = _GroupHarness();
      harness.store.seedUser(_directoryUser('user-1', 'one@example.test'));
      harness.store.seedUser(_directoryUser('user-2', 'two@example.test'));
      final context = AuthScimProvisioningContext(
        connection: _connection(
          connectionId: 'connection-a',
          tenantId: 'tenant-a',
          organizationId: 'org-a',
          provisioningDomainId: 'domain-a',
          scopes: const <AuthScimScope>[AuthScimScope.groupsWrite],
        ),
      );
      final group = harness.store.createGroup(
        context,
        AuthScimGroupData(
          displayName: 'Direct mutation',
          members: <AuthScimGroupMember>[
            AuthScimGroupMember(
              value: 'user-1',
              type: AuthScimGroupMemberType.user,
            ),
          ],
        ),
      );
      final updated = harness.store.mutateGroupMembership(
        context,
        AuthScimGroupMembershipMutation(
          groupResourceId: group.id,
          kind: AuthScimGroupMembershipMutationKind.add,
          members: <AuthScimGroupMember>[
            AuthScimGroupMember(
              value: 'user-2',
              type: AuthScimGroupMemberType.user,
            ),
          ],
        ),
      );
      expect(updated!.data.members.map((value) => value.value), <String>[
        'user-1',
        'user-2',
      ]);

      final otherContext = AuthScimProvisioningContext(
        connection: _connection(
          connectionId: 'connection-b',
          tenantId: 'tenant-b',
          organizationId: 'org-b',
          provisioningDomainId: 'domain-b',
          scopes: const <AuthScimScope>[AuthScimScope.groupsWrite],
        ),
      );
      expect(
        harness.store.mutateGroupMembership(
          otherContext,
          AuthScimGroupMembershipMutation(
            groupResourceId: group.id,
            kind: AuthScimGroupMembershipMutationKind.remove,
            members: <AuthScimGroupMember>[
              AuthScimGroupMember(
                value: 'user-1',
                type: AuthScimGroupMemberType.user,
              ),
            ],
          ),
        ),
        isNull,
      );
      expect(
        harness.store.findGroup(context, group.id)!.data.members,
        hasLength(2),
      );
    });
  });

  test('declares durable atomic semantics for every Group mutation', () {
    final harness = _GroupHarness();
    final schema = harness.plugin.persistenceSchemas.single;
    expect(
      schema.entities.map((value) => value.id),
      containsAll(<String>['directoryGroup', 'directoryGroupMember']),
    );
    final operations = schema.atomicOperations.map((value) => value.id).toSet();
    for (final endpoint in harness.plugin.endpoints.where(
      (value) => value.id.startsWith('scim.groups.'),
    )) {
      if (endpoint.method == AuthOperationMethod.get) {
        expect(endpoint.semantics, isA<AuthReadOnlyOperationSemantics>());
        continue;
      }
      final semantics = endpoint.semantics as AuthMutationOperationSemantics;
      expect(semantics.persistence.atomicity, AuthMutationAtomicity.atomic);
      final reference = semantics.persistence.reference!;
      expect(reference.schemaId, 'scim.directory');
      expect(operations, contains(reference.atomicOperationId));
    }
  });

  test(
    'projection input contains stable SCIM identities and exact binding only',
    () {
      final connection = _connection(
        connectionId: 'connection-a',
        tenantId: 'tenant-a',
        organizationId: 'org-a',
        provisioningDomainId: 'domain-a',
        scopes: const <AuthScimScope>[AuthScimScope.groupsWrite],
      );
      final change = AuthScimRoleMembershipProjectionChange(
        context: AuthScimProvisioningContext(connection: connection),
        groupResourceId: 'group-1',
        before: const <AuthScimStableResourceIdentity>[],
        after: <AuthScimStableResourceIdentity>[
          AuthScimStableResourceIdentity(
            resourceId: 'user-1',
            type: AuthScimGroupMemberType.user,
          ),
        ],
      );
      expect(change.context.connectionId, 'connection-a');
      expect(change.groupResourceId, 'group-1');
      expect(change.after.single.resourceId, 'user-1');
    },
  );
}

Map<String, Object?> _groupInput(
  String displayName, {
  String? externalId,
  List<Map<String, Object?>> members = const <Map<String, Object?>>[],
}) => <String, Object?>{
  'schemas': const <String>[authScimGroupSchema],
  'displayName': displayName,
  'externalId': ?externalId,
  if (members.isNotEmpty) 'members': members,
};

Map<String, Object?> _member(String value, {String type = 'User'}) =>
    <String, Object?>{'value': value, 'type': type};

Map<String, dynamic> _json(AuthTestHttpResponse response) =>
    Map<String, dynamic>.from(jsonDecode(response.body) as Map);

final class _GroupHarness {
  _GroupHarness({int maximumGroupMembers = 5}) {
    store = _MemoryGroupStore(maximumMembers: maximumGroupMembers);
    plugin = ScimPlugin<Object>(
      store: store,
      tokenResolver: const _GroupResolver(),
      options: AuthScimOptions(maximumGroupMembers: maximumGroupMembers),
    );
    final runtime = AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: const <AuthProvider>[],
        store: InMemoryAuthStore(),
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

  late final _MemoryGroupStore store;
  late final ScimPlugin<Object> plugin;
  late final AuthPluginEndpointFixture<Object> fixture;

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

final class _GroupResolver implements AuthScimBearerTokenResolver<Object> {
  const _GroupResolver();

  @override
  AuthScimConnectionIdentity? resolve(
    AuthScimBearerTokenRequest<Object> request,
  ) => switch (request.token) {
    'groups-read-a' => _connection(
      connectionId: 'connection-a',
      tenantId: 'tenant-a',
      organizationId: 'org-a',
      provisioningDomainId: 'domain-a',
      scopes: const <AuthScimScope>[AuthScimScope.groupsRead],
    ),
    'groups-write-a' => _connection(
      connectionId: 'connection-a',
      tenantId: 'tenant-a',
      organizationId: 'org-a',
      provisioningDomainId: 'domain-a',
      scopes: const <AuthScimScope>[AuthScimScope.groupsWrite],
    ),
    'groups-read-b' => _connection(
      connectionId: 'connection-b',
      tenantId: 'tenant-b',
      organizationId: 'org-b',
      provisioningDomainId: 'domain-b',
      scopes: const <AuthScimScope>[AuthScimScope.groupsRead],
    ),
    'users-write-a' => _connection(
      connectionId: 'connection-a',
      tenantId: 'tenant-a',
      organizationId: 'org-a',
      provisioningDomainId: 'domain-a',
      scopes: const <AuthScimScope>[AuthScimScope.usersWrite],
    ),
    _ => null,
  };
}

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

typedef _Key = (String, String, String, String, String);

final class _MemoryGroupStore implements AuthScimProvisioningStore {
  _MemoryGroupStore({required this.maximumMembers});

  final int maximumMembers;
  final Map<_Key, AuthScimUser> _users = <_Key, AuthScimUser>{};
  final Map<_Key, AuthScimGroup> _groups = <_Key, AuthScimGroup>{};
  var _sequence = 0;

  List<AuthScimGroup> get liveGroups => _groups.values
      .where((value) => value.state == AuthScimDirectoryGroupState.active)
      .toList(growable: false);
  List<AuthScimGroup> get tombstones => _groups.values
      .where((value) => value.state == AuthScimDirectoryGroupState.tombstoned)
      .toList(growable: false);

  void seedUser(AuthScimUser user) => _users[_userKey(user)] = user;

  @override
  AuthScimGroupPage listGroups(
    AuthScimProvisioningContext context,
    AuthScimListGroupsQuery query,
  ) {
    var values =
        liveGroups.where((value) => _boundGroup(context, value)).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    final filter = query.filter;
    if (filter != null) {
      values = values.where((group) => _matchesGroup(group, filter)).toList();
    }
    final total = values.length;
    final offset = query.startIndex - 1;
    return AuthScimGroupPage(
      resources: offset >= total
          ? const <AuthScimGroup>[]
          : values.skip(offset).take(query.count),
      totalResults: total,
    );
  }

  @override
  AuthScimGroup? findGroup(
    AuthScimProvisioningContext context,
    String resourceId,
  ) {
    final group = _groups[_key(context, resourceId)];
    return group != null &&
            group.state == AuthScimDirectoryGroupState.active &&
            _boundGroup(context, group)
        ? group
        : null;
  }

  @override
  AuthScimGroup createGroup(
    AuthScimProvisioningContext context,
    AuthScimGroupData group,
  ) {
    _ensureUnique(context, group);
    final id = 'group-${++_sequence}';
    _validateMembers(context, id, group.members);
    final now = DateTime.utc(2026, 1, 1, 0, 0, _sequence);
    final resource = AuthScimGroup(
      connectionId: context.connectionId,
      tenantId: context.tenantId,
      organizationId: context.organizationId,
      provisioningDomainId: context.provisioningDomainId,
      id: id,
      data: group,
      meta: AuthScimResourceMeta(
        created: now,
        lastModified: now,
        resourceType: 'Group',
        location: Uri.parse('/auth/scim/v2/Groups/$id'),
        version: '"1"',
      ),
      state: AuthScimDirectoryGroupState.active,
    );
    _groups[_key(context, id)] = resource;
    return resource;
  }

  @override
  AuthScimGroup? replaceGroup(
    AuthScimProvisioningContext context,
    String resourceId,
    AuthScimGroupData group,
  ) {
    final current = findGroup(context, resourceId);
    if (current == null) return null;
    _ensureUnique(context, group, exceptId: resourceId);
    _validateMembers(context, resourceId, group.members);
    return _replace(current, group);
  }

  @override
  AuthScimGroup? patchGroup(
    AuthScimProvisioningContext context,
    String resourceId,
    AuthScimGroupPatchDocument patch,
  ) {
    final current = findGroup(context, resourceId);
    if (current == null) return null;
    final next = patch.apply(current.data, maximumMembers: maximumMembers);
    _ensureUnique(context, next, exceptId: resourceId);
    _validateMembers(context, resourceId, next.members);
    return _replace(current, next);
  }

  @override
  AuthScimGroup? mutateGroupMembership(
    AuthScimProvisioningContext context,
    AuthScimGroupMembershipMutation mutation,
  ) {
    final current = findGroup(context, mutation.groupResourceId);
    if (current == null) return null;
    final members = switch (mutation.kind) {
      AuthScimGroupMembershipMutationKind.add => <AuthScimGroupMember>[
        ...current.data.members,
        ...mutation.members,
      ],
      AuthScimGroupMembershipMutationKind.remove =>
        current.data.members
            .where(
              (member) => !mutation.members.any(
                (removed) =>
                    member.value == removed.value &&
                    member.type == removed.type,
              ),
            )
            .toList(growable: false),
      AuthScimGroupMembershipMutationKind.replace => mutation.members,
    };
    final next = AuthScimGroupData(
      displayName: current.data.displayName,
      externalId: current.data.externalId,
      members: members,
      maximumMembers: maximumMembers,
    );
    _validateMembers(context, current.id, next.members);
    return _replace(current, next);
  }

  @override
  AuthScimGroup? tombstoneGroup(
    AuthScimProvisioningContext context,
    String resourceId,
  ) {
    final current = findGroup(context, resourceId);
    if (current == null) return null;
    final instant = current.meta.lastModified.add(const Duration(seconds: 1));
    final tombstone = AuthScimGroup(
      connectionId: current.connectionId,
      tenantId: current.tenantId,
      organizationId: current.organizationId,
      provisioningDomainId: current.provisioningDomainId,
      id: current.id,
      data: AuthScimGroupData(
        displayName: current.data.displayName,
        externalId: current.data.externalId,
        maximumMembers: maximumMembers,
      ),
      meta: AuthScimResourceMeta(
        created: current.meta.created,
        lastModified: instant,
        resourceType: 'Group',
        version: '"tombstone"',
      ),
      state: AuthScimDirectoryGroupState.tombstoned,
      tombstonedAt: instant,
    );
    _groups[_key(context, resourceId)] = tombstone;
    return tombstone;
  }

  AuthScimGroup _replace(AuthScimGroup current, AuthScimGroupData data) {
    final version = int.parse(current.meta.version!.replaceAll('"', '')) + 1;
    final updated = AuthScimGroup(
      connectionId: current.connectionId,
      tenantId: current.tenantId,
      organizationId: current.organizationId,
      provisioningDomainId: current.provisioningDomainId,
      id: current.id,
      data: data,
      meta: AuthScimResourceMeta(
        created: current.meta.created,
        lastModified: current.meta.lastModified.add(const Duration(seconds: 1)),
        resourceType: 'Group',
        version: '"$version"',
      ),
      state: AuthScimDirectoryGroupState.active,
    );
    _groups[_groupKey(updated)] = updated;
    return updated;
  }

  void _ensureUnique(
    AuthScimProvisioningContext context,
    AuthScimGroupData data, {
    String? exceptId,
  }) {
    if (liveGroups.any(
      (group) =>
          group.id != exceptId &&
          _boundGroup(context, group) &&
          group.data.displayName.toLowerCase() ==
              data.displayName.toLowerCase(),
    )) {
      throw const AuthScimConflictException();
    }
  }

  void _validateMembers(
    AuthScimProvisioningContext context,
    String groupId,
    List<AuthScimGroupMember> members,
  ) {
    for (final member in members) {
      final user = _users[_key(context, member.value)];
      final valid = switch (member.type) {
        AuthScimGroupMemberType.user =>
          user != null && user.state != AuthScimDirectoryUserState.tombstoned,
        AuthScimGroupMemberType.group =>
          member.value != groupId && findGroup(context, member.value) != null,
      };
      if (!valid) throw const AuthScimConflictException();
    }
  }

  @override
  AuthScimUserPage listUsers(
    AuthScimProvisioningContext context,
    AuthScimListUsersQuery query,
  ) => AuthScimUserPage(resources: const <AuthScimUser>[], totalResults: 0);

  @override
  AuthScimUser? findUser(
    AuthScimProvisioningContext context,
    String resourceId,
  ) => _users[_key(context, resourceId)];

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
}

AuthScimUser _directoryUser(String id, String userName) => AuthScimUser(
  connectionId: 'connection-a',
  tenantId: 'tenant-a',
  organizationId: 'org-a',
  provisioningDomainId: 'domain-a',
  id: id,
  data: AuthScimUserData(userName: userName),
  meta: AuthScimResourceMeta(
    created: DateTime.utc(2026),
    lastModified: DateTime.utc(2026),
  ),
  state: AuthScimDirectoryUserState.active,
);

_Key _key(AuthScimProvisioningContext context, String resourceId) => (
  context.connectionId,
  context.tenantId,
  context.organizationId,
  context.provisioningDomainId,
  resourceId,
);

_Key _userKey(AuthScimUser resource) => (
  resource.connectionId,
  resource.tenantId,
  resource.organizationId,
  resource.provisioningDomainId,
  resource.id,
);

_Key _groupKey(AuthScimGroup resource) => (
  resource.connectionId,
  resource.tenantId,
  resource.organizationId,
  resource.provisioningDomainId,
  resource.id,
);

bool _boundGroup(AuthScimProvisioningContext context, AuthScimGroup resource) =>
    resource.connectionId == context.connectionId &&
    resource.tenantId == context.tenantId &&
    resource.organizationId == context.organizationId &&
    resource.provisioningDomainId == context.provisioningDomainId;

bool _matchesGroup(AuthScimGroup group, AuthScimGroupFilter filter) {
  final expected = filter.value.toLowerCase();
  return switch (filter.attribute) {
    AuthScimGroupFilterAttribute.id => group.id.toLowerCase() == expected,
    AuthScimGroupFilterAttribute.displayName =>
      group.data.displayName.toLowerCase() == expected,
    AuthScimGroupFilterAttribute.externalId =>
      group.data.externalId?.toLowerCase() == expected,
  };
}
