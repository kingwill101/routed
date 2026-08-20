import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'in-memory username store satisfies public atomic conformance',
    () async {
      AuthUsernameFaultPoint? armed;
      final store = InMemoryAuthStore(
        usernameFaultInjector: (point) {
          if (point == armed) {
            armed = null;
            throw StateError('injected conformance fault');
          }
        },
      );
      await verifyAuthUsernameStoreConformance(
        AuthUsernameStoreConformanceFixture(
          store: store,
          armFault: (point) => armed = point,
        ),
      );
    },
  );
}
