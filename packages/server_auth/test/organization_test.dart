import 'dart:async';

import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('OrganizationPlugin', () {
    test('is opt-in and contributes immutable portable topology', () {
      final base = AuthOptions<Object>(
        providers: const [],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
      );
      final without = AuthRuntime<Object>(options: base);
      expect(without.plugin(authOrganizationPluginId), isNull);
      expect(without.registry.endpoints, isEmpty);

      final feature = OrganizationPlugin<Object>(
        store: InMemoryAuthOrganizationStore(),
        userStore: InMemoryAuthStore().users,
      );
      final runtime = AuthRuntime<Object>(
        options: base.copyWith(plugins: [feature]),
      );
      expect(runtime.plugin(authOrganizationPluginId), same(feature));
      expect(runtime.registry.isFrozen, isTrue);
      expect(runtime.registry.endpoints, hasLength(36));
      expect(
        runtime.registry.endpoints.map((endpoint) => endpoint.path),
        contains('/organization/create'),
      );
      expect(runtime.registry.persistenceSchemas.single.id, 'organization');
      expect(() => runtime.registry.register(_EmptyPlugin()), throwsStateError);
    });

    test('concurrent slug creation has one winner', () async {
      final feature = OrganizationPlugin<Object>(
        store: InMemoryAuthOrganizationStore(),
      );
      final users = List.generate(
        12,
        (index) => AuthUser(id: 'user-$index', email: 'user$index@example.com'),
      );
      final attempts = await Future.wait(
        users.map((user) async {
          try {
            await feature.createOrganization(
              context: Object(),
              user: user,
              name: 'Acme',
              slug: 'acme',
            );
            return 'ok';
          } on AuthFlowException catch (error) {
            return error.code;
          }
        }),
      );
      expect(attempts.where((value) => value == 'ok'), hasLength(1));
      expect(
        attempts.where((value) => value == 'organization_slug_taken'),
        hasLength(11),
      );
    });

    test('membership limits, duplicates, and last owner are atomic', () async {
      final feature = OrganizationPlugin<Object>(
        store: InMemoryAuthOrganizationStore(),
        options: const AuthOrganizationOptions(membershipLimit: 2),
      );
      final owner = AuthUser(id: 'owner', email: 'owner@example.com');
      final organization = (await feature.createOrganization(
        context: Object(),
        user: owner,
        name: 'Acme',
        slug: 'acme',
      )).data;
      await feature.trustedAddMember(
        context: Object(),
        actor: owner,
        organizationId: organization.id,
        userId: 'member-1',
      );
      await expectLater(
        feature.trustedAddMember(
          context: Object(),
          actor: owner,
          organizationId: organization.id,
          userId: 'member-1',
        ),
        _flow('member_exists'),
      );
      await expectLater(
        feature.trustedAddMember(
          context: Object(),
          actor: owner,
          organizationId: organization.id,
          userId: 'member-2',
        ),
        _flow('membership_limit'),
      );
      await expectLater(
        _invoke(feature, 'organization.leave', owner, {
          'organizationId': organization.id,
        }),
        _flow('last_owner'),
      );
    });

    test('only creator-role actors can mutate creator memberships', () async {
      final store = InMemoryAuthOrganizationStore();
      final feature = OrganizationPlugin<Object>(store: store);
      final owner = AuthUser(id: 'owner', email: 'owner@example.com');
      final admin = AuthUser(id: 'admin', email: 'admin@example.com');
      final organization = (await feature.createOrganization(
        context: Object(),
        user: owner,
        name: 'Acme',
        slug: 'acme',
      )).data;
      await feature.trustedAddMember(
        context: Object(),
        actor: owner,
        organizationId: organization.id,
        userId: admin.id,
        roles: const ['admin'],
      );

      await expectLater(
        _invoke(feature, 'organization.updateMemberRole', admin, {
          'organizationId': organization.id,
          'userId': admin.id,
          'roles': ['owner'],
        }),
        _flow('organization_forbidden'),
      );
      await expectLater(
        _invoke(feature, 'organization.updateMemberRole', admin, {
          'organizationId': organization.id,
          'userId': owner.id,
          'roles': ['member'],
        }),
        _flow('organization_forbidden'),
      );
      await expectLater(
        _invoke(feature, 'organization.removeMember', admin, {
          'organizationId': organization.id,
          'userId': owner.id,
        }),
        _flow('organization_forbidden'),
      );
      await expectLater(
        _invoke(feature, 'organization.inviteMember', admin, {
          'organizationId': organization.id,
          'email': 'new-owner@example.com',
          'roles': ['owner'],
        }),
        _flow('organization_forbidden'),
      );
      expect((await store.findMember(organization.id, admin.id))!.roles, [
        'admin',
      ]);
      expect((await store.findMember(organization.id, owner.id))!.roles, [
        'owner',
      ]);
      expect(await store.listInvitations(organization.id), isEmpty);
    });

    test('creator role normalization preserves the last owner', () async {
      final feature = OrganizationPlugin<Object>(
        store: InMemoryAuthOrganizationStore(),
        options: const AuthOrganizationOptions(creatorRole: ' Owner '),
      );
      final owner = AuthUser(id: 'owner', email: 'owner@example.com');
      final organization = (await feature.createOrganization(
        context: Object(),
        user: owner,
        name: 'Acme',
        slug: 'acme',
      )).data;

      await expectLater(
        _invoke(feature, 'organization.leave', owner, {
          'organizationId': organization.id,
        }),
        _flow('last_owner'),
      );
    });

    test(
      'membership mutation fails closed without atomic capability',
      () async {
        final now = DateTime.utc(2030);
        final organization = AuthOrganization(
          id: 'organization',
          name: 'Acme',
          slug: 'acme',
          createdAt: now,
          updatedAt: now,
        );
        final owner = AuthOrganizationMember(
          id: 'owner-member',
          organizationId: organization.id,
          userId: 'owner',
          roles: const ['owner'],
          createdAt: now,
        );
        final member = AuthOrganizationMember(
          id: 'regular-member',
          organizationId: organization.id,
          userId: 'member',
          roles: const ['member'],
          createdAt: now,
        );
        final feature = OrganizationPlugin<Object>(
          store: _OrganizationStoreWithoutOwnershipCapability(organization, [
            owner,
            member,
          ]),
        );

        await expectLater(
          _invoke(
            feature,
            'organization.removeMember',
            AuthUser(id: 'owner', email: 'owner@example.com'),
            {'organizationId': organization.id, 'userId': member.userId},
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('atomically authorize membership mutations'),
            ),
          ),
        );
      },
    );

    test(
      'creator role definitions are immutable at the store boundary',
      () async {
        final store = InMemoryAuthOrganizationStore();
        final owner = AuthUser(id: 'owner', email: 'owner@example.com');
        final feature = OrganizationPlugin<Object>(store: store);
        final organization = (await feature.createOrganization(
          context: Object(),
          user: owner,
          name: 'Acme',
          slug: 'acme',
        )).data;
        final now = DateTime.utc(2030);
        final role = AuthOrganizationRole(
          id: 'billing-role',
          organizationId: organization.id,
          name: 'billing',
          permissions: const {
            'organization': ['read'],
          },
          createdAt: now,
          updatedAt: now,
        );
        await store.createRole(role);

        await expectLater(
          store.updateRole(
            role.copyWith(name: 'owner'),
            previousName: role.name,
            creatorRole: 'owner',
          ),
          _flow('creator_role'),
        );
        expect(await store.findRole(organization.id, 'billing'), same(role));
        expect((await store.findMember(organization.id, owner.id))!.roles, [
          'owner',
        ]);
      },
    );

    test('invitation is email-bound and consumed exactly once', () async {
      final feature = OrganizationPlugin<Object>(
        store: InMemoryAuthOrganizationStore(),
        userStore: InMemoryAuthStore().users,
      );
      final owner = AuthUser(id: 'owner', email: 'owner@example.com');
      final invited = AuthUser(id: 'invited', email: 'ADA@EXAMPLE.COM');
      final organization = (await feature.createOrganization(
        context: Object(),
        user: owner,
        name: 'Acme',
        slug: 'acme',
      )).data;
      final invite = _map(
        await _invoke(feature, 'organization.inviteMember', owner, {
          'organizationId': organization.id,
          'email': 'ada@example.com',
          'roles': ['member'],
        }),
      );
      final invitationId = _map(invite['data'])['id'] as String;

      await _invoke(feature, 'organization.acceptInvitation', invited, {
        'invitationId': invitationId,
      });
      await expectLater(
        _invoke(feature, 'organization.acceptInvitation', invited, {
          'invitationId': invitationId,
        }),
        _flow('invitation_not_pending'),
      );
      await expectLater(
        _invoke(
          feature,
          'organization.getInvitation',
          AuthUser(id: 'other', email: 'other@example.com'),
          {'invitationId': invitationId},
        ),
        _flow('invitation_email_mismatch'),
      );
    });

    test('invalid invitation teams are rejected before persistence', () async {
      final disabledStore = InMemoryAuthOrganizationStore();
      final disabled = OrganizationPlugin<Object>(store: disabledStore);
      final owner = AuthUser(id: 'owner', email: 'owner@example.com');
      final disabledOrganization = (await disabled.createOrganization(
        context: Object(),
        user: owner,
        name: 'Disabled',
        slug: 'disabled',
      )).data;
      await expectLater(
        _invoke(disabled, 'organization.inviteMember', owner, {
          'organizationId': disabledOrganization.id,
          'email': 'invitee@example.com',
          'teamId': 'missing',
        }),
        _flow('teams_disabled'),
      );
      expect(
        await disabledStore.listInvitations(disabledOrganization.id),
        isEmpty,
      );

      final enabledStore = InMemoryAuthOrganizationStore();
      final enabled = OrganizationPlugin<Object>(
        store: enabledStore,
        options: const AuthOrganizationOptions(
          teams: AuthOrganizationTeamsOptions(enabled: true),
        ),
      );
      final first = (await enabled.createOrganization(
        context: Object(),
        user: owner,
        name: 'First',
        slug: 'first',
      )).data;
      final second = (await enabled.createOrganization(
        context: Object(),
        user: owner,
        name: 'Second',
        slug: 'second',
      )).data;
      final otherTeam = (await enabledStore.listTeams(second.id)).single;
      await expectLater(
        _invoke(enabled, 'organization.inviteMember', owner, {
          'organizationId': first.id,
          'email': 'invitee@example.com',
          'teamId': otherTeam.id,
        }),
        _flow('team_not_found'),
      );
      expect(await enabledStore.listInvitations(first.id), isEmpty);
    });

    test('existing members cannot consume invitation capacity', () async {
      final authStore = InMemoryAuthStore();
      final owner = AuthUser(id: 'owner', email: 'owner@example.com');
      final member = AuthUser(id: 'member', email: 'member@example.com');
      await authStore.users.create(owner);
      await authStore.users.create(member);
      final organizationStore = InMemoryAuthOrganizationStore();
      final feature = OrganizationPlugin<Object>(
        store: organizationStore,
        userStore: authStore.users,
      );
      final organization = (await feature.createOrganization(
        context: Object(),
        user: owner,
        name: 'Acme',
        slug: 'acme',
      )).data;
      await feature.trustedAddMember(
        context: Object(),
        actor: owner,
        organizationId: organization.id,
        userId: member.id,
      );

      await expectLater(
        _invoke(feature, 'organization.inviteMember', owner, {
          'organizationId': organization.id,
          'email': ' MEMBER@example.com ',
        }),
        _flow('member_exists'),
      );
      expect(await organizationStore.listInvitations(organization.id), isEmpty);
    });

    test(
      'dynamic role rename preserves assignment and delete rejects use',
      () async {
        final store = InMemoryAuthOrganizationStore();
        final feature = OrganizationPlugin<Object>(
          store: store,
          userStore: InMemoryAuthStore().users,
          options: const AuthOrganizationOptions(dynamicRoles: true),
        );
        final owner = AuthUser(id: 'owner', email: 'owner@example.com');
        final organization = (await feature.createOrganization(
          context: Object(),
          user: owner,
          name: 'Acme',
          slug: 'acme',
        )).data;
        await _invoke(feature, 'organization.createRole', owner, {
          'organizationId': organization.id,
          'name': 'billing',
          'permissions': {
            'invoice': ['read'],
          },
        });
        await feature.trustedAddMember(
          context: Object(),
          actor: owner,
          organizationId: organization.id,
          userId: 'accountant',
          roles: ['billing'],
        );
        await _invoke(feature, 'organization.updateRole', owner, {
          'organizationId': organization.id,
          'name': 'billing',
          'newName': 'finance',
        });
        expect((await store.findMember(organization.id, 'accountant'))!.roles, [
          'finance',
        ]);
        await expectLater(
          _invoke(feature, 'organization.deleteRole', owner, {
            'organizationId': organization.id,
            'name': 'finance',
          }),
          _flow('role_in_use'),
        );
        expect(
          await feature.hasPermission(
            context: Object(),
            userId: 'accountant',
            organizationId: organization.id,
            resource: 'invoice',
            action: 'read',
          ),
          isTrue,
        );
      },
    );

    test(
      'dynamic role rename updates pending invitations atomically',
      () async {
        final store = InMemoryAuthOrganizationStore();
        final feature = OrganizationPlugin<Object>(
          store: store,
          userStore: InMemoryAuthStore().users,
          options: const AuthOrganizationOptions(dynamicRoles: true),
        );
        final owner = AuthUser(id: 'owner', email: 'owner@example.com');
        final invited = AuthUser(id: 'invited', email: 'invited@example.com');
        final organization = (await feature.createOrganization(
          context: Object(),
          user: owner,
          name: 'Acme',
          slug: 'acme',
        )).data;
        await _invoke(feature, 'organization.createRole', owner, {
          'organizationId': organization.id,
          'name': 'billing',
          'permissions': {
            'invoice': ['read'],
          },
        });
        final result = _map(
          await _invoke(feature, 'organization.inviteMember', owner, {
            'organizationId': organization.id,
            'email': invited.email,
            'roles': ['billing'],
          }),
        );
        final invitationId = _map(result['data'])['id'] as String;

        await expectLater(
          _invoke(feature, 'organization.deleteRole', owner, {
            'organizationId': organization.id,
            'name': 'billing',
          }),
          _flow('role_in_use'),
        );
        await _invoke(feature, 'organization.updateRole', owner, {
          'organizationId': organization.id,
          'name': 'billing',
          'newName': 'finance',
        });
        expect((await store.findInvitation(invitationId))!.roles, ['finance']);

        await _invoke(feature, 'organization.acceptInvitation', invited, {
          'invitationId': invitationId,
        });
        expect((await store.findMember(organization.id, invited.id))!.roles, [
          'finance',
        ]);
        expect(
          await feature.hasPermission(
            context: Object(),
            userId: invited.id,
            organizationId: organization.id,
            resource: 'invoice',
            action: 'read',
          ),
          isTrue,
        );
      },
    );

    test('persistence topology describes every stored field and relation', () {
      final schema = OrganizationPlugin<Object>(
        store: InMemoryAuthOrganizationStore(),
      ).persistenceSchemas.single;
      final entities = {
        for (final entity in schema.entities) entity.id: entity,
      };

      expect(
        entities['organization']!.fields.map((field) => field.name),
        containsAll([
          'id',
          'name',
          'slug',
          'logo',
          'metadata',
          'createdAt',
          'updatedAt',
        ]),
      );
      expect(
        entities['organization_member']!.fields.map((field) => field.name),
        containsAll([
          'id',
          'organizationId',
          'userId',
          'roles',
          'attributes',
          'createdAt',
        ]),
      );
      expect(
        entities['organization_invitation']!.fields.map((field) => field.name),
        containsAll([
          'id',
          'organizationId',
          'email',
          'roles',
          'inviterId',
          'status',
          'expiresAt',
          'createdAt',
          'teamId',
          'attributes',
        ]),
      );
      expect(
        entities['organization_role']!.fields.map((field) => field.name),
        containsAll([
          'id',
          'organizationId',
          'name',
          'permissions',
          'predefined',
          'createdAt',
          'updatedAt',
        ]),
      );
      expect(
        entities['organization_team']!.fields.map((field) => field.name),
        containsAll([
          'id',
          'organizationId',
          'name',
          'attributes',
          'createdAt',
          'updatedAt',
        ]),
      );
      expect(
        entities['organization_team_member']!.fields.map((field) => field.name),
        containsAll(['id', 'teamId', 'userId', 'createdAt']),
      );
      expect(
        entities['organization_member']!.relationships.map(
          (relationship) =>
              '${relationship.field}:${relationship.targetEntity}',
        ),
        unorderedEquals(['organizationId:organization', 'userId:user']),
      );
      expect(
        entities['organization_invitation']!.relationships.map(
          (relationship) =>
              '${relationship.field}:${relationship.targetEntity}',
        ),
        unorderedEquals([
          'organizationId:organization',
          'inviterId:user',
          'teamId:organization_team',
        ]),
      );
      expect(
        entities['organization_role']!.relationships.map(
          (relationship) =>
              '${relationship.field}:${relationship.targetEntity}',
        ),
        ['organizationId:organization'],
      );
      expect(
        entities['organization_team']!.relationships.map(
          (relationship) =>
              '${relationship.field}:${relationship.targetEntity}',
        ),
        ['organizationId:organization'],
      );
      expect(
        entities['organization_team_member']!.relationships.map(
          (relationship) =>
              '${relationship.field}:${relationship.targetEntity}',
        ),
        unorderedEquals(['teamId:organization_team', 'userId:user']),
      );
    });

    test('teams enforce capacity and organization deletion cascades', () async {
      final store = InMemoryAuthOrganizationStore();
      final feature = OrganizationPlugin<Object>(
        store: store,
        options: const AuthOrganizationOptions(
          membershipLimit: 20,
          teams: AuthOrganizationTeamsOptions(
            enabled: true,
            teamMemberLimit: 2,
          ),
        ),
      );
      final owner = AuthUser(id: 'owner', email: 'owner@example.com');
      final organization = (await feature.createOrganization(
        context: Object(),
        user: owner,
        name: 'Acme',
        slug: 'acme',
      )).data;
      final team = (await store.listTeams(organization.id)).single;
      for (var index = 0; index < 8; index++) {
        await feature.trustedAddMember(
          context: Object(),
          actor: owner,
          organizationId: organization.id,
          userId: 'member-$index',
        );
      }
      final outcomes = await Future.wait(
        List.generate(8, (index) async {
          try {
            await feature.trustedAddTeamMember(
              context: Object(),
              actor: owner,
              teamId: team.id,
              userId: 'member-$index',
            );
            return 'ok';
          } on AuthFlowException catch (error) {
            return error.code;
          }
        }),
      );
      // The creator already occupies one of the two slots.
      expect(outcomes.where((value) => value == 'ok'), hasLength(1));
      expect(
        outcomes.where((value) => value == 'team_member_limit'),
        hasLength(7),
      );
      await _invoke(feature, 'organization.delete', owner, {
        'organizationId': organization.id,
      });
      expect(await store.findOrganization(organization.id), isNull);
      expect(await store.listMembers(organization.id), isEmpty);
      expect(await store.listTeams(organization.id), isEmpty);
      expect(await store.listTeamMembers(team.id), isEmpty);
    });

    test('before transforms and after failures return warnings', () async {
      final failures = <AuthOrganizationInternalFailure>[];
      final events = <AuthOrganizationLifecycleEvent>[];
      final feature = OrganizationPlugin<Object>(
        store: InMemoryAuthOrganizationStore(),
        options: AuthOrganizationOptions(
          hooks: AuthOrganizationHooks(
            beforeOrganization: (event) =>
                event.data.copyWith(name: event.data.name.toUpperCase()),
            afterOrganization: (_) => throw StateError('after failed'),
          ),
          reportFailure: failures.add,
          emitEvent: events.add,
        ),
      );
      final result = await feature.createOrganization(
        context: Object(),
        user: AuthUser(id: 'owner', email: 'owner@example.com'),
        name: 'Acme',
        slug: 'acme',
      );
      expect(result.data.name, 'ACME');
      expect(
        result.warnings.map((value) => value.code),
        contains('after_commit_hook_failed'),
      );
      expect(failures.single.error, isA<StateError>());
      expect(events.single.payload, isNot(contains('hookError')));
    });

    test(
      'reinvite reuses a pending action ID and delivery failure is committed',
      () async {
        final store = InMemoryAuthOrganizationStore();
        final failures = <AuthOrganizationInternalFailure>[];
        final events = <AuthOrganizationLifecycleEvent>[];
        var deliveries = 0;
        final feature = OrganizationPlugin<Object>(
          store: store,
          userStore: InMemoryAuthStore().users,
          options: AuthOrganizationOptions(
            sendInvitation: (_) {
              deliveries++;
              throw StateError('mail unavailable');
            },
            reportFailure: failures.add,
            emitEvent: events.add,
          ),
        );
        final owner = AuthUser(id: 'owner', email: 'owner@example.com');
        final organization = (await feature.createOrganization(
          context: Object(),
          user: owner,
          name: 'Acme',
          slug: 'acme',
        )).data;
        events.clear();

        final first = _map(
          await _invoke(feature, 'organization.inviteMember', owner, {
            'organizationId': organization.id,
            'email': 'invitee@example.com',
          }),
        );
        final second = _map(
          await _invoke(feature, 'organization.inviteMember', owner, {
            'organizationId': organization.id,
            'email': 'INVITEE@example.com',
          }),
        );
        expect(_map(first['data'])['id'], _map(second['data'])['id']);
        expect(deliveries, 2);
        expect(
          (first['warnings'] as List).map((value) => _map(value)['code']),
          contains('invitation_delivery_failed'),
        );
        expect(await store.listInvitations(organization.id), hasLength(1));
        expect(failures, hasLength(2));
        expect(events, hasLength(2));
        expect(
          events.every((event) => !event.payload.containsKey('id')),
          isTrue,
        );
      },
    );

    test('custom non-opaque invitation IDs require verified email', () async {
      final feature = OrganizationPlugin<Object>(
        store: InMemoryAuthOrganizationStore(),
        userStore: InMemoryAuthStore().users,
        options: const AuthOrganizationOptions(
          invitationIdGenerator: _predictableInvitationId,
        ),
      );
      final owner = AuthUser(id: 'owner', email: 'owner@example.com');
      final organization = (await feature.createOrganization(
        context: Object(),
        user: owner,
        name: 'Acme',
        slug: 'acme',
      )).data;
      final invited = AuthUser(id: 'invited', email: 'invited@example.com');
      final result = _map(
        await _invoke(feature, 'organization.inviteMember', owner, {
          'organizationId': organization.id,
          'email': invited.email,
        }),
      );
      final invitationId = _map(result['data'])['id'] as String;
      await expectLater(
        _invoke(feature, 'organization.acceptInvitation', invited, {
          'invitationId': invitationId,
        }),
        _flow('verified_email_required'),
      );
      await _invoke(feature, 'organization.acceptInvitation', invited, {
        'invitationId': invitationId,
      }, emailVerified: true);
    });

    test(
      'multi-role permissions union without leaking into global roles',
      () async {
        final feature = OrganizationPlugin<Object>(
          store: InMemoryAuthOrganizationStore(),
          options: const AuthOrganizationOptions(
            staticRoles: {
              'billing': {
                'invoice': ['read'],
              },
            },
          ),
        );
        final owner = AuthUser(id: 'owner', email: 'owner@example.com');
        final organization = (await feature.createOrganization(
          context: Object(),
          user: owner,
          name: 'Acme',
          slug: 'acme',
        )).data;
        await feature.trustedAddMember(
          context: Object(),
          actor: owner,
          organizationId: organization.id,
          userId: 'billing-user',
          roles: ['member', 'billing'],
        );
        expect(
          await feature.hasPermission(
            context: Object(),
            userId: 'billing-user',
            organizationId: organization.id,
            resource: 'invoice',
            action: 'read',
          ),
          isTrue,
        );
        expect(owner.roles, isEmpty);
        await expectLater(
          feature.hasPermission(
            context: Object(),
            userId: 'billing-user',
            organizationId: 'other-organization',
            resource: 'invoice',
            action: 'read',
          ),
          _flow('organization_not_found'),
        );
      },
    );
  });
}

String _predictableInvitationId() => 'predictable-id';

Future<Object?> _invoke(
  OrganizationPlugin<Object> feature,
  String id,
  AuthUser user,
  Map<String, dynamic> input, {
  bool emailVerified = false,
}) {
  final endpoint = feature.endpoints.singleWhere((value) => value.id == id);
  return Future.sync(
    () => endpoint.invoke(
      AuthOperationInvocation(
        context: Object(),
        user: user,
        emailVerified: emailVerified,
      ),
      input,
    ),
  );
}

Matcher _flow(String code) => throwsA(
  isA<AuthFlowException>().having((error) => error.code, 'code', code),
);

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

final class _EmptyPlugin implements AuthServerPlugin<Object> {
  @override
  String get id => 'empty';

  @override
  void configure(AuthServerPluginContext<Object> context) {}
}

final class _OrganizationStoreWithoutOwnershipCapability
    implements AuthOrganizationStore {
  _OrganizationStoreWithoutOwnershipCapability(
    this.organization,
    Iterable<AuthOrganizationMember> members,
  ) : _members = {for (final member in members) member.userId: member};

  final AuthOrganization organization;
  final Map<String, AuthOrganizationMember> _members;

  @override
  AuthOrganization? findOrganization(String organizationId) =>
      organizationId == organization.id ? organization : null;

  @override
  AuthOrganizationMember? findMember(String organizationId, String userId) =>
      organizationId == organization.id ? _members[userId] : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
