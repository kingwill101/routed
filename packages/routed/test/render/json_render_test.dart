import 'dart:convert';

import 'package:routed/src/render/json_render.dart';
import 'package:test/test.dart';

import 'render_test_helpers.dart';

void main() {
  group('JsonRender', () {
    test('renders JSON with content type', () {
      final harness = createRenderHarness();

      JsonRender({'ok': true}).render(harness.response);
      harness.response.writeNow();

      expect(harness.bodyAsString(), equals(jsonEncode({'ok': true})));
      expect(
        harness.response.headers.value('Content-Type'),
        equals('application/json; charset=utf-8'),
      );
    });
  });

  group('IndentedJsonRender', () {
    test('renders pretty JSON', () {
      final harness = createRenderHarness();

      IndentedJsonRender({'name': 'Routed'}).render(harness.response);
      harness.response.writeNow();

      final body = harness.bodyAsString();
      expect(body, contains('\n  "name": "Routed"\n'));
    });
  });

  group('AsciiJsonRender', () {
    test('escapes non-ascii characters', () {
      final harness = createRenderHarness();

      AsciiJsonRender({'word': 'café'}).render(harness.response);
      harness.response.writeNow();

      expect(harness.bodyAsString(), contains('caf\\u00e9'));
    });
  });

  group('JsonpRender', () {
    test('wraps JSON in callback', () {
      final harness = createRenderHarness();

      JsonpRender('handle', {'ok': true}).render(harness.response);
      harness.response.writeNow();

      expect(harness.bodyAsString(), equals('handle({"ok":true});'));
      expect(
        harness.response.headers.value('Content-Type'),
        equals('application/javascript; charset=utf-8'),
      );
    });

    test('returns plain JSON when callback is empty', () {
      final harness = createRenderHarness();

      JsonpRender('', {'ok': true}).render(harness.response);
      harness.response.writeNow();

      expect(harness.bodyAsString(), equals('{"ok":true}'));
    });
  });

  group('SecureJsonRender', () {
    test('prefixes arrays to avoid hijacking', () {
      final harness = createRenderHarness();

      SecureJsonRender([1, 2, 3]).render(harness.response);
      harness.response.writeNow();

      expect(harness.bodyAsString(), equals(")]}',\n[1,2,3]"));
    });

    test('leaves objects unchanged', () {
      final harness = createRenderHarness();

      SecureJsonRender({'ok': true}).render(harness.response);
      harness.response.writeNow();

      expect(harness.bodyAsString(), equals('{"ok":true}'));
    });
  });
}
