import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  test('in-memory organization store preserves ownership atomically', () async {
    await verifyAuthOrganizationStoreOwnershipConformance(
      InMemoryAuthOrganizationStore(),
    );
  });
}
