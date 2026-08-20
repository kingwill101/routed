import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  test('in-memory backend passes public two-factor conformance', () async {
    await verifyAuthTwoFactorBackendConformance(
      InMemoryAuthTwoFactorBackend.new,
    );
  });
}
