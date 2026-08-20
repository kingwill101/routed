import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('anonymous users are typed, session-safe, and deletable', () async {
    final store = InMemoryAuthStore();
    final feature = AnonymousPlugin<Object>(generateName: (context) => 'Guest');
    final runtime = AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: const [],
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        plugins: [feature],
      ),
    );

    final result = await feature.signInAnonymous(context: Object());
    expect(result.user.isAnonymous, isTrue);
    expect(result.user.name, 'Guest');
    expect(result.user.toJson()['isAnonymous'], isTrue);
    final principal = result.user.toPrincipal();
    expect(AuthUser.fromPrincipal(principal).isAnonymous, isTrue);

    await feature.deleteAnonymousUser(user: result.user);
    expect(await store.users.findById(result.user.id), isNull);
    expect(
      runtime
          .registry
          .persistenceSchemas
          .single
          .entities
          .single
          .fields
          .single
          .name,
      'isAnonymous',
    );
  });

  test(
    'anonymous deletion rejects regular users and disabled deletion',
    () async {
      final store = InMemoryAuthStore();
      final regular = await store.users.create(
        AuthUser(id: 'user-1', email: 'user@example.com'),
      );
      final feature = AnonymousPlugin<Object>(disableDeleteAnonymousUser: true);
      AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: const [],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [feature],
        ),
      );

      await expectLater(
        feature.deleteAnonymousUser(user: regular),
        _flow('anonymous_required'),
      );
      final anonymous = (await feature.signInAnonymous(context: Object())).user;
      await expectLater(
        feature.deleteAnonymousUser(user: anonymous),
        _flow('anonymous_delete_disabled'),
      );
    },
  );

  test('link hook runs before the anonymous identity is removed', () async {
    final store = InMemoryAuthStore();
    AuthUser? linkedFrom;
    final feature = AnonymousPlugin<Object>(
      onLinkAccount:
          ({required context, required anonymousUser, required newUser}) {
            linkedFrom = anonymousUser;
          },
    );
    AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: const [],
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        plugins: [feature],
      ),
    );
    final anonymous = (await feature.signInAnonymous(context: Object())).user;
    final newUser = await store.users.create(
      AuthUser(id: 'user-2', email: 'ada@example.com'),
    );

    await feature.linkAnonymousAccount(
      context: Object(),
      anonymousUser: anonymous,
      newUser: newUser,
    );

    expect(linkedFrom?.id, anonymous.id);
    expect(await store.users.findById(anonymous.id), isNull);
    expect(await store.users.findById(newUser.id), isNotNull);
  });
}

Matcher _flow(String code) => throwsA(
  isA<AuthFlowException>().having((error) => error.code, 'code', code),
);
