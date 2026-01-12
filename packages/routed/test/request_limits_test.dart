import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:routed/middlewares.dart';
import 'package:routed/routed.dart';
import 'package:routed/src/engine/providers/request.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

void main() {
  group('Request limits', () {
    engineTest(
      'middleware rejects payloads over content length limit',
      (engine, client) async {
        engine.middlewares.add(limitRequestBody(5));
        engine.post('/limited', (ctx) async {
          final body = await ctx.request.body();
          return ctx.string(body);
        });

        final response = await client.post(
          '/limited',
          '1234567890',
          headers: {
            HttpHeaders.contentLengthHeader: ['10'],
          },
        );

        expect(response.statusCode, equals(HttpStatus.requestEntityTooLarge));
        expect(response.body, equals('Payload Too Large'));
      },
      transportMode: TransportMode.ephemeralServer,
    );

    engineTest(
      'engine wraps requests when max size exceeded',
      (engine, client) async {
        engine.post('/wrapped', (ctx) async {
          final body = await ctx.request.body();
          return ctx.string(body);
        });

        final response = await client.post('/wrapped', '1234');

        expect(response.statusCode, equals(HttpStatus.ok));
        expect(response.body, equals('1234'));
      },
      transportMode: TransportMode.ephemeralServer,
      configItems: {
        'security': {'max_request_size': 5},
      },
    );

    engineTest(
      'streams request body and exposes session metadata',
      (engine, client) async {
        engine.post('/stream', (ctx) async {
          final bytes = await ctx.request.stream.fold<List<int>>(
            <int>[],
            (list, chunk) => list..addAll(chunk),
          );
          final sessionId = ctx.request.session.id;
          final requestedHost = ctx.request.requestedUri.host;
          final remotePort = ctx.request.connectionInfo?.remotePort;

          return ctx.json({
            'body': utf8.decode(bytes),
            'session': sessionId,
            'host': requestedHost,
            'remotePort': remotePort,
          });
        });

        final response = await client.post('/stream', 'ping');
        final payload = response.json();

        expect(payload['body'], equals('ping'));
        expect(payload['session'], isNotEmpty);
        expect(payload['host'], isNotEmpty);
        expect(payload['remotePort'], isNotNull);
      },
      transportMode: TransportMode.ephemeralServer,
    );

    engineTest(
      'exercises wrapped request stream helpers',
      (engine, client) async {
        engine.post('/fold', (ctx) async {
          final builder = await ctx.request.httpRequest.fold<BytesBuilder>(
            BytesBuilder(),
            (current, chunk) {
              current.add(chunk);
              return current;
            },
          );
          return ctx.string(utf8.decode(builder.toBytes()));
        });
        engine.post('/first', (ctx) async {
          final chunk = await ctx.request.httpRequest.first;
          return ctx.string(utf8.decode(chunk));
        });
        engine.post('/length', (ctx) async {
          final count = await ctx.request.httpRequest.length;
          return ctx.string(count.toString());
        });
        engine.post('/list', (ctx) async {
          final chunks = await ctx.request.httpRequest.toList();
          final bytes = chunks.expand((chunk) => chunk).toList();
          return ctx.string(utf8.decode(bytes));
        });
        engine.post('/any', (ctx) async {
          final hasDigit = await ctx.request.httpRequest.any(
            (chunk) => chunk.any((byte) => byte == '9'.codeUnitAt(0)),
          );
          return ctx.string(hasDigit.toString());
        });
        engine.post('/every', (ctx) async {
          final allHaveData = await ctx.request.httpRequest.every(
            (chunk) => chunk.isNotEmpty,
          );
          return ctx.string(allHaveData.toString());
        });
        engine.post('/reduce', (ctx) async {
          final merged = await ctx.request.httpRequest.reduce((
            previous,
            current,
          ) {
            final combined = Uint8List(previous.length + current.length);
            combined.setAll(0, previous);
            combined.setAll(previous.length, current);
            return combined;
          });
          return ctx.string(utf8.decode(merged));
        });
        engine.post('/take', (ctx) async {
          final chunks = await ctx.request.httpRequest.take(1).toList();
          final bytes = chunks.expand((chunk) => chunk).toList();
          return ctx.string(utf8.decode(bytes));
        });
        engine.post('/last', (ctx) async {
          final chunk = await ctx.request.httpRequest.last;
          return ctx.string(utf8.decode(chunk));
        });
        engine.post('/single', (ctx) async {
          final chunk = await ctx.request.httpRequest.single;
          return ctx.string(utf8.decode(chunk));
        });
        engine.post('/element', (ctx) async {
          final chunk = await ctx.request.httpRequest.elementAt(0);
          return ctx.string(utf8.decode(chunk));
        });
        engine.post('/map', (ctx) async {
          final chunks = await ctx.request.httpRequest
              .map((chunk) => chunk)
              .toList();
          final bytes = chunks.expand((chunk) => chunk).toList();
          return ctx.string(utf8.decode(bytes));
        });
        engine.post('/async-map', (ctx) async {
          final chunks = await ctx.request.httpRequest
              .asyncMap((chunk) async => chunk)
              .toList();
          final bytes = chunks.expand((chunk) => chunk).toList();
          return ctx.string(utf8.decode(bytes));
        });
        engine.post('/expand', (ctx) async {
          final chunks = await ctx.request.httpRequest
              .expand((chunk) => [chunk])
              .toList();
          final bytes = chunks.expand((chunk) => chunk).toList();
          return ctx.string(utf8.decode(bytes));
        });
        engine.post('/skip', (ctx) async {
          final chunks = await ctx.request.httpRequest.skip(1).toList();
          return ctx.string(chunks.length.toString());
        });
        engine.post('/take-while', (ctx) async {
          final chunks = await ctx.request.httpRequest
              .takeWhile((chunk) => chunk.isNotEmpty)
              .toList();
          final bytes = chunks.expand((chunk) => chunk).toList();
          return ctx.string(utf8.decode(bytes));
        });
        engine.post('/where', (ctx) async {
          final chunks = await ctx.request.httpRequest
              .where((chunk) => chunk.isNotEmpty)
              .toList();
          final bytes = chunks.expand((chunk) => chunk).toList();
          return ctx.string(utf8.decode(bytes));
        });
        engine.post('/handle-error', (ctx) async {
          final chunks = await ctx.request.httpRequest
              .handleError((_) {})
              .toList();
          final bytes = chunks.expand((chunk) => chunk).toList();
          return ctx.string(utf8.decode(bytes));
        });
        engine.post('/broadcast', (ctx) async {
          final isBroadcast = ctx.request.httpRequest.isBroadcast;
          return ctx.string(isBroadcast.toString());
        });

        final foldResponse = await client.post('/fold', 'fold');
        expect(foldResponse.body, equals('fold'));

        final firstResponse = await client.post('/first', 'first');
        expect(firstResponse.body, equals('first'));

        final lengthResponse = await client.post('/length', 'len');
        expect(lengthResponse.body, equals('1'));

        final listResponse = await client.post('/list', 'list');
        expect(listResponse.body, equals('list'));

        final anyResponse = await client.post('/any', '9');
        expect(anyResponse.body, equals('true'));

        final everyResponse = await client.post('/every', 'x');
        expect(everyResponse.body, equals('true'));

        final reduceResponse = await client.post('/reduce', 'reduce');
        expect(reduceResponse.body, equals('reduce'));

        final takeResponse = await client.post('/take', 'take');
        expect(takeResponse.body, equals('take'));

        final lastResponse = await client.post('/last', 'last');
        expect(lastResponse.body, equals('last'));

        final singleResponse = await client.post('/single', 'single');
        expect(singleResponse.body, equals('single'));

        final elementResponse = await client.post('/element', 'element');
        expect(elementResponse.body, equals('element'));

        final mapResponse = await client.post('/map', 'map');
        expect(mapResponse.body, equals('map'));

        final asyncMapResponse = await client.post('/async-map', 'async');
        expect(asyncMapResponse.body, equals('async'));

        final expandResponse = await client.post('/expand', 'expand');
        expect(expandResponse.body, equals('expand'));

        final skipResponse = await client.post('/skip', 'skip');
        expect(skipResponse.body, equals('0'));

        final takeWhileResponse = await client.post('/take-while', 'take');
        expect(takeWhileResponse.body, equals('take'));

        final whereResponse = await client.post('/where', 'where');
        expect(whereResponse.body, equals('where'));

        final handleErrorResponse = await client.post('/handle-error', 'err');
        expect(handleErrorResponse.body, equals('err'));

        final broadcastResponse = await client.post('/broadcast', 'noop');
        expect(broadcastResponse.body, equals('false'));
      },
      transportMode: TransportMode.ephemeralServer,
      configItems: {
        'security': {'max_request_size': 1024},
      },
    );

    engineTest(
      'request service provider resolves request bindings',
      (engine, client) async {
        engine.get('/resolve', (ctx) async {
          final req = await ctx.container.make<Request>();
          final res = await ctx.container.make<Response>();
          final ctxFromContainer = await ctx.container.make<EngineContext>();

          return ctx.json({
            'reqSame': identical(req, ctx.request),
            'resSame': identical(res, ctx.response),
            'ctxSame': identical(ctxFromContainer.request, ctx.request),
          });
        });
        engine.get('/provider', (ctx) async {
          final container = Container();
          container
            ..instance<EngineConfig>(ctx.engine!.config)
            ..instance<Engine>(ctx.engine!);
          final provider = RequestServiceProvider(
            ctx.request.httpRequest,
            ctx.request.httpRequest.response,
          );
          provider.register(container);

          final req = await container.make<Request>();
          final res = await container.make<Response>();
          final ctxFromContainer = await container.make<EngineContext>();

          return ctx.json({
            'hasRequest': req.method.isNotEmpty,
            'hasResponse': res.statusCode == HttpStatus.ok,
            'hasContext': ctxFromContainer.request.method.isNotEmpty,
          });
        });
        engine.get('/meta', (ctx) {
          return ctx.json({
            'hasCert': ctx.request.certificate != null,
            'sessionId': ctx.request.session.id,
          });
        });

        final response = await client.get('/resolve');
        expect(response.json()['reqSame'], isTrue);
        expect(response.json()['resSame'], isTrue);
        expect(response.json()['ctxSame'], isTrue);

        final providerResponse = await client.get('/provider');
        expect(providerResponse.json()['hasRequest'], isTrue);
        expect(providerResponse.json()['hasResponse'], isTrue);
        expect(providerResponse.json()['hasContext'], isTrue);

        final metaResponse = await client.get('/meta');
        expect(metaResponse.json()['hasCert'], isFalse);
        expect(metaResponse.json()['sessionId'], isNotEmpty);
      },
      transportMode: TransportMode.ephemeralServer,
    );
  });
}
