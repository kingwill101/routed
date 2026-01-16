import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:routed/middlewares.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('LimitedHttpRequestWrapper', () {
    engineTest(
      'forwards request metadata and stream helpers',
      (engine, client) async {
        engine.post('/limited', (ctx) async {
          final original = ctx.request.httpRequest;

          Uint8List toBytes(String value) =>
              Uint8List.fromList(utf8.encode(value));
          LimitedHttpRequestWrapper wrapStrings(List<String> chunks) {
            return LimitedHttpRequestWrapper(
              original,
              Stream<List<int>>.fromIterable(chunks.map(toBytes)),
            );
          }

          String decodeBytes(Uint8List bytes) => utf8.decode(bytes);
          String decodeChunks(Iterable<Uint8List> chunks) {
            return utf8.decode(chunks.expand((chunk) => chunk).toList());
          }

          final metadataWrapper = LimitedHttpRequestWrapper(
            original,
            const Stream<List<int>>.empty(),
          );
          final cookies = metadataWrapper.cookies;
          final cookieName = cookies.isNotEmpty ? cookies.first.name : '';
          final cookieValue = cookies.isNotEmpty ? cookies.first.value : '';

          final listenCompleter = Completer<String>();
          final listenDone = Completer<void>();
          wrapStrings(['listen']).listen(
            (chunk) => listenCompleter.complete(decodeBytes(chunk)),
            onError: (Object error, [StackTrace? stack]) {
              listenCompleter.completeError(error, stack);
            },
            onDone: () => listenDone.complete(),
            cancelOnError: true,
          );
          final listenValue = await listenCompleter.future;
          await listenDone.future;

          var onListenCalled = false;
          var onCancelCalled = false;
          final broadcastStream = Stream<List<int>>.fromIterable([
            toBytes('broadcast'),
          ]).asBroadcastStream();
          final broadcastWrapper = LimitedHttpRequestWrapper(
            original,
            broadcastStream,
          );
          final broadcasted = broadcastWrapper.asBroadcastStream(
            onListen: (_) => onListenCalled = true,
            onCancel: (_) => onCancelCalled = true,
          );
          final broadcastValue = decodeBytes(await broadcasted.first);
          final broadcastSubscription = broadcasted.listen((_) {});
          await broadcastSubscription.cancel();
          await Future<void>.delayed(Duration.zero);

          final asyncExpandValue = decodeBytes(
            await wrapStrings(['expand'])
                .asyncExpand((chunk) => Stream<Uint8List>.fromIterable([chunk]))
                .first,
          );
          final asyncMapValue = decodeBytes(
            await wrapStrings([
              'async-map',
            ]).asyncMap((chunk) async => chunk).first,
          );

          final castValue = decodeBytes(
            await wrapStrings(['cast']).cast<List<int>>().first as Uint8List,
          );

          final containsChunk = toBytes('contains');
          final containsResult = await LimitedHttpRequestWrapper(
            original,
            Stream<List<int>>.fromIterable([containsChunk]),
          ).contains(containsChunk);

          final distinctChunks = await LimitedHttpRequestWrapper(
            original,
            Stream<List<int>>.fromIterable([
              Uint8List.fromList([1]),
              Uint8List.fromList([1]),
            ]),
          ).distinct((prev, next) => prev[0] == next[0]).toList();

          final elementAtValue = decodeBytes(
            await wrapStrings(['a', 'element']).elementAt(1),
          );

          final everyResult = await wrapStrings([
            'every',
          ]).every((chunk) => chunk.isNotEmpty);

          final expandChunks = await wrapStrings([
            'ex',
          ]).expand((chunk) => [chunk, chunk]).toList();

          final firstValue = decodeBytes(await wrapStrings(['first']).first);
          final firstWhereValue = decodeBytes(
            await wrapStrings([
              'skip',
              'first-where',
            ]).firstWhere((chunk) => chunk.contains('f'.codeUnitAt(0))),
          );
          final firstWhereFallback = decodeBytes(
            await wrapStrings(['miss']).firstWhere(
              (chunk) => chunk.contains('z'.codeUnitAt(0)),
              orElse: () => Uint8List.fromList(utf8.encode('fallback')),
            ),
          );

          final foldValue = await wrapStrings(['fo', 'ld']).fold<String>(
            '',
            (previous, chunk) => previous + decodeBytes(chunk),
          );

          final forEachBuffer = StringBuffer();
          await wrapStrings([
            'for',
            'each',
          ]).forEach((chunk) => forEachBuffer.write(decodeBytes(chunk)));

          final handleErrorLength =
              await LimitedHttpRequestWrapper(
                    original,
                    Stream<List<int>>.error(StateError('boom')),
                  )
                  .handleError((_) {}, test: (error) => error is StateError)
                  .toList()
                  .then((value) => value.length);

          final isEmptyResult = await LimitedHttpRequestWrapper(
            original,
            const Stream<List<int>>.empty(),
          ).isEmpty;

          final joinedValue = await wrapStrings(['join']).join('-');

          final lastValue = decodeBytes(
            await wrapStrings(['first', 'last']).last,
          );
          final lastWhereValue = decodeBytes(
            await wrapStrings([
              'last',
              'where',
            ]).lastWhere((chunk) => chunk.contains('w'.codeUnitAt(0))),
          );
          final lastWhereFallback = decodeBytes(
            await wrapStrings(['absent']).lastWhere(
              (chunk) => chunk.contains('z'.codeUnitAt(0)),
              orElse: () => Uint8List.fromList(utf8.encode('fallback')),
            ),
          );

          final lengthValue = await wrapStrings(['len', 'gth']).length;

          final mapValue = decodeChunks(
            await wrapStrings(['map']).map((chunk) => chunk).toList(),
          );

          final pipeController = StreamController<List<int>>();
          final pipeFuture = wrapStrings(['pipe']).pipe(pipeController.sink);
          final pipeBytes = await pipeController.stream
              .expand((chunk) => chunk)
              .toList();
          await pipeFuture;
          await pipeController.close();
          final pipeValue = utf8.decode(pipeBytes);

          final reducedValue = decodeBytes(
            await wrapStrings(['re', 'duce']).reduce((previous, current) {
              final combined = Uint8List(previous.length + current.length);
              combined.setAll(0, previous);
              combined.setAll(previous.length, current);
              return combined;
            }),
          );

          final singleValue = decodeBytes(await wrapStrings(['single']).single);
          final singleWhereValue = decodeBytes(
            await wrapStrings([
              'target',
            ]).singleWhere((chunk) => chunk.contains('t'.codeUnitAt(0))),
          );
          final singleWhereFallback = decodeBytes(
            await wrapStrings(['none']).singleWhere(
              (chunk) => chunk.contains('z'.codeUnitAt(0)),
              orElse: () => Uint8List.fromList(utf8.encode('fallback')),
            ),
          );

          final skipValue = decodeChunks(
            await wrapStrings(['skip', 'keep']).skip(1).toList(),
          );
          final skipWhileValue = decodeChunks(
            await wrapStrings([
              'skip',
              'stay',
            ]).skipWhile((chunk) => chunk.contains('k'.codeUnitAt(0))).toList(),
          );

          final takeValue = decodeChunks(
            await wrapStrings(['take', 'rest']).take(1).toList(),
          );
          final takeWhileValue = decodeChunks(
            await wrapStrings([
              'take',
              'stop',
            ]).takeWhile((chunk) => chunk.contains('k'.codeUnitAt(0))).toList(),
          );

          final timeoutController = StreamController<List<int>>();
          final timeoutValue = decodeBytes(
            await LimitedHttpRequestWrapper(original, timeoutController.stream)
                .timeout(
                  Duration.zero,
                  onTimeout: (sink) {
                    sink.add(Uint8List.fromList(utf8.encode('timeouted')));
                    sink.close();
                  },
                )
                .first,
          );
          await timeoutController.close();

          final listValue = decodeChunks(
            await wrapStrings(['list', 'value']).toList(),
          );

          final setValue = await wrapStrings(['set', 'value']).toSet();

          final transformedValue = decodeBytes(
            await wrapStrings(['hi'])
                .transform(
                  StreamTransformer<List<int>, Uint8List>.fromHandlers(
                    handleData: (data, sink) {
                      sink.add(
                        Uint8List.fromList([...data, '!'.codeUnitAt(0)]),
                      );
                    },
                  ),
                )
                .first,
          );

          final whereValue = decodeChunks(
            await wrapStrings([
              'where',
              'drop',
            ]).where((chunk) => chunk.contains('w'.codeUnitAt(0))).toList(),
          );

          final drainValue = await wrapStrings(['drain']).drain('done');

          final anyResult = await wrapStrings([
            'any',
          ]).any((chunk) => chunk.contains('a'.codeUnitAt(0)));

          return ctx.json({
            'method': metadataWrapper.method,
            'path': metadataWrapper.uri.path,
            'requestedPath': metadataWrapper.requestedUri.path,
            'contentLength': metadataWrapper.contentLength,
            'header': metadataWrapper.headers.value('X-Test'),
            'cookieName': cookieName,
            'cookieValue': cookieValue,
            'protocolVersion': metadataWrapper.protocolVersion,
            'persistentConnection': metadataWrapper.persistentConnection,
            'hasCertificate': metadataWrapper.certificate != null,
            'hasConnectionInfo': metadataWrapper.connectionInfo != null,
            'sameResponse': identical(
              metadataWrapper.response,
              original.response,
            ),
            'sameSession': identical(metadataWrapper.session, original.session),
            'listen': listenValue,
            'broadcast': broadcastValue,
            'onListenCalled': onListenCalled,
            'onCancelCalled': onCancelCalled,
            'asyncExpand': asyncExpandValue,
            'asyncMap': asyncMapValue,
            'cast': castValue,
            'contains': containsResult,
            'distinctCount': distinctChunks.length,
            'elementAt': elementAtValue,
            'every': everyResult,
            'expandCount': expandChunks.length,
            'first': firstValue,
            'firstWhere': firstWhereValue,
            'firstWhereFallback': firstWhereFallback,
            'fold': foldValue,
            'forEach': forEachBuffer.toString(),
            'handleErrorLength': handleErrorLength,
            'isBroadcast': broadcastWrapper.isBroadcast,
            'isEmpty': isEmptyResult,
            'joinedNotEmpty': joinedValue.isNotEmpty,
            'last': lastValue,
            'lastWhere': lastWhereValue,
            'lastWhereFallback': lastWhereFallback,
            'length': lengthValue,
            'map': mapValue,
            'pipe': pipeValue,
            'reduce': reducedValue,
            'single': singleValue,
            'singleWhere': singleWhereValue,
            'singleWhereFallback': singleWhereFallback,
            'skip': skipValue,
            'skipWhile': skipWhileValue,
            'take': takeValue,
            'takeWhile': takeWhileValue,
            'timeout': timeoutValue,
            'toList': listValue,
            'toSetSize': setValue.length,
            'transform': transformedValue,
            'where': whereValue,
            'drain': drainValue,
            'any': anyResult,
          });
        });

        final response = await client.post(
          '/limited',
          'data',
          headers: {
            'X-Test': ['value'],
            HttpHeaders.cookieHeader: ['session=abc'],
            HttpHeaders.acceptEncodingHeader: ['identity'],
          },
        );
        final payload = response.json();

        expect(payload['method'], equals('POST'));
        expect(payload['path'], equals('/limited'));
        expect(payload['requestedPath'], equals('/limited'));
        expect(payload['contentLength'], isA<int>());
        expect(payload['header'], equals('value'));
        expect(payload['cookieName'], equals('session'));
        expect(payload['cookieValue'], equals('abc'));
        expect(payload['protocolVersion'], isNotEmpty);
        expect(payload['persistentConnection'], isTrue);
        expect(payload['hasCertificate'], isFalse);
        expect(payload['hasConnectionInfo'], isTrue);
        expect(payload['sameResponse'], isTrue);
        expect(payload['sameSession'], isTrue);
        expect(payload['listen'], equals('listen'));
        expect(payload['broadcast'], equals('broadcast'));
        expect(payload['onListenCalled'], isTrue);
        expect(payload['onCancelCalled'], isA<bool>());
        expect(payload['asyncExpand'], equals('expand'));
        expect(payload['asyncMap'], equals('async-map'));
        expect(payload['cast'], equals('cast'));
        expect(payload['contains'], isTrue);
        expect(payload['distinctCount'], equals(1));
        expect(payload['elementAt'], equals('element'));
        expect(payload['every'], isTrue);
        expect(payload['expandCount'], equals(2));
        expect(payload['first'], equals('first'));
        expect(payload['firstWhere'], equals('first-where'));
        expect(payload['firstWhereFallback'], equals('fallback'));
        expect(payload['fold'], equals('fold'));
        expect(payload['forEach'], equals('foreach'));
        expect(payload['handleErrorLength'], equals(0));
        expect(payload['isBroadcast'], isTrue);
        expect(payload['isEmpty'], isTrue);
        expect(payload['joinedNotEmpty'], isTrue);
        expect(payload['last'], equals('last'));
        expect(payload['lastWhere'], equals('where'));
        expect(payload['lastWhereFallback'], equals('fallback'));
        expect(payload['length'], equals(2));
        expect(payload['map'], equals('map'));
        expect(payload['pipe'], equals('pipe'));
        expect(payload['reduce'], equals('reduce'));
        expect(payload['single'], equals('single'));
        expect(payload['singleWhere'], equals('target'));
        expect(payload['singleWhereFallback'], equals('fallback'));
        expect(payload['skip'], equals('keep'));
        expect(payload['skipWhile'], equals('stay'));
        expect(payload['take'], equals('take'));
        expect(payload['takeWhile'], equals('take'));
        expect(payload['timeout'], equals('timeouted'));
        expect(payload['toList'], equals('listvalue'));
        expect(payload['toSetSize'], equals(2));
        expect(payload['transform'], equals('hi!'));
        expect(payload['where'], equals('where'));
        expect(payload['drain'], equals('done'));
        expect(payload['any'], isTrue);
      },
      transportMode: TransportMode.ephemeralServer,
    );
  });
}
