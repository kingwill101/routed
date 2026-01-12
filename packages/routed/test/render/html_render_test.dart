import 'dart:io';

import 'package:routed/src/render/html.dart';
import 'package:routed/src/view/view_engine.dart';
import 'package:test/test.dart';

import 'render_test_helpers.dart';

class FakeViewEngine implements ViewEngine {
  FakeViewEngine({required this.result});

  final String result;
  String? lastTemplate;
  Map<String, dynamic>? lastData;
  Object? error;

  @override
  List<String> get extensions => ['.fake'];

  @override
  Future<String> render(String name, [Map<String, dynamic>? data]) async {
    lastTemplate = name;
    lastData = data;
    if (error != null) {
      throw error!;
    }
    return result;
  }

  @override
  Future<String> renderFile(
    String filePath, [
    Map<String, dynamic>? data,
  ]) async {
    lastTemplate = filePath;
    lastData = data;
    if (error != null) {
      throw error!;
    }
    return result;
  }
}

void main() {
  group('HtmlRender', () {
    test('renders inline content via engine', () async {
      final harness = createRenderHarness();
      final engine = FakeViewEngine(result: '<h1>Hello</h1>');

      final render = HtmlRender(
        content: '<h1>{{ title }}</h1>',
        data: {'title': 'Hello'},
        engine: engine,
      );

      await render.render(harness.response);
      harness.response.writeNow();

      expect(harness.bodyAsString(), equals('<h1>Hello</h1>'));
      expect(engine.lastTemplate, equals('<h1>{{ title }}</h1>'));
      expect(engine.lastData?['title'], equals('Hello'));
      expect(
        harness.response.headers.value('Content-Type'),
        equals('text/html; charset=utf-8'),
      );
    });

    test('renders template files via engine', () async {
      final harness = createRenderHarness();
      final engine = FakeViewEngine(result: '<p>Hi</p>');

      final render = HtmlRender(
        templateName: 'welcome.liquid',
        data: {'user': 'Ada'},
        engine: engine,
      );

      await render.render(harness.response);
      harness.response.writeNow();

      expect(harness.bodyAsString(), equals('<p>Hi</p>'));
      expect(engine.lastTemplate, equals('welcome.liquid'));
      expect(engine.lastData?['user'], equals('Ada'));
    });

    test('returns 404 when no template data provided', () async {
      final harness = createRenderHarness();
      final engine = FakeViewEngine(result: 'unused');

      final render = HtmlRender(data: {}, engine: engine);

      await render.render(harness.response);
      harness.response.writeNow();

      expect(harness.response.statusCode, equals(HttpStatus.notFound));
      expect(harness.bodyAsString(), equals(''));
    });

    test('handles engine errors with 500 response', () async {
      final harness = createRenderHarness();
      final engine = FakeViewEngine(result: 'unused')
        ..error = StateError('boom');

      final render = HtmlRender(
        content: '<p>fail</p>',
        data: const {},
        engine: engine,
      );

      await render.render(harness.response);
      harness.response.writeNow();

      expect(
        harness.response.statusCode,
        equals(HttpStatus.internalServerError),
      );
      expect(harness.bodyAsString(), contains('Error rendering template'));
    });
  });
}
