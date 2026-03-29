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

    test('respondWithInertiaPage writes JSON for Inertia visits', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        await respondWithInertiaPage(
          request,
          component: 'Dashboard',
          props: {'title': 'Inertia'},
          html: (page, _) async =>
              '<!doctype html>${renderInertiaBootstrap(page)}',
          version: 'dev',
        );
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dashboard?tab=1'),
      );
      request.headers.add('X-Inertia', 'true');
      request.headers.add('X-Inertia-Version', 'dev');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      expect(response.statusCode, equals(200));
      expect(
        response.headers.value('content-type'),
        equals('application/json'),
      );
      expect(body, contains('"component":"Dashboard"'));
      expect(body, contains('"url":"/dashboard?tab=1"'));
      expect(body, contains('"version":"dev"'));
    });

    test('respondWithInertiaPage writes HTML for first visits', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        await respondWithInertiaPage(
          request,
          component: 'Home',
          props: {'title': 'Inertia'},
          html: (page, _) => renderInertiaVitePageHtml(
            page,
            assets: const InertiaViteAssets(
              entry: 'index.html',
              manifestPath: '/tmp/does-not-exist.manifest.json',
              hotFile: '/tmp/does-not-exist.hot',
              fallbackScript: '/assets/app.js',
            ),
            title: 'Inertia Home',
          ),
        );
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      expect(
        response.headers.value('content-type'),
        equals('text/html; charset=utf-8'),
      );
      expect(body, contains('<title>Inertia Home</title>'));
      expect(
        body,
        contains('<script data-page="app" type="application/json">'),
      );
      expect(body, contains('<div id="app"></div>'));
      expect(
        body,
        contains('<script type="module" src="/assets/app.js"></script>'),
      );
    });

    test('renderInertiaVitePageHtml includes SSR head and body', () async {
      final html = await renderInertiaVitePageHtml(
        PageData(component: 'Home', props: const {}, url: '/'),
        assets: const InertiaViteAssets(
          entry: 'index.html',
          manifestPath: '/tmp/does-not-exist.manifest.json',
          hotFile: '/tmp/does-not-exist.hot',
          fallbackScript: '/assets/app.js',
        ),
        title: 'SSR Demo',
        ssr: const SsrResponse(
          body: '<main>Server Rendered</main>',
          head: '<meta name="ssr" content="true">',
        ),
      );

      expect(html, contains('<meta name="ssr" content="true">'));
      expect(
        html,
        contains('<div id="app"><main>Server Rendered</main></div>'),
      );
      expect(html, contains('<title>SSR Demo</title>'));
    });

    test('tryWriteStaticAsset serves files from the configured root', () async {
      final directory = await Directory.systemTemp.createTemp(
        'inertia_http_assets_',
      );
      addTearDown(() => directory.delete(recursive: true));

      final assetDirectory = Directory('${directory.path}/assets');
      await assetDirectory.create();
      final asset = File('${assetDirectory.path}/app.js');
      await asset.writeAsString('console.log("inertia");');

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        if (await tryWriteStaticAsset(request, rootDirectory: directory.path)) {
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/assets/app.js'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      expect(response.statusCode, equals(200));
      expect(
        response.headers.value('content-type'),
        equals('application/javascript'),
      );
      expect(body, equals('console.log("inertia");'));
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
