import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'organization client shares transport and sends explicit active IDs',
    () async {
      final requests = <http.Request>[];
      final plugin = const AuthOrganizationClientPlugin();
      final auth = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        bearerToken: 'jwt-1',
        plugins: [plugin],
        httpClient: MockClient((request) async {
          requests.add(request);
          switch (request.url.path) {
            case '/auth/csrf':
              return http.Response(
                jsonEncode({'csrfToken': 'csrf-1'}),
                200,
                headers: {'set-cookie': 'session=s1; Path=/; HttpOnly'},
              );
            case '/auth/organization/create':
              expect(request.headers['authorization'], 'Bearer jwt-1');
              expect(request.headers['cookie'], 'session=s1');
              expect(jsonDecode(request.body)['_csrf'], 'csrf-1');
              return http.Response(
                jsonEncode({
                  'data': _organizationJson,
                  'warnings': [
                    {'code': 'invitation_delivery_failed'},
                  ],
                }),
                200,
              );
            case '/auth/organization/get':
              expect(request.url.queryParameters['organizationId'], 'org-1');
              return http.Response(jsonEncode(_organizationJson), 200);
            case '/auth/organization/has-permission':
              expect(request.method, 'GET');
              expect(request.url.queryParameters['organizationId'], 'org-1');
              return http.Response(
                jsonEncode({'allowed': true, 'organizationId': 'org-1'}),
                200,
              );
            default:
              fail('Unexpected request: ${request.method} ${request.url}');
          }
        }),
      );
      final organizations = auth.plugins.use(plugin);

      final created = await organizations.create(name: 'Acme', slug: 'acme');
      expect(created.data.id, 'org-1');
      expect(created.warnings.single.code, 'invitation_delivery_failed');
      expect(organizations.activeOrganizationId, 'org-1');

      final current = await organizations.get();
      expect(current.slug, 'acme');
      expect(
        await organizations.hasPermission(
          resource: 'organization',
          action: 'delete',
        ),
        isTrue,
      );
      expect(
        requests.where((request) => request.url.path == '/auth/csrf'),
        hasLength(1),
      );
      expect(
        organizations.localRoleAllows(['member', 'admin'], 'member', 'update'),
        isTrue,
      );
    },
  );

  test(
    'transport refreshes CSRF once after an invalid token response',
    () async {
      var csrfCalls = 0;
      var mutations = 0;
      final transport = AuthClientTransport(
        baseUrl: Uri.parse('https://example.test'),
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/csrf') {
            csrfCalls++;
            return http.Response(
              jsonEncode({'csrfToken': 'csrf-$csrfCalls'}),
              200,
            );
          }
          mutations++;
          if (mutations == 1) {
            return http.Response(jsonEncode({'error': 'invalid_csrf'}), 403);
          }
          expect(jsonDecode(request.body)['_csrf'], 'csrf-2');
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );

      final response = await transport.mutate('POST', '/feature/action', {
        'value': 1,
      });
      expect(jsonDecode(response.body)['ok'], isTrue);
      expect(csrfCalls, 2);
      expect(mutations, 2);
    },
  );

  test(
    'leaving and removing a team clear matching active selections',
    () async {
      final plugin = const AuthOrganizationClientPlugin();
      final auth = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        plugins: [plugin],
        httpClient: MockClient((request) async {
          switch (request.url.path) {
            case '/auth/csrf':
              return http.Response(jsonEncode({'csrfToken': 'csrf-1'}), 200);
            case '/auth/organization/leave':
              expect(jsonDecode(request.body)['organizationId'], 'org-1');
              return http.Response(
                jsonEncode({'data': _memberJson, 'warnings': const []}),
                200,
              );
            case '/auth/organization/remove-team':
              expect(jsonDecode(request.body)['teamId'], 'team-1');
              return http.Response(
                jsonEncode({'data': _teamJson, 'warnings': const []}),
                200,
              );
            default:
              fail('Unexpected request: ${request.method} ${request.url}');
          }
        }),
      );
      final organizations = auth.plugins.use(plugin)
        ..activeOrganizationId = 'org-1'
        ..activeTeamId = 'team-1';

      await organizations.leave();
      expect(organizations.activeOrganizationId, isNull);
      expect(organizations.activeTeamId, isNull);

      organizations
        ..activeOrganizationId = 'org-1'
        ..activeTeamId = 'team-1';
      await organizations.removeTeam('team-1');
      expect(organizations.activeOrganizationId, 'org-1');
      expect(organizations.activeTeamId, isNull);
    },
  );
}

final Map<String, dynamic> _organizationJson = {
  'id': 'org-1',
  'name': 'Acme',
  'slug': 'acme',
  'logo': null,
  'metadata': <String, dynamic>{},
  'createdAt': '2030-01-01T00:00:00.000Z',
  'updatedAt': '2030-01-01T00:00:00.000Z',
};

final Map<String, dynamic> _memberJson = {
  'id': 'member-1',
  'organizationId': 'org-1',
  'userId': 'user-1',
  'roles': ['member'],
  'attributes': <String, dynamic>{},
  'createdAt': '2030-01-01T00:00:00.000Z',
};

final Map<String, dynamic> _teamJson = {
  'id': 'team-1',
  'organizationId': 'org-1',
  'name': 'Default',
  'attributes': <String, dynamic>{},
  'createdAt': '2030-01-01T00:00:00.000Z',
  'updatedAt': '2030-01-01T00:00:00.000Z',
};
