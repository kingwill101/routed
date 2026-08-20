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
  final mutationStore = store as AuthOrganizationMembershipMutationStore;
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
