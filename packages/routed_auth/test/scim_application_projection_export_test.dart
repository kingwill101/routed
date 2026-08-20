import 'package:routed_auth/routed_auth.dart';
import 'package:test/test.dart';

void main() {
  test('reexports the server-neutral SCIM application projection API', () {
    final scope = AuthScimApplicationProjectionScope(
      connectionId: 'connection-a',
      tenantId: 'tenant-a',
      organizationId: 'organization-a',
      provisioningDomainId: 'domain-a',
    );
    final subject = AuthScimApplicationProjectionSubject(
      scope: scope,
      resourceId: 'directory-user-a',
      kind: AuthScimApplicationSubjectKind.user,
    );
    final store = InMemoryAuthScimApplicationProjectionStore();

    expect(subject.scope, scope);
    expect(store, isA<AuthScimApplicationProjectionStore>());
    expect(store, isNot(isA<AuthStore>()));
  });
}
