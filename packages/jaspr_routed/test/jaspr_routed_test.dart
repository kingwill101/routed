import 'dart:convert';
import 'dart:io';

import 'package:jaspr/jaspr.dart';
import 'package:jaspr_routed/jaspr_routed.dart';
import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    Jaspr.initializeApp();
  });

  group('jasprRoute', () {
    test('renders Jaspr component and exposes EngineContext', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final requestStream = server.asBroadcastStream();

      final handler = jasprRoute((ctx) => const EchoComponent());

      final uri = Uri.http('localhost:${server.port}', '/hello');
      final responseFuture = () async {
        final req = await client.getUrl(uri);
        return req.close();
      }();

      final httpRequest = await requestStream.first;
      final ctx = _createContext(httpRequest);
      await handler(ctx);

      final response = await responseFuture;
      final body = await utf8.decodeStream(response);

      expect(response.statusCode, equals(HttpStatus.ok));
      expect(body, contains('Method: GET Uri: /hello'));
    });

    test('reuses route handler across multiple requests', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      var callCount = 0;
      final handler = jasprRoute((ctx) {
        callCount++;
        return CounterComponent(callCount);
      });

      final uri = Uri.http('localhost:${server.port}', '/count');
      final requestStream = server.asBroadcastStream();

      Future<String> sendRequest() async {
        final responseFuture = () async {
          final req = await client.getUrl(uri);
          return req.close();
        }();

        final httpRequest = await requestStream.first;
        final ctx = _createContext(httpRequest);
        await handler(ctx);

        final response = await responseFuture;
        expect(response.statusCode, equals(HttpStatus.ok));
        return utf8.decodeStream(response);
      }

      final firstBody = await sendRequest();
      final secondBody = await sendRequest();

      expect(firstBody, contains('Call #1'));
      expect(secondBody, contains('Call #2'));
    });
  });
}

EngineContext _createContext(HttpRequest httpRequest) {
  final container = Container();
  final request = Request(httpRequest, {}, EngineConfig());
  final response = Response(httpRequest.response);
  final ctx = EngineContext(
    request: request,
    response: response,
    container: container,
  );
  container
    ..instance<Request>(request)
    ..instance<Response>(response)
    ..instance<EngineContext>(ctx);
  return ctx;
}

class EchoComponent extends StatelessComponent {
  const EchoComponent();

  @override
  Component build(BuildContext context) {
    final engine = context.engineContext;
    return Component.text('Method: ${engine.method} Uri: ${engine.uri.path}');
  }
}

class CounterComponent extends StatelessComponent {
  const CounterComponent(this.callCount);

  final int callCount;

  @override
  Component build(BuildContext context) {
    return Component.text('Call #$callCount');
  }
}
