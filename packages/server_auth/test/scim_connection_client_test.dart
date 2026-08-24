import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'managed SCIM client is installed only through its client plugin',
    () async {
      final requests = <http.Request>[];
      const plugin = AuthScimConnectionClientPlugin();
      final auth = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        plugins: <AuthClientPlugin<dynamic>>[plugin],
        httpClient: MockClient((request) async {
          requests.add(request);
          switch (request.url.path) {
            case '/auth/csrf':
              return http.Response(
                jsonEncode(<String, Object?>{'csrfToken': 'csrf-1'}),
                200,
              );
            case '/auth/scim/connections/create':
              expect(request.method, 'POST');
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              expect(body['organizationId'], 'organization-a');
              expect(body['idempotencyKey'], 'create-1');
              expect(body['_csrf'], 'csrf-1');
              return http.Response(jsonEncode(_creationJson), 200);
            case '/auth/scim/connections':
              expect(request.method, 'GET');
              expect(
                request.url.queryParameters['organizationId'],
                'organization-a',
              );
              return http.Response(
                jsonEncode(<String, Object?>{
                  'items': <Object?>[_connectionJson],
                  'total': 1,
                  'limit': 10,
                  'offset': 0,
                }),
                200,
              );
            case '/auth/scim/connections/credentials/rotate':
              expect(request.method, 'POST');
              return http.Response(jsonEncode(_issuanceJson), 200);
            default:
              fail('Unexpected request: ${request.method} ${request.url}');
          }
        }),
      );
      final connections = auth.plugins.use(plugin);

      final created = await connections.create(
        organizationId: 'organization-a',
        name: 'Directory',
        provisioningDomainId: 'employees',
        scopes: const <AuthScimScope>[AuthScimScope.usersWrite],
        credentialName: 'Primary',
        idempotencyKey: 'create-1',
      );
      expect(created.connection.id, 'connection-a');
      expect(created.issuance.secret, 'rscim.credential-a.raw-secret');

      final page = await connections.list(
        organizationId: 'organization-a',
        limit: 10,
      );
      expect(page.items.single.id, created.connection.id);

      final rotated = await connections.rotateCredential(
        organizationId: 'organization-a',
        connectionId: created.connection.id,
        credentialId: created.issuance.credential.id,
        name: 'Replacement',
        scopes: const <AuthScimScope>[AuthScimScope.usersRead],
        idempotencyKey: 'rotate-1',
      );
      expect(rotated.credential.id, 'credential-a');
      expect(
        requests.where((request) => request.url.path == '/auth/csrf'),
        hasLength(1),
      );
    },
  );
}

final DateTime _now = DateTime.utc(2030);

final Map<String, Object?> _connectionJson = <String, Object?>{
  'id': 'connection-a',
  'tenantId': 'tenant-a',
  'organizationId': 'organization-a',
  'provisioningDomainId': 'employees',
  'subjectId': 'user-a',
  'name': 'Directory',
  'scopes': <String>['usersWrite'],
  'state': 'active',
  'createdAt': _now.toIso8601String(),
  'updatedAt': _now.toIso8601String(),
};

final Map<String, Object?> _credentialJson = <String, Object?>{
  'id': 'credential-a',
  'connectionId': 'connection-a',
  'name': 'Primary',
  'keyPrefix': 'rscim.credenti',
  'scopes': <String>['usersWrite'],
  'active': true,
  'createdAt': _now.toIso8601String(),
  'updatedAt': _now.toIso8601String(),
  'expiresAt': _now.add(const Duration(days: 90)).toIso8601String(),
};

final Map<String, Object?> _issuanceJson = <String, Object?>{
  'credential': _credentialJson,
  'replayed': false,
  'secret': 'rscim.credential-a.raw-secret',
};

final Map<String, Object?> _creationJson = <String, Object?>{
  'connection': _connectionJson,
  'issuance': _issuanceJson,
};
