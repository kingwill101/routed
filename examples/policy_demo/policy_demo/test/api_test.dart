import 'dart:io';

import 'package:policy_demo/app.dart' show createEngine;
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

const _sessionCookieName = 'policy_session';
const _csrfCookieName = 'csrf_token';

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

class _CsrfContext {
  const _CsrfContext({required this.session, required this.token});

  final Cookie session;
  final String token;
}

Future<_CsrfContext> _csrfContext(TestClient client, {Cookie? session}) async {
  final response = await client.get(
    '/api/v1/csrf',
    headers: session == null
        ? null
        : {
            HttpHeaders.cookieHeader: [_cookieHeader(session)],
          },
  );
  response.assertStatus(HttpStatus.ok);
  final json = response.json() as Map<String, dynamic>;
  final token = json['csrfToken']?.toString() ?? '';
  final setCookies = response.headers.entries
      .where((entry) => entry.key.toLowerCase() == HttpHeaders.setCookieHeader)
      .expand((entry) => entry.value)
      .toList();
  Cookie? sessionCookie = response.cookie(_sessionCookieName) ?? session;
  Cookie? csrfCookie = response.cookie(_csrfCookieName);
  for (final cookieStr in setCookies) {
    try {
      final parsed = Cookie.fromSetCookieValue(cookieStr);
      if (parsed.name == _sessionCookieName) {
        sessionCookie = parsed;
      }
      if (parsed.name == _csrfCookieName) {
        csrfCookie = parsed;
      }
    } catch (_) {}
  }
  expect(sessionCookie, isNotNull);
  expect(token, isNotEmpty);
  return _CsrfContext(
    session: sessionCookie!,
    token: csrfCookie?.value ?? token,
  );
}

Map<String, List<String>> _csrfHeaders(_CsrfContext context) {
  return {
    HttpHeaders.cookieHeader: [
      '${_cookieHeader(context.session)}; $_csrfCookieName=${context.token}',
    ],
    'x-csrf-token': [context.token],
  };
}

Future<Cookie> _login(
  TestClient client, {
  required _CsrfContext csrf,
  String id = 'ada',
}) async {
  final response = await client.postJson('/api/v1/login', {
    'id': id,
    'role': 'editor',
  }, headers: _csrfHeaders(csrf));
  response.assertStatus(HttpStatus.ok);
  final cookie = response.cookie(_sessionCookieName) ?? csrf.session;
  return cookie;
}

void main() {
  group('API', () {
    late Engine engine;
    late TestClient client;

    setUpAll(() async {
      engine = await createEngine();
      client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
    });

    tearDownAll(() async {
      await client.close();
      await engine.close();
    });

    test('health check returns ok', () async {
      final response = await client.get('/api/v1/health');
      response.assertStatus(HttpStatus.ok);
      final json = response.json() as Map<String, dynamic>;
      expect(json['status'], equals('ok'));
    });

    test('users endpoints return data', () async {
      final listResponse = await client.get('/api/v1/users');
      listResponse.assertStatus(HttpStatus.ok);
      final listJson = listResponse.json() as Map<String, dynamic>;
      expect(listJson['data'], isA<List>());

      final showResponse = await client.get('/api/v1/users/1');
      showResponse.assertStatus(HttpStatus.ok);
      final showJson = showResponse.json() as Map<String, dynamic>;
      expect(showJson['id'], equals('1'));

      final csrf = await _csrfContext(client);
      final createResponse = await client.postJson('/api/v1/users', {
        'name': 'Grace',
        'email': 'grace@example.com',
      }, headers: _csrfHeaders(csrf));
      createResponse.assertStatus(HttpStatus.created);
      final createdJson = createResponse.json() as Map<String, dynamic>;
      expect(createdJson['name'], equals('Grace'));
    });

    test('project policies enforce access', () async {
      final unauthProjects = await client.get('/api/v1/projects');
      unauthProjects.assertStatus(HttpStatus.ok);
      final unauthJson = unauthProjects.json() as Map<String, dynamic>;
      expect(unauthJson['data'], isEmpty);

      var csrf = await _csrfContext(client);
      final forbiddenCreate = await client.postJson('/api/v1/projects', {
        'name': 'Unauthorized',
      }, headers: _csrfHeaders(csrf));
      forbiddenCreate.assertStatus(HttpStatus.forbidden);

      final cookie = await _login(client, csrf: csrf);
      csrf = await _csrfContext(client, session: cookie);

      final meResponse = await client.get(
        '/api/v1/me',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(cookie)],
        },
      );
      meResponse.assertStatus(HttpStatus.ok);
      final meJson = meResponse.json() as Map<String, dynamic>;
      expect(meJson['principal']['id'], equals('ada'));

      final projectsResponse = await client.get(
        '/api/v1/projects',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(cookie)],
        },
      );
      projectsResponse.assertStatus(HttpStatus.ok);
      final projectsJson = projectsResponse.json() as Map<String, dynamic>;
      expect(projectsJson['data'], isA<List>());
      expect(projectsJson['data'].length, equals(1));

      final createProject = await client.postJson('/api/v1/projects', {
        'name': 'Analytical Engine',
      }, headers: _csrfHeaders(csrf));
      createProject.assertStatus(HttpStatus.created);
      final projectJson = createProject.json() as Map<String, dynamic>;
      expect(projectJson['ownerId'], equals('ada'));

      final showProject = await client.get(
        '/api/v1/projects/1',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(cookie)],
        },
      );
      showProject.assertStatus(HttpStatus.ok);

      final forbiddenProject = await client.get(
        '/api/v1/projects/2',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(cookie)],
        },
      );
      forbiddenProject.assertStatus(HttpStatus.forbidden);

      final updateProject = await client.putJson('/api/v1/projects/1', {
        'name': 'Compiler 2.0',
      }, headers: _csrfHeaders(csrf));
      updateProject.assertStatus(HttpStatus.ok);
      final updatedJson = updateProject.json() as Map<String, dynamic>;
      expect(updatedJson['name'], equals('Compiler 2.0'));
    });
  });
}
