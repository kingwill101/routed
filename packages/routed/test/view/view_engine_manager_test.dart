import 'package:routed/src/view/engine_manager.dart';
import 'package:routed/src/view/view_engine.dart';
import 'package:test/test.dart';

class FakeViewEngine implements ViewEngine {
  FakeViewEngine(this.label, {required this.extensions});

  final String label;

  @override
  final List<String> extensions;

  String? lastRenderName;
  Map<String, dynamic>? lastRenderData;

  @override
  Future<String> render(String name, [Map<String, dynamic>? data]) async {
    lastRenderName = name;
    lastRenderData = data;
    return '$label:$name';
  }

  @override
  Future<String> renderFile(
    String filePath, [
    Map<String, dynamic>? data,
  ]) async {
    lastRenderName = filePath;
    lastRenderData = data;
    return '$label:$filePath';
  }
}

void main() {
  group('ViewEngineManager', () {
    test('registers engines by extension', () async {
      final manager = ViewEngineManager();
      final engine = FakeViewEngine('alpha', extensions: ['.foo', '.bar']);

      manager.register(engine);

      expect(manager.engineForFile('template.foo'), equals(engine));
      expect(manager.engineForFile('template.bar'), equals(engine));
      expect(manager.engineForFile('template.baz'), isNull);
    });

    test('renders through the matching engine', () async {
      final manager = ViewEngineManager();
      final engine = FakeViewEngine('beta', extensions: ['.liquid']);
      manager.register(engine);

      final result = await manager.render('welcome.liquid', {'name': 'Rae'});

      expect(result, equals('beta:welcome.liquid'));
      expect(engine.lastRenderName, equals('welcome.liquid'));
      expect(engine.lastRenderData?['name'], equals('Rae'));
    });

    test('renders files through the matching engine', () async {
      final manager = ViewEngineManager();
      final engine = FakeViewEngine('gamma', extensions: ['.tmpl']);
      manager.register(engine);

      final result = await manager.renderFile('/templates/card.tmpl');

      expect(result, equals('gamma:/templates/card.tmpl'));
      expect(engine.lastRenderName, equals('/templates/card.tmpl'));
    });

    test('throws when no engine matches', () async {
      final manager = ViewEngineManager();

      expect(
        () => manager.render('missing.mustache'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
