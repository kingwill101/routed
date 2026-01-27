/// Tests for dart:io HTTP helpers.
library;

import 'dart:convert';
import 'dart:io';

import 'package:inertia_dart/inertia_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Inertia HTTP helpers', () {
    test('inertiaRequestFromHttp captures method, url, and headers', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      InertiaRequest? captured;
      server.listen((request) async {
        captured = inertiaRequestFromHttp(request);
        final response = InertiaResponse.json(
          PageData(component: 'Home', props: const {}, url: '/home'),
        );
        await writeInertiaResponse(request.response, response);
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/home?tab=1'),
      );
      request.headers.add('X-Inertia', 'true');
      request.headers.add('X-Inertia-Version', '1');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      expect(captured, isNotNull);
      expect(captured!.method, equals('GET'));
      expect(captured!.url, equals('/home?tab=1'));
      final headerKeys = captured!.headers.keys.map((key) => key.toLowerCase());
      expect(headerKeys, contains('x-inertia'));
      expect(body, contains('"component":"Home"'));
    });

    test('writeInertiaResponse writes HTML body', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        final page = PageData(component: 'Html', props: const {}, url: '/html');
        final response = InertiaResponse.html(page, '<div>Html</div>');
        await writeInertiaResponse(request.response, response);
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/html'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      expect(
        response.headers.value('content-type'),
        equals('text/html; charset=utf-8'),
      );
      expect(body, equals('<div>Html</div>'));
    });

    test(
      'writeInertiaResponse closes immediately for location responses',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((request) async {
          final response = InertiaResponse.location('/redirect');
          await writeInertiaResponse(request.response, response);
        });

        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/redirect'),
        );
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        expect(response.statusCode, equals(409));
        expect(body, isEmpty);
      },
    );
  });
}
