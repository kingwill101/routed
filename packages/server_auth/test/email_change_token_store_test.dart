import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('email-change tokens are digest-backed, one-time, and user-bound', () async {
    final store = InMemoryAuthEmailChangeTokenStore();
    await store.save(
      AuthEmailChangeToken(
        userId: 'user-1',
        newEmail: 'new@example.com',
        token: 'raw-token',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      ),
    );

    final consumed = await store.consume('raw-token');
    expect(consumed?.userId, equals('user-1'));
    expect(consumed?.newEmail, equals('new@example.com'));
    expect(await store.consume('raw-token'), isNull);
  });

  test('email updates preserve uniqueness and canonical casing', () async {
    final store = InMemoryAuthStore();
    await store.users.create(AuthUser(id: 'user-1', email: 'old@example.com'));
    await store.users.create(AuthUser(id: 'user-2', email: 'taken@example.com'));

    final updated = await store.users.updateEmailForUser(
      'user-1',
      '  New@Example.com ',
    );
    expect(updated?.email, equals('new@example.com'));
    expect(await store.users.findByEmail('old@example.com'), isNull);
    expect(
      await store.users.updateEmailForUser('user-1', 'taken@example.com'),
      isNull,
    );
  });
}
