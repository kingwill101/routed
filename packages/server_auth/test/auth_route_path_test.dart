import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

const _id = AuthRouteParameterKey('id');
const _tenant = AuthRouteParameterKey('tenant');
const _userRoute = AuthRoutePath(
  '/users/{id}',
  parameters: <AuthRouteParameterKey>[_id],
);

void main() {
  group('AuthRoutePath', () {
    test('accepts the canonical root route without parameters', () {
      const route = AuthRoutePath('/');

      expect(route.validate(), '/');
      expect(route.resolve(const {}), '/');
    });

    test('resolves an exact typed parameter set and encodes one segment', () {
      const hostile = 'team/a b?#%✓';
      final resolved = _userRoute.resolve(<AuthRouteParameterKey, String>{
        _id: hostile,
      });

      expect(resolved, '/users/team%2Fa%20b%3F%23%25%E2%9C%93');
      expect(Uri.parse(resolved).pathSegments, <String>['users', hostile]);
    });

    test('requires every parameter and rejects extras', () {
      expect(
        () => _userRoute.resolve(const <AuthRouteParameterKey, String>{}),
        throwsArgumentError,
      );
      expect(
        () => _userRoute.resolve(<AuthRouteParameterKey, String>{
          _id: 'user-1',
          _tenant: 'tenant-1',
        }),
        throwsArgumentError,
      );
      expect(
        () => _userRoute.resolve(<AuthRouteParameterKey, String>{_id: ''}),
        throwsArgumentError,
      );
      expect(
        () => _userRoute.bind(<String, Object?>{'id': ''}),
        throwsArgumentError,
      );
    });

    test('rejects invalid, missing, extra, and duplicate declarations', () {
      final invalid = <AuthRoutePath>[
        const AuthRoutePath('users/{id}', parameters: [_id]),
        const AuthRoutePath('/users/:id'),
        const AuthRoutePath('/users/prefix-{id}', parameters: [_id]),
        const AuthRoutePath('/users/{bad-name}'),
        const AuthRoutePath('/users/{id}', parameters: []),
        const AuthRoutePath('/users', parameters: [_id]),
        const AuthRoutePath('/users/{id}/{id}', parameters: [_id]),
        const AuthRoutePath('/users/{id}', parameters: [_id, _id]),
      ];

      for (final route in invalid) {
        expect(route.validate, throwsArgumentError, reason: route.template);
      }
    });

    test('hostile browser-shaped values remain one decoded segment', () async {
      final runner = PropertyTestRunner<String>(
        Gen.oneOf<String>(<String>[
          '../admin',
          'a/b',
          'a%2Fb',
          '%252e%252e%252f',
          ' ?#&=+',
          '<script>alert(1)</script>',
          '用户/✓',
          'x\r\nX-Injected: yes',
          'x' * 2048,
        ]),
        (value) {
          final resolved = _userRoute.resolve(<AuthRouteParameterKey, String>{
            _id: value,
          });
          final uri = Uri.parse(resolved);
          expect(uri.pathSegments, hasLength(2));
          expect(uri.pathSegments.last, value);
          expect(uri.hasQuery, isFalse);
          expect(uri.hasFragment, isFalse);
        },
        PropertyConfig(numTests: 500, seed: 20260820),
      );

      final result = await runner.run();
      expect(result.success, isTrue, reason: '${result.error}');
    });

    test('transport preserves host base paths and root mounts', () async {
      final transport = AuthClientTransport(
        baseUrl: Uri.parse('https://example.test/gateway'),
        basePath: '/auth',
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      final values = <AuthRouteParameterKey, String>{_id: 'a/b?c'};

      final auth = transport.endpoint(_userRoute, pathParameters: values);
      final root = transport.endpoint(
        _userRoute,
        pathParameters: values,
        mount: AuthEndpointMount.root,
      );

      expect(auth.path, '/gateway/auth/users/a%2Fb%3Fc');
      expect(root.path, '/gateway/users/a%2Fb%3Fc');
      expect(auth.pathSegments.last, 'a/b?c');
    });

    test('client encodes hostile parameter values as one path segment', () {
      final transport = AuthClientTransport(
        baseUrl: Uri.parse('https://example.test/gateway'),
        basePath: '/auth',
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      final cases = <String, String>{
        '/': '%2F',
        '%': '%25',
        '雪': '%E9%9B%AA',
        'what?where#fragment': 'what%3Fwhere%23fragment',
      };

      for (final entry in cases.entries) {
        final uri = transport.endpoint(
          _userRoute,
          pathParameters: <AuthRouteParameterKey, String>{_id: entry.key},
        );
        expect(uri.pathSegments.last, entry.key, reason: entry.key);
        expect(uri.path, endsWith('/users/${entry.value}'), reason: entry.key);
        expect(uri.hasQuery, isFalse, reason: entry.key);
        expect(uri.hasFragment, isFalse, reason: entry.key);
      }
    });

    test('client rejects URI dot segments before path normalization', () {
      final transport = AuthClientTransport(
        baseUrl: Uri.parse('https://example.test'),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(
        () => transport.endpoint(
          _userRoute,
          pathParameters: <AuthRouteParameterKey, String>{_id: '..'},
        ),
        throwsArgumentError,
      );
    });

    test('topology rejects equivalent dynamic route shapes', () {
      const userId = AuthRouteParameterKey('userId');
      final store = InMemoryAuthStore();

      expect(
        () => AuthRuntime<Object>(
          options: AuthOptions<Object>(
            providers: const <AuthProvider>[],
            store: store,
            storeMode: AuthStoreMode.ephemeral,
            plugins: const <AuthServerPlugin<Object>>[
              _RoutePlugin(
                id: 'first',
                endpointId: 'first.read',
                route: _userRoute,
              ),
              _RoutePlugin(
                id: 'second',
                endpointId: 'second.read',
                route: AuthRoutePath(
                  '/users/{userId}',
                  parameters: <AuthRouteParameterKey>[userId],
                ),
              ),
            ],
          ),
        ),
        throwsStateError,
      );
    });

    test(
      'topology validates every route and keys collisions by mount/method',
      () {
        final store = InMemoryAuthStore();
        expect(
          () => AuthRuntime<Object>(
            options: AuthOptions<Object>(
              providers: const <AuthProvider>[],
              store: store,
              storeMode: AuthStoreMode.ephemeral,
              plugins: const <AuthServerPlugin<Object>>[
                _RoutePlugin(
                  id: 'invalid',
                  endpointId: 'invalid.read',
                  route: AuthRoutePath('/users/{id}'),
                ),
              ],
            ),
          ),
          throwsArgumentError,
        );

        final runtime = AuthRuntime<Object>(
          options: AuthOptions<Object>(
            providers: const <AuthProvider>[],
            store: InMemoryAuthStore(),
            storeMode: AuthStoreMode.ephemeral,
            plugins: const <AuthServerPlugin<Object>>[
              _RoutePlugin(
                id: 'get-auth',
                endpointId: 'get-auth.read',
                route: _userRoute,
              ),
              _RoutePlugin(
                id: 'post-auth',
                endpointId: 'post-auth.write',
                route: _userRoute,
                method: AuthOperationMethod.post,
              ),
              _RoutePlugin(
                id: 'get-root',
                endpointId: 'get-root.read',
                route: _userRoute,
                mount: AuthEndpointMount.root,
              ),
            ],
          ),
        );
        expect(runtime.registry.endpoints, hasLength(3));
      },
    );
  });
}

final class _RoutePlugin
    implements AuthServerPlugin<Object>, AuthEndpointContributor<Object> {
  const _RoutePlugin({
    required this.id,
    required this.endpointId,
    required this.route,
    this.method = AuthOperationMethod.get,
    this.mount = AuthEndpointMount.auth,
  });

  @override
  final String id;
  final String endpointId;
  final AuthRoutePath route;
  final AuthOperationMethod method;
  final AuthEndpointMount mount;

  @override
  void configure(AuthServerPluginContext<Object> context) {}

  @override
  Iterable<AuthEndpointDescriptor<Object>> get endpoints => [
    TypedAuthEndpointDescriptor<Object, Map<String, dynamic>, Object?>(
      id: endpointId,
      method: method,
      path: route,
      mount: mount,
      semantics: method == AuthOperationMethod.get
          ? const AuthOperationSemantics.readOnly()
          : const AuthOperationSemantics.mutation(
              persistence: AuthMutationPersistence.external(),
              replaySafety: AuthMutationReplaySafety.repeatable,
            ),
      requestCodec: AuthOperationCodec<Map<String, dynamic>>(
        decode: (value) => value,
        encode: (value) => value,
      ),
      responseCodec: AuthOperationCodec<Object?>(
        decode: (value) => value,
        encode: (value) => value,
      ),
      handler: (_, _) => const <String, Object?>{'ok': true},
    ),
  ];
}
