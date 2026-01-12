import 'dart:convert';
import 'dart:io';

import 'package:routed/src/render/data_render.dart';
import 'package:routed/src/render/redirect.dart';
import 'package:routed/src/render/string_render.dart';
import 'package:routed/src/render/xml.dart';
import 'package:routed/src/render/yaml.dart';
import 'package:test/test.dart';

import 'render_test_helpers.dart';

void main() {
  group('StringRender', () {
    test('writes plain text', () {
      final harness = createRenderHarness();

      StringRender('hello').render(harness.response);
      harness.response.writeNow();

      expect(harness.bodyAsString(), equals('hello'));
      expect(
        harness.response.headers.value('Content-Type'),
        equals('text/plain; charset=utf-8'),
      );
    });
  });

  group('DataRender', () {
    test('writes binary data', () {
      final harness = createRenderHarness();
      final payload = utf8.encode('binary');

      DataRender('application/octet-stream', payload).render(harness.response);
      harness.response.writeNow();

      expect(harness.bodyAsString(), equals('binary'));
      expect(
        harness.response.headers.value('Content-Type'),
        equals('application/octet-stream'),
      );
    });
  });

  group('XmlRender', () {
    test('renders maps and lists as XML', () {
      final harness = createRenderHarness();

      XmlRender({
        'user': {
          'name': 'Ada',
          'roles': ['admin'],
        },
      }).render(harness.response);
      harness.response.writeNow();

      final body = harness.bodyAsString();
      expect(body, contains('<user>'));
      expect(body, contains('<name>Ada</name>'));
      expect(body, contains('<item>admin</item>'));
      expect(
        harness.response.headers.value('Content-Type'),
        equals('application/xml; charset=utf-8'),
      );
    });
  });

  group('YamlRender', () {
    test('renders YAML output', () {
      final harness = createRenderHarness();

      YamlRender({'feature': 'cache'}).render(harness.response);
      harness.response.writeNow();

      expect(harness.bodyAsString(), contains('feature: cache'));
      expect(
        harness.response.headers.value('Content-Type'),
        equals('application/x-yaml; charset=utf-8'),
      );
    });
  });

  group('RedirectRender', () {
    test('sets status and location header', () {
      final harness = createRenderHarness();

      RedirectRender(
        code: HttpStatus.found,
        location: '/login',
      ).render(harness.response);

      expect(harness.response.statusCode, equals(HttpStatus.found));
      expect(
        harness.response.headers.value(HttpHeaders.locationHeader),
        equals('/login'),
      );
    });

    test('throws for invalid status codes', () {
      final harness = createRenderHarness();

      expect(
        () => RedirectRender(
          code: 200,
          location: '/bad',
        ).render(harness.response),
        throwsA(isA<Exception>()),
      );
    });
  });
}
