import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('authPrincipalAttribute remains stable', () {
    expect(authPrincipalAttribute, equals('auth.principal'));
  });

  test('InMemoryRememberTokenStore saves and reads principals', () async {
    final store = InMemoryRememberTokenStore();
    final principal = AuthPrincipal(id: 'user-1', roles: const ['admin']);
    final expiry = DateTime.now().add(const Duration(minutes: 5));

    await store.save('token-1', principal, expiry);
    final restored = await store.read('token-1');

    expect(restored, isNotNull);
    expect(restored!.id, equals('user-1'));
    expect(restored.roles, contains('admin'));
  });

  test('InMemoryRememberTokenStore evicts expired tokens', () async {
    final store = InMemoryRememberTokenStore();
    final principal = AuthPrincipal(id: 'user-2', roles: const ['user']);
    final expiry = DateTime.now().subtract(const Duration(seconds: 1));

    await store.save('expired', principal, expiry);
    final restored = await store.read('expired');

    expect(restored, isNull);
  });
}
