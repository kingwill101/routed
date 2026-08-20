import 'dart:async';

import '../core/exceptions.dart';
import '../core/organization_models.dart';
import '../core/organization_store.dart';

/// A failed organization persistence-adapter conformance case.
final class AuthOrganizationStoreConformanceFailure implements Exception {
  const AuthOrganizationStoreConformanceFailure(this.caseId, this.cause);

  final String caseId;
  final Object cause;

  @override
  String toString() =>
      'AuthOrganizationStoreConformanceFailure($caseId): $cause';
}

/// Verifies the atomic owner-preservation contract of [store].
///
/// The supplied store must use an isolated namespace. The verifier creates
/// several organizations and intentionally submits stale and concurrent
/// ownership-bearing mutations. Durable adapters should run this verifier in
/// their own test suites.
Future<void> verifyAuthOrganizationStoreOwnershipConformance(
  AuthOrganizationStore store,
) async {
  if (store is! AuthOrganizationMembershipMutationStore) {
    throw const AuthOrganizationStoreConformanceFailure(
      'membership.capability',
      'AuthOrganizationMembershipMutationStore is required',
    );
  }
  if (store is! AuthOrganizationAtomicMutationStore) {
    throw const AuthOrganizationStoreConformanceFailure(
      'mutation.capability',
      'AuthOrganizationAtomicMutationStore is required',
    );
  }
  final mutationStore = store as AuthOrganizationMembershipMutationStore;
  final atomicStore = store as AuthOrganizationAtomicMutationStore;
  await _case('membership.concurrent-last-owner', () async {
    final fixture = await _twoOwners(store, 'concurrent');
    final results = await Future.wait([
      _capture(
        () => mutationStore.mutateOrganizationMembership(
          _demote(fixture.first, fixture.first),
        ),
      ),
      _capture(
        () => mutationStore.mutateOrganizationMembership(
          _demote(fixture.second, fixture.second),
        ),
      ),
    ]);
    _check(results.where((result) => result == null).length == 1, 'winners');
    final owners = (await store.listMembers(
      fixture.organization.id,
    )).where((member) => member.roles.contains('owner'));
    _check(owners.length == 1, 'owner count');
  });

  await _case('membership.stale-actor', () async {
    final fixture = await _twoOwners(store, 'stale-actor');
    await mutationStore.mutateOrganizationMembership(
      _demote(fixture.second, fixture.first),
    );
    final error = await _capture(
      () => mutationStore.mutateOrganizationMembership(
        AuthOrganizationMembershipMutation(
          kind: AuthOrganizationMembershipMutationKind.remove,
          actorMembership: fixture.first,
          targetMembership: fixture.second,
          creatorRole: 'owner',
        ),
      ),
    );
    _check(error == 'organization_forbidden', 'stale actor result');
    final remaining = await store.findMember(
      fixture.organization.id,
      fixture.second.userId,
    );
    _check(remaining?.roles.contains('owner') == true, 'remaining owner');
  });

  await _case('membership.failure-atomicity', () async {
    final fixture = await _oneOwner(store, 'rollback');
    final error = await _capture(
      () => mutationStore.mutateOrganizationMembership(
        AuthOrganizationMembershipMutation(
          kind: AuthOrganizationMembershipMutationKind.remove,
          actorMembership: fixture.owner,
          targetMembership: fixture.owner,
          creatorRole: 'owner',
        ),
      ),
    );
    _check(error == 'last_owner', 'failure code');
    final member = await store.findMember(
      fixture.organization.id,
      fixture.owner.userId,
    );
    _check(member?.roles.contains('owner') == true, 'owner rollback');
  });

  await _case('invitation.idempotent-retry-and-binding', () async {
    final fixture = await _oneOwner(store, 'invite-replay');
    final now = DateTime.utc(2030);
    final invitation = _invitation(
      fixture.organization.id,
      id: 'invite-replay-first',
      email: 'invitee@example.com',
      inviterId: fixture.owner.userId,
      now: now,
    );
    final idempotency = AuthOrganizationIdempotency(
      key: 'invite-replay-key',
      organizationId: fixture.organization.id,
      actorId: fixture.owner.userId,
      operationId: 'organization.inviteMember',
      fingerprint: 'fingerprint-a',
    );
    final first = await atomicStore.executeOrganizationMutation(
      AuthOrganizationCreateInvitationCommand(
        actorMembership: fixture.owner,
        invitation: invitation,
        invitationLimit: 1,
        replacePending: false,
        idempotency: idempotency,
      ),
    );
    final replay = await atomicStore.executeOrganizationMutation(
      AuthOrganizationCreateInvitationCommand(
        actorMembership: fixture.owner,
        invitation: _invitation(
          fixture.organization.id,
          id: 'invite-replay-second',
          email: 'invitee@example.com',
          inviterId: fixture.owner.userId,
          now: now,
        ),
        invitationLimit: 1,
        replacePending: false,
        idempotency: idempotency,
      ),
    );
    _check(replay.value.id == first.value.id, 'deterministic replay');
    final conflict = await _capture(
      () => atomicStore.executeOrganizationMutation(
        AuthOrganizationCreateInvitationCommand(
          actorMembership: fixture.owner,
          invitation: invitation,
          invitationLimit: 1,
          replacePending: false,
          idempotency: AuthOrganizationIdempotency(
            key: idempotency.key,
            organizationId: fixture.organization.id,
            actorId: fixture.owner.userId,
            operationId: 'organization.inviteMember',
            fingerprint: 'fingerprint-b',
          ),
        ),
      ),
    );
    _check(conflict == 'idempotency_key_conflict', 'binding conflict');
  });

  await _case('invitation.replace-failure-rollback', () async {
    final fixture = await _oneOwner(store, 'invite-rollback');
    final now = DateTime.utc(2030);
    final first = _invitation(
      fixture.organization.id,
      id: 'invite-rollback-first',
      email: 'first@example.com',
      inviterId: fixture.owner.userId,
      now: now,
    );
    final collision = _invitation(
      fixture.organization.id,
      id: 'invite-rollback-collision',
      email: 'second@example.com',
      inviterId: fixture.owner.userId,
      now: now,
    );
    await store.createInvitation(first);
    await store.createInvitation(collision);
    await store.transitionInvitation(
      collision.id,
      AuthOrganizationInvitationStatus.canceled,
      now: now,
    );
    final error = await _capture(
      () => atomicStore.executeOrganizationMutation(
        AuthOrganizationCreateInvitationCommand(
          actorMembership: fixture.owner,
          invitation: _invitation(
            fixture.organization.id,
            id: collision.id,
            email: first.email,
            inviterId: fixture.owner.userId,
            now: now,
          ),
          invitationLimit: null,
          replacePending: true,
          idempotency: AuthOrganizationIdempotency(
            key: 'invite-rollback-key',
            organizationId: fixture.organization.id,
            actorId: fixture.owner.userId,
            operationId: 'organization.inviteMember',
            fingerprint: 'rollback-fingerprint',
          ),
        ),
      ),
    );
    _check(error == 'invitation_exists', 'failure code');
    _check(
      (await store.findInvitation(first.id))?.status ==
          AuthOrganizationInvitationStatus.pending,
      'pending invitation rollback',
    );
  });

  await _case('team-member.concurrent-capacity', () async {
    final fixture = await _oneOwner(store, 'team-capacity');
    final now = DateTime.utc(2030);
    final first = AuthOrganizationMember(
      id: 'team-capacity-member-1',
      organizationId: fixture.organization.id,
      userId: 'team-capacity-user-2',
      roles: const ['member'],
      createdAt: now,
    );
    final second = AuthOrganizationMember(
      id: 'team-capacity-member-2',
      organizationId: fixture.organization.id,
      userId: 'team-capacity-user-3',
      roles: const ['member'],
      createdAt: now,
    );
    await store.addMember(first);
    await store.addMember(second);
    final team = AuthOrganizationTeam(
      id: 'team-capacity-team',
      organizationId: fixture.organization.id,
      name: 'Capacity',
      createdAt: now,
      updatedAt: now,
    );
    await store.createTeam(team);
    final outcomes = await Future.wait([
      _capture(
        () => atomicStore.executeOrganizationMutation(
          AuthOrganizationTeamMemberMutationCommand(
            kind: AuthOrganizationTeamMemberMutationKind.add,
            actorMembership: fixture.owner,
            team: team,
            teamMember: AuthOrganizationTeamMember(
              id: 'team-capacity-link-1',
              teamId: team.id,
              userId: first.userId,
              createdAt: now,
            ),
            memberLimit: 1,
            idempotency: _idempotency(
              'team-capacity-add-1',
              fixture,
              'organization.addTeamMember',
            ),
          ),
        ),
      ),
      _capture(
        () => atomicStore.executeOrganizationMutation(
          AuthOrganizationTeamMemberMutationCommand(
            kind: AuthOrganizationTeamMemberMutationKind.add,
            actorMembership: fixture.owner,
            team: team,
            teamMember: AuthOrganizationTeamMember(
              id: 'team-capacity-link-2',
              teamId: team.id,
              userId: second.userId,
              createdAt: now,
            ),
            memberLimit: 1,
            idempotency: _idempotency(
              'team-capacity-add-2',
              fixture,
              'organization.addTeamMember',
            ),
          ),
        ),
      ),
    ]);
    _check(outcomes.where((value) => value == null).length == 1, 'winner');
    _check((await store.listTeamMembers(team.id)).length == 1, 'capacity');
  });

  if (store case final AuthOrganizationUserDeletionStore deletionStore) {
    await _case('user-deletion.concurrent-last-owner', () async {
      final fixture = await _twoOwners(store, 'user-deletion');
      final results = await Future.wait([
        _capture(
          () => deletionStore.deleteUserData(
            fixture.first.userId,
            creatorRole: 'owner',
          ),
        ),
        _capture(
          () => deletionStore.deleteUserData(
            fixture.second.userId,
            creatorRole: 'owner',
          ),
        ),
      ]);
      _check(results.where((result) => result == null).length == 1, 'winners');
      final owners = (await store.listMembers(
        fixture.organization.id,
      )).where((member) => member.roles.contains('owner'));
      _check(owners.length == 1, 'owner count');
    });
  }
}

AuthOrganizationMembershipMutation _demote(
  AuthOrganizationMember actor,
  AuthOrganizationMember target,
) => AuthOrganizationMembershipMutation(
  kind: AuthOrganizationMembershipMutationKind.replaceRoles,
  actorMembership: actor,
  targetMembership: target,
  creatorRole: 'owner',
  replacementRoles: const ['member'],
);

AuthOrganizationInvitation _invitation(
  String organizationId, {
  required String id,
  required String email,
  required String inviterId,
  required DateTime now,
}) => AuthOrganizationInvitation(
  id: id,
  organizationId: organizationId,
  email: email,
  roles: const ['member'],
  inviterId: inviterId,
  status: AuthOrganizationInvitationStatus.pending,
  expiresAt: now.add(const Duration(days: 1)),
  createdAt: now,
);

AuthOrganizationIdempotency _idempotency(
  String key,
  ({AuthOrganization organization, AuthOrganizationMember owner}) fixture,
  String operationId,
) => AuthOrganizationIdempotency(
  key: key,
  organizationId: fixture.organization.id,
  actorId: fixture.owner.userId,
  operationId: operationId,
  fingerprint: key,
);

Future<String?> _capture(FutureOr<Object?> Function() operation) async {
  try {
    await Future.sync(operation);
    return null;
  } on AuthFlowException catch (error) {
    return error.code;
  }
}

Future<void> _case(String id, Future<void> Function() body) async {
  try {
    await body();
  } on AuthOrganizationStoreConformanceFailure {
    rethrow;
  } catch (error) {
    throw AuthOrganizationStoreConformanceFailure(id, error);
  }
}

void _check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

Future<
  ({
    AuthOrganization organization,
    AuthOrganizationMember first,
    AuthOrganizationMember second,
  })
>
_twoOwners(AuthOrganizationStore store, String namespace) async {
  final fixture = await _oneOwner(store, namespace);
  final second = AuthOrganizationMember(
    id: '$namespace-member-2',
    organizationId: fixture.organization.id,
    userId: '$namespace-user-2',
    roles: const ['owner'],
    createdAt: DateTime.utc(2030),
  );
  await store.addMember(second);
  return (
    organization: fixture.organization,
    first: fixture.owner,
    second: second,
  );
}

Future<({AuthOrganization organization, AuthOrganizationMember owner})>
_oneOwner(AuthOrganizationStore store, String namespace) async {
  final now = DateTime.utc(2030);
  final organization = AuthOrganization(
    id: '$namespace-organization',
    name: namespace,
    slug: namespace,
    createdAt: now,
    updatedAt: now,
  );
  final owner = AuthOrganizationMember(
    id: '$namespace-member-1',
    organizationId: organization.id,
    userId: '$namespace-user-1',
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
  return (organization: organization, owner: owner);
}
