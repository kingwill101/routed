import 'package:file/memory.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_views/routed_views.dart';
import 'package:test/test.dart';
import '../test_engine.dart';

void main() {
  group('ViewServiceProvider', () {
    late MemoryFileSystem fs;

    setUp(() {
      fs = MemoryFileSystem();
    });

    test('applies directory and engine from config', () async {
      final engine = testEngine(
        config: EngineConfig(fileSystem: fs),
        fileSystem: fs,
        viewConfig: RoutedViewConfig(directory: 'templates', cache: false),
      );
      addTearDown(() async => engine.close());
      await engine.initialize();

      expect(engine.config.templateDirectory, endsWith('templates'));
      expect(engine.config.views.viewPath, endsWith('templates'));
      expect(engine.config.views.cache, isFalse);
      expect(engine.config.templateEngine, isA<LiquidViewEngine>());
    });

    test('view configuration is fixed for the engine lifetime', () async {
      final engine = testEngine(
        config: EngineConfig(fileSystem: fs),
        fileSystem: fs,
        viewConfig: RoutedViewConfig(),
      );
      addTearDown(() async => engine.close());
      await engine.initialize();

      expect(engine.config.templateDirectory, endsWith('views'));
      expect(engine.config.views.viewPath, endsWith('views'));
    });
  });
}
