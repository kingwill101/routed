import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'admin client shares transport, CSRF state, bearer auth, and warnings',
    () async {
      final requests = <http.Request>[];
      final transport = AuthClientTransport(
        baseUrl: Uri.parse('https://example.test'),
        bearerToken: 'jwt-1',
        httpClient: MockClient((request) async {
          requests.add(request);
          switch (request.url.path) {
            case '/auth/csrf':
              return http.Response(
                jsonEncode({'csrfToken': 'csrf-1'}),
                200,
                headers: {'set-cookie': 'session=s1; Path=/; HttpOnly'},
              );
            case '/auth/admin/create-user':
              expect(request.headers['authorization'], 'Bearer jwt-1');
              expect(request.headers['cookie'], 'session=s1');
              expect(jsonDecode(request.body)['_csrf'], 'csrf-1');
              return http.Response(
                jsonEncode({
                  'data': _adminUser,
                  'warnings': [
                    {'code': 'after_hook_failed'},
                  ],
                }),
                200,
              );
            case '/auth/admin/list-users':
              expect(request.method, 'GET');
              expect(request.url.queryParameters['limit'], '20');
              return http.Response(
                jsonEncode({
                  'items': [_adminUser],
                  'total': 1,
                  'limit': 20,
                  'offset': 0,
                }),
                200,
              );
            case '/auth/admin/has-permission':
              return http.Response(jsonEncode({'allowed': true}), 200);
            default:
              fail('Unexpected request: ${request.method} ${request.url}');
          }
        }),
      );
      final client = AuthAdminClient(transport: transport);

      final created = await client.createUser(
        email: 'user@example.com',
        name: 'User',
        password: 'long-enough-password',
      );
      expect(created.data.user.id, 'user-1');
      expect(created.warnings.single.code, 'after_hook_failed');
      final page = await client.listUsers(limit: 20);
      expect(page.total, 1);
      expect(
        await client.hasPermission(resource: 'user', action: 'list'),
        isTrue,
      );
      expect(
        requests.where((request) => request.url.path == '/auth/csrf'),
        hasLength(1),
      );
      expect(client.localRoleAllows(['admin'], 'user', 'delete'), isTrue);
      expect(client.localRoleAllows(['user'], 'user', 'delete'), isFalse);
    },
  );
}

final Map<String, dynamic> _adminUser = {
  'id': 'user-1',
  'email': 'user@example.com',
  'name': 'User',
  'image': null,
  'roles': ['user'],
  'attributes': {},
  'userId': 'user-1',
  'banned': false,
  'banReason': null,
  'banExpiresAt': null,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
};
