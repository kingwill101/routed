import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  group('QueryMethods', () {
    test('reads cached query parameters and maps', () async {
      final engine = testEngine();
      engine.get('/query', (ctx) {
        ctx.set(ctx.queryCacheKey, <String, dynamic>{
          'name': 'Ada',
          'empty': '',
          'tags': <String>['alpha', 'beta'],
        });

        final tuple = ctx.getQueryMap('missing.');

        return ctx.json({
          'name': ctx.getQuery<String>('name'),
          'empty': ctx.getQuery<String>('empty'),
          'tags': ctx.getQueryArray('tags'),
          'alias': ctx.queryArray('tags'),
          'fallback': ctx.defaultQuery('missing', 'fallback'),
          'map': ctx.queryMap('filter.'),
          'tupleMap': tuple.$1,
          'tupleFound': tuple.$2,
          'rawQuery': ctx.request.uri.query,
          'rawParams': ctx.request.uri.queryParametersAll,
        });
      });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final response = await client.get(
        '/query?filter.role=admin&filter.level=2',
      );
      final json = response.json();
      expect(json['name'], equals('Ada'));
      expect(json['empty'], isNull);
      expect(json['tags'], equals(['alpha', 'beta']));
      expect(json['alias'], equals(['alpha', 'beta']));
      expect(json['fallback'], equals('fallback'));
      expect(
        json['map'],
        equals({'filter.role': 'admin', 'filter.level': '2'}),
      );
      expect(json['tupleMap'], equals({}));
      expect(json['tupleFound'], isFalse);
    });
  });

  group('NegotiationContext', () {
    test('negotiates response based on Accept header', () async {
      final engine = testEngine();
      engine.get('/negotiate', (ctx) async {
        return await ctx.negotiate({
          'text/plain': () async => ctx.string('plain'),
          'application/json': () async => ctx.json({'ok': true}),
        });
      });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.inMemory,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final response = await client.get(
        '/negotiate',
        headers: {
          HttpHeaders.acceptHeader: ['text/plain'],
        },
      );

      expect(response.statusCode, equals(HttpStatus.ok));
      expect(response.body, equals('plain'));
      expect(
        response.header(HttpHeaders.contentTypeHeader).first,
        contains('text/plain'),
      );
      expect(response.header(HttpHeaders.varyHeader).first, contains('Accept'));
    });

    test('returns 406 when no offers are provided', () async {
      final engine = testEngine();
      engine.get('/negotiate', (ctx) async {
        return await ctx.negotiate({});
      });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.inMemory,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final response = await client.get(
        '/negotiate',
        headers: {
          HttpHeaders.acceptHeader: ['application/xml'],
        },
      );

      expect(response.statusCode, equals(HttpStatus.notAcceptable));
    });
  });

  group('ProxyMethods', () {
    test('forwards requests and proxies response', () async {
      final completer = Completer<_ForwardedRequest>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => await server.close(force: true));

      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final headers = <String, String>{};
        request.headers.forEach((name, values) {
          headers[name] = values.join(',');
        });
        completer.complete(
          _ForwardedRequest(
            method: request.method,
            body: body,
            headers: headers,
          ),
        );
        request.response
          ..statusCode = HttpStatus.created
          ..headers.set('X-Target', 'true')
          ..write('proxied');
        await request.response.close();
      });

      final engine = testEngine();
      engine.post('/proxy', (ctx) async {
        return await ctx.forward(
          'http://127.0.0.1:${server.port}/target',
          options: const ProxyOptions(
            forwardHeaders: false,
            headers: {'X-Custom': 'yes'},
          ),
        );
      });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final response = await client.post(
        '/proxy',
        'payload',
        headers: {
          HttpHeaders.contentLengthHeader: ['7'],
          'X-Origin': ['source'],
        },
      );

      final forwarded = await completer.future;
      expect(forwarded.method, equals('POST'));
      expect(forwarded.body, equals('payload'));
      expect(forwarded.headers['x-custom'], equals('yes'));
      expect(forwarded.headers.containsKey('x-origin'), isFalse);
      expect(forwarded.headers.containsKey('x-forwarded-for'), isTrue);
      expect(forwarded.headers.containsKey('x-forwarded-host'), isTrue);
      expect(forwarded.headers.containsKey('x-forwarded-proto'), isTrue);

      expect(response.statusCode, equals(HttpStatus.created));
      expect(response.body, equals('proxied'));
      expect(response.header('x-target').first, equals('true'));
      expect(response.header('x-proxied-by').first, equals('Routed'));
    });
  });
}

class _ForwardedRequest {
  _ForwardedRequest({
    required this.method,
    required this.body,
    required this.headers,
  });

  final String method;
  final String body;
  final Map<String, String> headers;
}
