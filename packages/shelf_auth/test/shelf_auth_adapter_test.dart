import 'dart:convert';

import 'package:server_auth/server_auth.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_auth/shelf_auth.dart';
import 'package:test/test.dart';

void main() {
  group('bearerToken', () {
    test('extracts bearer token', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/'),
        headers: const <String, String>{'authorization': 'Bearer abc123'},
      );

      expect(bearerToken(request), 'abc123');
    });

    test('extracts lowercase bearer token', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/'),
        headers: const <String, String>{'authorization': 'bearer abc123'},
      );

      expect(bearerToken(request), 'abc123');
    });

    test('returns null for non-bearer authorization header', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/'),
        headers: const <String, String>{'authorization': 'Basic xyz'},
      );

      expect(bearerToken(request), isNull);
    });
  });

  group('bearerAuth', () {
    test('strict mode rejects missing token', () async {
      final handler = const Pipeline()
          .addMiddleware(
            bearerAuth(strict: true, resolvePrincipal: (_, _) => null),
          )
          .addHandler((_) => Response.ok('ok'));

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/')),
      );
      expect(response.statusCode, 401);
      expect(await response.readAsString(), contains('missing_bearer_token'));
    });

    test('stores principal in request context when token resolves', () async {
      final principal = AuthPrincipal(
        id: 'user-1',
        roles: const <String>['admin'],
      );
      final handler = const Pipeline()
          .addMiddleware(
            bearerAuth(
              strict: true,
              resolvePrincipal: (token, _) {
                if (token == 'good-token') {
                  return principal;
                }
                return null;
              },
            ),
          )
          .addHandler((request) {
            final current = authPrincipal(request);
            if (current == null) {
              return Response.internalServerError(body: 'missing principal');
            }
            return Response.ok(current.id);
          });

      final response = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/'),
          headers: const <String, String>{'authorization': 'Bearer good-token'},
        ),
      );

      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'user-1');
    });

    test('non-strict mode falls through for invalid token', () async {
      final handler = const Pipeline()
          .addMiddleware(
            bearerAuth(strict: false, resolvePrincipal: (_, _) => null),
          )
          .addHandler((_) => Response.ok('anonymous'));

      final response = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/'),
          headers: const <String, String>{'authorization': 'Bearer bad-token'},
        ),
      );

      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'anonymous');
    });
  });

  group('authProvidersEndpoint', () {
    test('serves providers at configured path', () async {
      final providers = <AuthProvider>[
        AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
      ];

      final handler = const Pipeline()
          .addMiddleware(authProvidersEndpoint(providers: providers))
          .addHandler((_) => Response.notFound('not found'));

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/auth/providers')),
      );

      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final list = body['providers'] as List<dynamic>;
      expect(list, hasLength(1));
      expect((list.first as Map<String, dynamic>)['id'], 'google');
    });

    test('falls through when path does not match', () async {
      final handler = const Pipeline()
          .addMiddleware(
            authProvidersEndpoint(providers: const <AuthProvider>[]),
          )
          .addHandler((_) => Response.notFound('missing'));

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/other')),
      );

      expect(response.statusCode, 404);
      expect(await response.readAsString(), 'missing');
    });
  });

  group('requireAuthenticated', () {
    test('rejects when principal is missing', () async {
      final handler = const Pipeline()
          .addMiddleware(requireAuthenticated())
          .addHandler((_) => Response.ok('ok'));

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/me')),
      );

      expect(response.statusCode, 401);
      expect(
        await response.readAsString(),
        contains('authentication_required'),
      );
    });

    test('passes when principal exists', () async {
      final handler = const Pipeline()
          .addMiddleware((inner) {
            return (request) => inner(
              request.change(
                context: <String, Object>{
                  ...request.context,
                  shelfAuthPrincipalContextKey: AuthPrincipal(id: 'user-1'),
                },
              ),
            );
          })
          .addMiddleware(requireAuthenticated())
          .addHandler((request) {
            final principal = authPrincipal(request);
            return Response.ok(principal?.id ?? 'missing');
          });

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/me')),
      );

      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'user-1');
    });
  });

  group('requireRoles', () {
    test('rejects unauthenticated requests', () async {
      final handler = const Pipeline()
          .addMiddleware(requireRoles(<String>['admin']))
          .addHandler((_) => Response.ok('ok'));

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/admin')),
      );

      expect(response.statusCode, 401);
    });

    test('rejects authenticated principal without required role', () async {
      final handler = const Pipeline()
          .addMiddleware((inner) {
            return (request) => inner(
              request.change(
                context: <String, Object>{
                  ...request.context,
                  shelfAuthPrincipalContextKey: AuthPrincipal(
                    id: 'user-1',
                    roles: const <String>['user'],
                  ),
                },
              ),
            );
          })
          .addMiddleware(requireRoles(<String>['admin']))
          .addHandler((_) => Response.ok('ok'));

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/admin')),
      );

      expect(response.statusCode, 403);
      expect(await response.readAsString(), contains('insufficient_role'));
    });

    test('passes when principal satisfies all required roles', () async {
      final handler = const Pipeline()
          .addMiddleware((inner) {
            return (request) => inner(
              request.change(
                context: <String, Object>{
                  ...request.context,
                  shelfAuthPrincipalContextKey: AuthPrincipal(
                    id: 'user-1',
                    roles: const <String>['admin', 'editor'],
                  ),
                },
              ),
            );
          })
          .addMiddleware(requireRoles(<String>['admin', 'editor']))
          .addHandler((_) => Response.ok('ok'));

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/admin')),
      );

      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'ok');
    });

    test('passes with any=true when one role matches', () async {
      final handler = const Pipeline()
          .addMiddleware((inner) {
            return (request) => inner(
              request.change(
                context: <String, Object>{
                  ...request.context,
                  shelfAuthPrincipalContextKey: AuthPrincipal(
                    id: 'user-1',
                    roles: const <String>['editor'],
                  ),
                },
              ),
            );
          })
          .addMiddleware(requireRoles(<String>['admin', 'editor'], any: true))
          .addHandler((_) => Response.ok('ok'));

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/admin')),
      );

      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'ok');
    });
  });
}
