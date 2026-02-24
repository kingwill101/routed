import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('registerDefaultAuthProviders registers built-in providers', () {
    registerDefaultAuthProviders();

    final registry = AuthProviderRegistry.instance;
    expect(registry.getEntry('google'), isNotNull);
    expect(registry.getEntry('github'), isNotNull);
    expect(registry.getEntry('telegram'), isNotNull);
  });
}
