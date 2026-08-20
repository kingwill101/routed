import 'dart:async';

import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'concurrent generated owner mutations always preserve an owner',
    () async {
      final runner = PropertyTestRunner<int>(Gen.integer(min: 0, max: 31), (
        shape,
      ) async {
        final store = InMemoryAuthOrganizationStore();
        final fixture = await _twoOwners(store, 'case-$shape');
        final first = _mutation(
          actor: fixture.first,
          target: shape.isEven ? fixture.first : fixture.second,
          remove: shape & 2 != 0,
        );
        final second = _mutation(
          actor: fixture.second,
          target: shape & 4 == 0 ? fixture.second : fixture.first,
          remove: shape & 8 != 0,
        );
        final operations = shape & 16 == 0 ? [first, second] : [second, first];
        final results = await Future.wait(
          operations.map(
            (mutation) =>
                _capture(() => store.mutateOrganizationMembership(mutation)),
          ),
        );

        expect(results.where((result) => result == null), hasLength(1));
        final members = await store.listMembers(fixture.organization.id);
        expect(
          members.where((member) => member.roles.contains('owner')),
          hasLength(1),
        );
      }, PropertyConfig(numTests: 256, seed: 20260820));

      final result = await runner.run();
      expect(
        result.success,
        isTrue,
        reason:
            'Property failed after ${result.numTests} cases: ${result.error}; '
            'input=${result.failingInput}; seed=${result.seed}',
      );
    },
  );
}

AuthOrganizationMembershipMutation _mutation({
  required AuthOrganizationMember actor,
  required AuthOrganizationMember target,
  required bool remove,
}) => AuthOrganizationMembershipMutation(
  kind: remove
      ? AuthOrganizationMembershipMutationKind.remove
      : AuthOrganizationMembershipMutationKind.replaceRoles,
  actorMembership: actor,
  targetMembership: target,
  creatorRole: 'owner',
  replacementRoles: remove ? null : const ['member'],
);

Future<String?> _capture(FutureOr<Object?> Function() operation) async {
  try {
    await Future.sync(operation);
    return null;
  } on AuthFlowException catch (error) {
    return error.code;
  }
}

Future<
  ({
    AuthOrganization organization,
    AuthOrganizationMember first,
    AuthOrganizationMember second,
  })
>
_twoOwners(InMemoryAuthOrganizationStore store, String namespace) async {
  final now = DateTime.utc(2030);
  final organization = AuthOrganization(
    id: '$namespace-organization',
    name: namespace,
    slug: namespace,
    createdAt: now,
    updatedAt: now,
  );
  final first = AuthOrganizationMember(
    id: '$namespace-member-1',
    organizationId: organization.id,
    userId: '$namespace-user-1',
    roles: const ['owner'],
    createdAt: now,
  );
  final second = AuthOrganizationMember(
    id: '$namespace-member-2',
    organizationId: organization.id,
    userId: '$namespace-user-2',
    roles: const ['owner'],
    createdAt: now,
  );
  await store.createOrganization(
    AuthOrganizationCreateTransaction(
      organization: organization,
      creatorMembership: first,
      organizationLimit: null,
    ),
  );
  await store.addMember(second);
  return (organization: organization, first: first, second: second);
}
