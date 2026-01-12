import 'dart:convert';

import 'package:routed/src/render/reader_render.dart';
import 'package:test/test.dart';

import 'render_test_helpers.dart';

void main() {
  group('ReaderRender', () {
    test('streams content with headers', () async {
      final harness = createRenderHarness();
      harness.response.headers.set('X-Existing', 'keep');

      final renderer = ReaderRender(
        contentType: 'text/plain; charset=utf-8',
        contentLength: 5,
        reader: Stream.value(utf8.encode('hello')),
        headers: {'X-Existing': 'override', 'X-New': 'value'},
      );

      await renderer.render(harness.response);

      expect(harness.bodyAsString(), equals('hello'));
      expect(
        harness.response.headers.value('Content-Type'),
        equals('text/plain; charset=utf-8'),
      );
      expect(harness.response.headers.value('Content-Length'), equals('5'));
      expect(harness.response.headers.value('X-Existing'), equals('keep'));
      expect(harness.response.headers.value('X-New'), equals('value'));
    });
  });
}
