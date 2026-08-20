import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  test('in-memory organization store preserves ownership atomically', () async {
    await verifyAuthOrganizationStoreOwnershipConformance(
      InMemoryAuthOrganizationStore(),
    );
  });

  test(
    'in-memory organization transactions roll back injected failures',
    () async {
      var inject = false;
      final store = InMemoryAuthOrganizationStore(
        failureInjector: (stage) {
          if (inject && stage == 'team.delete.after-members') {
            throw StateError('injected');
          }
        },
      );
      final now = DateTime.utc(2030);
      final organization = AuthOrganization(
        id: 'rollback-organization',
        name: 'Rollback',
        slug: 'rollback',
        createdAt: now,
        updatedAt: now,
      );
      final owner = AuthOrganizationMember(
        id: 'rollback-owner',
        organizationId: organization.id,
        userId: 'rollback-user',
        roles: const ['owner'],
        createdAt: now,
      );
      await store.createOrganization(
        AuthOrganizationCreateTransaction(
          organization: organization,
          creatorMembership: owner,
          organizationLimit: null,
        ),
      );
      final first = AuthOrganizationTeam(
        id: 'rollback-team-first',
        organizationId: organization.id,
        name: 'First',
        createdAt: now,
        updatedAt: now,
      );
      final second = AuthOrganizationTeam(
        id: 'rollback-team-second',
        organizationId: organization.id,
        name: 'Second',
        createdAt: now,
        updatedAt: now,
      );
      await store.createTeam(first);
      await store.createTeam(second);
      await store.addTeamMember(
        AuthOrganizationTeamMember(
          id: 'rollback-team-member',
          teamId: second.id,
          userId: owner.userId,
          createdAt: now,
        ),
      );
      await store.createInvitation(
        AuthOrganizationInvitation(
          id: 'rollback-invitation',
          organizationId: organization.id,
          email: 'invitee@example.com',
          roles: const ['member'],
          inviterId: owner.userId,
          status: AuthOrganizationInvitationStatus.pending,
          expiresAt: now.add(const Duration(days: 1)),
          createdAt: now,
          teamId: second.id,
        ),
      );

      inject = true;
      await expectLater(
        store.executeOrganizationMutation(
          AuthOrganizationTeamMutationCommand(
            kind: AuthOrganizationTeamMutationKind.delete,
            actorMembership: owner,
            team: second,
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(await store.findTeam(second.id), same(second));
      expect(await store.listTeamMembers(second.id), hasLength(1));
      expect(
        (await store.findInvitation('rollback-invitation'))?.teamId,
        second.id,
      );
    },
  );
}
