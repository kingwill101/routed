import 'dart:io';

import 'package:routed/routed.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('Parameter Type Tests', () {
    test('int parameter (success)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/users/{id:int}',
        handler: (ctx) => ctx.string('ok'),
      );

      // Should match for e.g. "/users/123"
      final uri = Uri.parse('/users/123');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);
      expect(route.matches(request), isTrue);

      // Extract parameter
      final params = route.extractParameters(uri.path);
      expect(params['id'], 123); // cast to int
      expect(params['id'], isA<int>());
    });

    test('int parameter (fail - not an int)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/users/{id:int}',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/users/abc');
      // Not an integer => shouldn't match
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);
      expect(route.matches(request), isFalse);
    });

    test('double parameter (success)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/price/{amount:double}',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/price/12.34');

      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);

      final params = route.extractParameters(uri.path);
      expect(params['amount'], 12.34);
      expect(params['amount'], isA<double>());
    });

    test('double parameter (integer also valid as double)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/price/{amount:double}',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/price/42');

      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);

      final params = route.extractParameters(uri.path);
      expect(params['amount'], 42.0);
      expect(params['amount'], isA<double>());
    });

    test('double parameter (fail - not numeric)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/price/{amount:double}',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/price/abc');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isFalse);
    });

    test('slug parameter (success)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/posts/{slug:slug}',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/posts/my-awesome-post');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);

      final params = route.extractParameters(uri.path);
      expect(params['slug'], 'my-awesome-post');
    });

    test('slug parameter (fail - invalid format)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/posts/{slug:slug}',
        handler: (ctx) => ctx.string('ok'),
      );

      // Slug pattern is `[a-z0-9]+(?:-[a-z0-9]+)*`
      // We'll attempt uppercase or special characters
      final uri = Uri.parse('/posts/MyAwesomePost!');

      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isFalse);
    });

    test('uuid parameter (success)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/resources/{rid:uuid}',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/resources/123e4567-e89b-12d3-a456-426614174000');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);

      final params = route.extractParameters(uri.path);
      expect(params['rid'], '123e4567-e89b-12d3-a456-426614174000');
    });

    test('uuid parameter (fail)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/resources/{rid:uuid}',
        handler: (ctx) => ctx.string('ok'),
      );

      // Not a valid UUID
      final uri = Uri.parse('/resources/NotARealUUID');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isFalse);
    });

    test('email parameter (success)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/subscribe/{contact:email}',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/subscribe/test.user@example.com');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);

      final params = route.extractParameters(uri.path);
      expect(params['contact'], 'test.user@example.com');
    });

    test('email parameter (fail)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/subscribe/{contact:email}',
        handler: (ctx) => ctx.string('ok'),
      );

      // Missing "@" or domain
      final uri = Uri.parse('/subscribe/notAnEmail');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isFalse);
    });

    test('ip parameter (success)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/diagnose/{address:ip}',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/diagnose/192.168.1.100');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);

      final params = route.extractParameters(uri.path);
      expect(params['address'], '192.168.1.100');
    });

    test('ip parameter (fail - invalid segment)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/diagnose/{address:ip}',
        handler: (ctx) => ctx.string('ok'),
      );

      // 999 is not a valid segment for IPv4
      final uri = Uri.parse('/diagnose/999.168.100.1h00');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isFalse);
    });
  });

  group('Optional Parameter Tests', () {
    test('matches with optional parameter present', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/users/{id}/posts/{title?}',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/users/123/posts/hello-world');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);
      final params = route.extractParameters(uri.path);
      expect(params['id'], '123');
      expect(params['title'], 'hello-world');
    });

    test('matches with optional parameter omitted', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/users/{id}/posts/{title?}',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/users/123/posts');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);
      final params = route.paramsWithInfo(uri.path);
      assert(params.length == 2);

      final title = params.where((entry) => entry.key == 'title').first;
      final id = params.where((entry) => entry.key == 'id').first;

      expect(title.value, isNull);
      expect(title.info.isOptional, isTrue);
      expect(title.info.isWildcard, isFalse);
      expect(id.value, '123');
    });
  });

  group('Wildcard Parameter Tests', () {
    test('matches single level wildcard', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/files/{*path}',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/files/documents/report.pdf');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);
      final params = route.extractParameters(uri.path);
      expect(params['path'], 'documents/report.pdf');
    });

    test('matches multi-level wildcard', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/files/{*path}',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/files/2023/q1/reports/financial.xlsx');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);
      final params = route.extractParameters(uri.path);
      expect(params['path'], '2023/q1/reports/financial.xlsx');
    });
  });

  group('Query Parameter Tests', () {
    test('matches route with query parameters', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/search',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/search?q=dart&page=1&sort=desc');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);
      expect(request.uri.queryParameters, {
        'q': 'dart',
        'page': '1',
        'sort': 'desc',
      });
    });

    test('matches route with encoded query parameters', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/search',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/search?q=dart+language&tags=web%2Capi');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);
      expect(request.uri.queryParameters, {
        'q': 'dart language',
        'tags': 'web,api',
      });
    });

    test('matches route with repeated query parameters', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/filter',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/filter?tag=web&tag=mobile&tag=desktop');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);
      expect(request.uri.queryParametersAll['tag'], [
        'web',
        'mobile',
        'desktop',
      ]);
    });
  });

  group('Custom Pattern Tests', () {
    setUp(() {
      clearCustomPatterns();
    });

    test('registerCustomType - custom phone number type', () {
      registerCustomType('phone', r'\d{3}-\d{3}-\d{4}');

      final route = EngineRoute(
        method: 'GET',
        path: '/contact/{number:phone}',
        handler: (ctx) => ctx.string('ok'),
      );

      final validRequest = MockHttpRequest();
      when(validRequest.method).thenReturn('GET');
      when(validRequest.uri).thenReturn(Uri.parse('/contact/123-456-7890'));

      final invalidRequest = MockHttpRequest();
      when(invalidRequest.method).thenReturn('GET');
      when(invalidRequest.uri).thenReturn(Uri.parse('/contact/123456789'));

      expect(route.matches(validRequest), isTrue);
      expect(route.matches(invalidRequest), isFalse);

      final params = route.extractParameters('/contact/123-456-7890');
      expect(params['number'], '123-456-7890');
    });

    test('registerParamPattern - global param pattern', () {
      registerParamPattern('id', r'\d{6}'); // 6-digit ID

      final route = EngineRoute(
        method: 'GET',
        path: '/users/{id}',
        handler: (ctx) => ctx.string('ok'),
      );

      final validRequest = MockHttpRequest();
      when(validRequest.method).thenReturn('GET');
      when(validRequest.uri).thenReturn(Uri.parse('/users/123456'));

      final invalidRequest = MockHttpRequest();
      when(invalidRequest.method).thenReturn('GET');
      when(invalidRequest.uri).thenReturn(Uri.parse('/users/12345'));

      expect(route.matches(validRequest), isTrue);
      expect(route.matches(invalidRequest), isFalse);

      final params = route.extractParameters('/users/123456');
      expect(params['id'], '123456');
    });

    test('addPattern - custom zipcode pattern', () {
      registerPattern('zipcode', r'\d{5}(?:-\d{4})?');

      final route = EngineRoute(
        method: 'GET',
        path: '/location/{zip:zipcode}',
        handler: (ctx) => ctx.string('ok'),
      );

      final validRequest1 = MockHttpRequest();
      when(validRequest1.method).thenReturn('GET');
      when(validRequest1.uri).thenReturn(Uri.parse('/location/12345'));

      final validRequest2 = MockHttpRequest();
      when(validRequest2.method).thenReturn('GET');
      when(validRequest2.uri).thenReturn(Uri.parse('/location/12345-6789'));

      final invalidRequest = MockHttpRequest();
      when(invalidRequest.method).thenReturn('GET');
      when(invalidRequest.uri).thenReturn(Uri.parse('/location/1234'));

      expect(route.matches(validRequest1), isTrue);
      expect(route.matches(validRequest2), isTrue);
      expect(route.matches(invalidRequest), isFalse);

      final params1 = route.extractParameters('/location/12345');
      final params2 = route.extractParameters('/location/12345-6789');
      expect(params1['zip'], '12345');
      expect(params2['zip'], '12345-6789');
    });

    test('multiple custom patterns in same route', () {
      registerCustomType('phone', r'\d{3}-\d{3}-\d{4}');
      registerCustomType('zipcode', r'\d{5}(?:-\d{4})?');

      final route = EngineRoute(
        method: 'GET',
        path: '/contact/{phone:phone}/area/{zip:zipcode}',
        handler: (ctx) => ctx.string('ok'),
      );

      final validRequest = MockHttpRequest();
      when(validRequest.method).thenReturn('GET');
      when(
        validRequest.uri,
      ).thenReturn(Uri.parse('/contact/123-456-7890/area/12345-6789'));

      expect(route.matches(validRequest), isTrue);

      final params = route.extractParameters(
        '/contact/123-456-7890/area/12345-6789',
      );
      expect(params['phone'], '123-456-7890');
      expect(params['zip'], '12345-6789');
    });
  });
  group('Custom route parameter casting', () {
    test('custom casting type (success)', () {
      EngineRoute.registerCustomCasting(
        'bool',
        (String? value) => value == 'true',
      );

      final route = EngineRoute(
        method: 'GET',
        path: '/toggle/{enabled:bool}',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/toggle/true');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);

      final params = route.extractParameters(uri.path);
      expect(params['enabled'], true);
      expect(params['enabled'], isA<bool>());

      EngineRoute.unregisterCustomCasting('bool');
    });

    test('custom casting type (fail)', () {
      EngineRoute.registerCustomCasting(
        'bool',
        (String? value) => value == 'true',
      );

      final route = EngineRoute(
        method: 'GET',
        path: '/toggle/{enabled:bool}',
        handler: (ctx) => ctx.string('ok'),
      );

      final uri = Uri.parse('/toggle/false');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);

      final params = route.extractParameters(uri.path);
      expect(params['enabled'], false);
      expect(params['enabled'], isA<bool>());

      EngineRoute.unregisterCustomCasting('bool');
    });
  });
  group('Route Constraint Validation Tests', () {
    test('regex string constraint', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/users/{id}',
        handler: (ctx) => ctx.string('ok'),
        constraints: {'id': r'^\d{5}$'},
      );

      final validRequest = MockHttpRequest();
      when(validRequest.method).thenReturn('GET');
      when(validRequest.uri).thenReturn(Uri.parse('/users/12345'));

      final invalidRequest = MockHttpRequest();
      when(invalidRequest.method).thenReturn('GET');
      when(invalidRequest.uri).thenReturn(Uri.parse('/users/123'));

      expect(route.matches(validRequest), isTrue);
      expect(route.matches(invalidRequest), isFalse);
    });

    test('domain constraint', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/api/v1/resource',
        handler: (ctx) => ctx.string('ok'),
        constraints: {'domain': r'^api\.example\.com$'},
      );

      // Valid request setup
      final validRequest = MockHttpRequest();
      final validHeaders = MockHttpHeaders();
      when(validHeaders.host).thenReturn('api.example.com');
      when(validRequest.method).thenReturn('GET');
      when(validRequest.uri).thenReturn(Uri.parse('/api/v1/resource'));
      when(validRequest.headers).thenAnswer((_) => validHeaders);

      // Invalid request setup
      final invalidRequest = MockHttpRequest();
      final invalidHeaders = MockHttpHeaders();
      when(invalidHeaders.host).thenReturn('wrong.example.com');
      when(invalidRequest.method).thenReturn('GET');
      when(invalidRequest.uri).thenReturn(Uri.parse('/api/v1/resource'));
      when(invalidRequest.headers).thenAnswer((_) => invalidHeaders);

      expect(route.matches(validRequest), isTrue);
      expect(route.matches(invalidRequest), isFalse);
    });

    test('function constraint', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/secure/data',
        handler: (ctx) => ctx.string('ok'),
        constraints: {
          'auth': (HttpRequest request) {
            return request.headers.value('Authorization') ==
                'Bearer valid-token';
          },
        },
      );

      // Valid request setup
      final validRequest = MockHttpRequest();
      final validHeaders = MockHttpHeaders();
      when(
        validHeaders.value('Authorization'),
      ).thenReturn('Bearer valid-token');
      when(validRequest.method).thenReturn('GET');
      when(validRequest.uri).thenReturn(Uri.parse('/secure/data'));
      when(validRequest.headers).thenAnswer((_) => validHeaders);

      // Invalid request setup
      final invalidRequest = MockHttpRequest();
      final invalidHeaders = MockHttpHeaders();
      when(
        invalidHeaders.value('Authorization'),
      ).thenReturn('Bearer invalid-token');
      when(invalidRequest.method).thenReturn('GET');
      when(invalidRequest.uri).thenReturn(Uri.parse('/secure/data'));
      when(invalidRequest.headers).thenAnswer((_) => invalidHeaders);

      expect(route.matches(validRequest), isTrue);
      expect(route.matches(invalidRequest), isFalse);
    });

    test('multiple constraints of different types', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/api/users/{id}/profile',
        handler: (ctx) => ctx.string('ok'),
        constraints: {
          'id': r'^\d{6}$',
          'domain': r'^api\.example\.com$',
          'auth': (HttpRequest request) {
            return request.headers.value('API-Key') == 'valid-key';
          },
        },
      );

      // Valid request setup
      final validRequest = MockHttpRequest();
      final validHeaders = MockHttpHeaders();
      when(validHeaders.host).thenReturn('api.example.com');
      when(validHeaders.value('API-Key')).thenReturn('valid-key');
      when(validRequest.method).thenReturn('GET');
      when(validRequest.uri).thenReturn(Uri.parse('/api/users/123456/profile'));
      when(validRequest.headers).thenAnswer((_) => validHeaders);

      // Invalid requests setup
      final invalidRequest1 = MockHttpRequest();
      final invalidHeaders1 = MockHttpHeaders();
      when(invalidHeaders1.host).thenReturn('api.example.com');
      when(invalidHeaders1.value('API-Key')).thenReturn('valid-key');
      when(invalidRequest1.method).thenReturn('GET');
      when(
        invalidRequest1.uri,
      ).thenReturn(Uri.parse('/api/users/12345/profile'));
      when(invalidRequest1.headers).thenAnswer((_) => invalidHeaders1);

      final invalidRequest2 = MockHttpRequest();
      final invalidHeaders2 = MockHttpHeaders();
      when(invalidHeaders2.host).thenReturn('wrong.example.com');
      when(invalidHeaders2.value('API-Key')).thenReturn('valid-key');
      when(invalidRequest2.method).thenReturn('GET');
      when(
        invalidRequest2.uri,
      ).thenReturn(Uri.parse('/api/users/123456/profile'));
      when(invalidRequest2.headers).thenAnswer((_) => invalidHeaders2);

      final invalidRequest3 = MockHttpRequest();
      final invalidHeaders3 = MockHttpHeaders();
      when(invalidHeaders3.host).thenReturn('api.example.com');
      when(invalidHeaders3.value('API-Key')).thenReturn('invalid-key');
      when(invalidRequest3.method).thenReturn('GET');
      when(
        invalidRequest3.uri,
      ).thenReturn(Uri.parse('/api/users/123456/profile'));
      when(invalidRequest3.headers).thenAnswer((_) => invalidHeaders3);

      expect(route.matches(validRequest), isTrue);
      expect(route.matches(invalidRequest1), isFalse); // wrong ID
      expect(route.matches(invalidRequest2), isFalse); // wrong domain
      expect(route.matches(invalidRequest3), isFalse); // wrong API key
    });

    test('constraint with missing parameter', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/optional/{param?}',
        handler: (ctx) => ctx.string('ok'),
        constraints: {'param': r'^\d+$'},
      );

      final requestWithoutParam = MockHttpRequest();
      when(requestWithoutParam.method).thenReturn('GET');
      when(requestWithoutParam.uri).thenReturn(Uri.parse('/optional'));

      expect(route.matches(requestWithoutParam), isFalse);
    });

    test('complex function constraint', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/advanced/{id}',
        handler: (ctx) => ctx.string('ok'),
        constraints: {
          'complex': (HttpRequest request) {
            final id = request.uri.pathSegments.last;
            final apiKey = request.headers.value('API-Key');
            final userAgent = request.headers.value('User-Agent');

            return id.length == 6 &&
                apiKey == 'valid-key' &&
                userAgent?.contains('Mozilla') == true;
          },
        },
      );

      // Valid request setup
      final validRequest = MockHttpRequest();
      final validHeaders = MockHttpHeaders();
      when(validHeaders.value('API-Key')).thenReturn('valid-key');
      when(validHeaders.value('User-Agent')).thenReturn('Mozilla/5.0');
      when(validRequest.method).thenReturn('GET');
      when(validRequest.uri).thenReturn(Uri.parse('/advanced/123456'));
      when(validRequest.headers).thenAnswer((_) => validHeaders);

      // Invalid request setup
      final invalidRequest = MockHttpRequest();
      final invalidHeaders = MockHttpHeaders();
      when(invalidHeaders.value('API-Key')).thenReturn('valid-key');
      when(invalidHeaders.value('User-Agent')).thenReturn('Custom/1.0');
      when(invalidRequest.method).thenReturn('GET');
      when(invalidRequest.uri).thenReturn(Uri.parse('/advanced/123456'));
      when(invalidRequest.headers).thenAnswer((_) => invalidHeaders);

      expect(route.matches(validRequest), isTrue);
      expect(route.matches(invalidRequest), isFalse);
    });
  });
}
