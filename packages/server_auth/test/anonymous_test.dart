import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('anonymous deletion declares browser Origin and CSRF protection', () {
    final endpoint = AnonymousPlugin<Object>().endpoints.singleWhere(
      (endpoint) => endpoint.id == 'anonymous.delete',
    );
    expect(endpoint.authentication, AuthOperationAuthentication.session);
    expect(endpoint.originPolicy, AuthOperationOriginPolicy.browser);
    expect(endpoint.csrfPolicy, AuthOperationCsrfPolicy.required);
  });

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

  test(
    'upgrade finalization atomically removes the anonymous identity',
    () async {
      final store = InMemoryAuthStore();
      final feature = AnonymousPlugin<Object>();
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

      await feature.completeAnonymousAccountUpgrade(
        anonymousUser: anonymous,
        targetUser: newUser,
      );

      expect(await store.users.findById(anonymous.id), isNull);
      expect(await store.users.findById(newUser.id), isNotNull);
    },
  );

  test(
    'upgrade rejects anonymous targets without mutating its source',
    () async {
      final store = InMemoryAuthStore();
      final feature = AnonymousPlugin<Object>();
      AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: const [],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [feature],
        ),
      );
      final source = (await feature.signInAnonymous(context: Object())).user;

      await expectLater(
        feature.completeAnonymousAccountUpgrade(
          anonymousUser: source,
          targetUser: AuthUser(id: 'other-anonymous', isAnonymous: true),
        ),
        _flow('anonymous_link_unavailable'),
      );
      expect(await store.users.findById(source.id), isNotNull);
    },
  );

  test('configuration fails closed without an atomic mutation store', () {
    final store = _CoreOnlyStore(InMemoryAuthStore());
    expect(
      () => AnonymousPlugin<Object>().configure(
        AuthServerPluginContext<Object>(store: store),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('AuthAnonymousAccountMutationStore'),
        ),
      ),
    );
  });
}

Matcher _flow(String code) => throwsA(
  isA<AuthFlowException>().having((error) => error.code, 'code', code),
);

final class _CoreOnlyStore implements AuthStore {
  _CoreOnlyStore(this.delegate);

  final AuthStore delegate;

  @override
  AuthAccountStore get accounts => delegate.accounts;
  @override
  AuthCredentialStore get credentials => delegate.credentials;
  @override
  AuthDeviceAuthorizationStore get deviceAuthorizations =>
      delegate.deviceAuthorizations;
  @override
  AuthEmailChangeTokenStore get emailChangeTokens => delegate.emailChangeTokens;
  @override
  AuthEmailOtpStore get emailOtps => delegate.emailOtps;
  @override
  AuthJwtVersionStore get jwtVersions => delegate.jwtVersions;
  @override
  AuthOAuthChallengeStore get oauthChallenges => delegate.oauthChallenges;
  @override
  AuthPasswordResetTokenStore get passwordResetTokens =>
      delegate.passwordResetTokens;
  @override
  AuthSessionStore get sessions => delegate.sessions;
  @override
  AuthUserStore get users => delegate.users;
  @override
  AuthVerificationTokenStore get verificationTokens =>
      delegate.verificationTokens;
}
