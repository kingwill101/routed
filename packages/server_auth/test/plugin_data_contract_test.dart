import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('AuthServerPluginDataContract', () {
    test(
      'requires an inventory declaration for a plugin-owned login method',
      () {
        final plugin = _InventoryPlugin(
          contract: const AuthServerPluginDataContract.none(),
        );

        expect(() => _freeze(plugin), throwsA(isA<StateError>()));
      },
    );

    test('requires a deletion declaration for plugin-owned user data', () {
      final plugin = _DeletionPlugin(
        contract: const AuthServerPluginDataContract.none(),
      );

      expect(() => _freeze(plugin), throwsA(isA<StateError>()));
    });

    test('requires removal routes to be recent-authenticated mutations', () {
      final plugin = _InventoryPlugin(
        contract: const AuthServerPluginDataContract(
          authenticationMethodNamespace: 'external_device',
          removalEndpointIds: <String>['external_device.remove'],
        ),
        recentAuthentication: false,
      );

      expect(() => _freeze(plugin), throwsA(isA<StateError>()));
    });

    test('accepts a complete external plugin topology', () {
      final plugin = _InventoryPlugin(
        contract: const AuthServerPluginDataContract(
          authenticationMethodNamespace: 'external_device',
          removalEndpointIds: <String>['external_device.remove'],
        ),
      );

      final registry = _freeze(plugin);

      expect(registry.isFrozen, isTrue);
      expect(
        registry.pluginIdForEndpoint('external_device.remove'),
        'external',
      );
    });

    test('allows plugins with no user-owned auth data to declare none', () {
      final registry = _freeze(_EmptyPlugin());

      expect(registry.isFrozen, isTrue);
    });
  });
}

AuthServerPluginRegistry<Object> _freeze(AuthServerPlugin<Object> plugin) {
  final store = InMemoryAuthStore();
  final registry = AuthServerPluginRegistry<Object>(
    store: store,
    authenticationMethods: AuthAuthenticationMethodService(store: store),
  );
  registry.register(plugin);
  registry.freeze();
  return registry;
}

final class _EmptyPlugin implements AuthServerPlugin<Object> {
  @override
  String get id => 'empty';

  @override
  AuthServerPluginDataContract get dataContract =>
      const AuthServerPluginDataContract.none();

  @override
  void configure(AuthServerPluginContext<Object> context) {}
}

final class _InventoryPlugin
    implements
        AuthServerPlugin<Object>,
        AuthEndpointContributor<Object>,
        AuthAuthenticationMethodInventoryContributor {
  _InventoryPlugin({required this.contract, this.recentAuthentication = true});

  final AuthServerPluginDataContract contract;
  final bool recentAuthentication;

  @override
  String get id => 'external';

  @override
  AuthServerPluginDataContract get dataContract => contract;

  @override
  String get authenticationMethodNamespace => 'external_device';

  @override
  AuthAuthenticationMethodSnapshot authenticationMethodsForUser(
    String userId,
  ) => AuthAuthenticationMethodSnapshot.complete(const []);

  @override
  void configure(AuthServerPluginContext<Object> context) {}

  @override
  Iterable<AuthEndpointDescriptor<Object>> get endpoints => [
    TypedAuthEndpointDescriptor<Object, Map<String, dynamic>, Object?>(
      id: 'external_device.remove',
      method: AuthOperationMethod.post,
      path: const AuthRoutePath('/external-device/remove'),
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
        ),
        replaySafety: AuthMutationReplaySafety.idempotent,
      ),
      requestCodec: AuthOperationCodec<Map<String, dynamic>>(
        decode: (value) => value,
        encode: (value) => value,
      ),
      responseCodec: AuthOperationCodec<Object?>(
        decode: (value) => value,
        encode: (value) => value,
      ),
      csrfPolicy: AuthOperationCsrfPolicy.required,
      requiresRecentAuthentication: recentAuthentication,
      handler: (_, _) => const <String, dynamic>{'status': 'removed'},
    ),
  ];
}

final class _DeletionPlugin
    implements AuthServerPlugin<Object>, AuthUserDeletionPlanContributor {
  _DeletionPlugin({required this.contract});

  final AuthServerPluginDataContract contract;

  @override
  String get id => 'external_data';

  @override
  AuthServerPluginDataContract get dataContract => contract;

  @override
  String get userDataNamespace => 'external_data';

  @override
  void configure(AuthServerPluginContext<Object> context) {}

  @override
  AuthUserDeletionPlan createUserDeletionPlan(AuthUser user) =>
      AuthNoopUserDeletionPlan(
        domain: AuthInMemoryUserDeletionDomain(),
        userId: user.id,
        namespace: userDataNamespace,
      );
}
