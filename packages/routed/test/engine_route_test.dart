// test/engine_route_test.dart

import 'package:routed/src/engine/engine.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:routed_testing/src/mock.mocks.dart';
import 'package:test/test.dart';

// Or wherever your EngineRoute is defined, e.g. 'package:my_app/engine_route.dart'
// Adjust the import path as needed.

void main() {
  group('Parameter Type Tests', () {
    test('int parameter (success)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/users/{id:int}',
        handler: (ctx) => null,
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
        handler: (ctx) => null,
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
        handler: (ctx) => null,
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
        handler: (ctx) => null,
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
        handler: (ctx) => null,
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
        handler: (ctx) => null,
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
        handler: (ctx) => null,
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
        handler: (ctx) => null,
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
        handler: (ctx) => null,
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
        handler: (ctx) => null,
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
        handler: (ctx) => null,
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
        handler: (ctx) => null,
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
        handler: (ctx) => null,
      );

      // 999 is not a valid segment for IPv4
      final uri = Uri.parse('/diagnose/999.168.100.1h00');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isFalse);
    });

    test('string parameter (success)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/anything/{value:string}',
        handler: (ctx) => null,
      );

      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(Uri.parse('/anything/hello_world'));

      // string => r'[^/]+', so any non-slash is okay
      expect(route.matches(request), isTrue);

      final params = route.extractParameters(request.uri.path);
      expect(params['value'], 'hello_world');
    });

    test('string parameter (fail - slash in param)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/anything/{value:string}',
        handler: (ctx) => null,
      );

      // If we put a slash in the param, it won't match because r'[^/]+' excludes slashes
      final uri = Uri.parse('/anything/hello/world');
      // This route expects exactly two segments, so "hello/world" is a second segment
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isFalse);
    });

    test('Multiple placeholders (int + slug)', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/book/{id:int}/chapter/{ch:slug}',
        handler: (ctx) => null,
      );

      // Should match e.g. "/book/42/chapter/intro-section"
      final uri = Uri.parse('/book/42/chapter/intro-section');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);

      final params = route.extractParameters(uri.path);
      expect(params['id'], 42);
      expect(params['ch'], 'intro-section');
    });
  });

  group('Optional Parameter Tests', () {
    test('matches with optional parameter present', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/users/{id}/posts/{title?}',
        handler: (ctx) => null,
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
        handler: (ctx) => null,
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
        handler: (ctx) => null,
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
        handler: (ctx) => null,
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

  group('Combined Parameter Types', () {
    test('combines typed, optional and wildcard parameters', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/users/{id:int}/files/{type?}/{*path}',
        handler: (ctx) => null,
      );

      final uri = Uri.parse('/users/123/files/images/2023/photo.jpg');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);
      final params = route.extractParameters(uri.path);
      expect(params['id'], 123);
      expect(params['type'], 'images');
      expect(params['path'], '2023/photo.jpg');
    });

    test('combines typed and wildcard with optional omitted', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/users/{id:int}/files/{type?}/{*path}',
        handler: (ctx) => null,
      );

      final uri = Uri.parse('/users/123/files/docs/report.pdf');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);
      final params = route.extractParameters(uri.path);
      expect(params['id'], 123);
      expect(params['type'], 'docs');
      expect(params['path'], 'report.pdf');
    });
  });

  group('Query Parameter Tests', () {
    test('matches route with query parameters', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/search',
        handler: (ctx) => null,
      );

      final uri = Uri.parse('/search?q=dart&page=1&sort=desc');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);
      expect(request.uri.queryParameters,
          {'q': 'dart', 'page': '1', 'sort': 'desc'});
    });

    test('matches route with encoded query parameters', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/search',
        handler: (ctx) => null,
      );

      final uri = Uri.parse('/search?q=dart+language&tags=web%2Capi');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);
      expect(request.uri.queryParameters,
          {'q': 'dart language', 'tags': 'web,api'});
    });

    test('matches route with repeated query parameters', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/filter',
        handler: (ctx) => null,
      );

      final uri = Uri.parse('/filter?tag=web&tag=mobile&tag=desktop');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);
      expect(
          request.uri.queryParametersAll['tag'], ['web', 'mobile', 'desktop']);
    });

    test('matches route with empty query parameters', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/items',
        handler: (ctx) => null,
      );

      final uri = Uri.parse('/items?sort=&filter=');
      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(uri);

      expect(route.matches(request), isTrue);
      expect(request.uri.queryParameters, {'sort': '', 'filter': ''});
    });
  });

  group('EngineRoute Constraint Validation Tests', () {
    test('Constraint pass', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/items/{id}',
        handler: (ctx) => null,
        constraints: {
          'id': r'^\d+$',
        },
      );

      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      when(request.uri).thenReturn(Uri.parse('/items/123'));

      // Should pass (id=123 matches /^\d+$/)
      expect(route.matches(request), isTrue);
    });

    test('Constraint fail', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/items/{id}',
        handler: (ctx) => null,
        constraints: {
          'id': r'^\d+$',
        },
      );

      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      // "abc" does not match the numeric constraint
      when(request.uri).thenReturn(Uri.parse('/items/abc'));

      expect(route.matches(request), isFalse);
    });

    test('Multiple constraints', () {
      final route = EngineRoute(
        method: 'GET',
        path: '/users/{userId}/{slug}',
        handler: (ctx) => null,
        constraints: {
          'userId': r'^\d+$',
          'slug': r'^[a-z0-9-]+$',
        },
      );

      final request = MockHttpRequest();
      when(request.method).thenReturn('GET');
      // userId=42 (passes), slug=my-post (passes)
      when(request.uri).thenReturn(Uri.parse('/users/42/my-post'));

      expect(route.matches(request), isTrue);
    });
  });
}
