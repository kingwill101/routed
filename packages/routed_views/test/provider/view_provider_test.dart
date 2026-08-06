import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed_view/routed_view.dart';
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
        configItems: {
          'view': {
            'engine': 'liquid',
            'directory': 'templates',
            'cache': false,
          },
        },
        providers: [ViewServiceProvider()],
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      expect(engine.config.templateDirectory, endsWith('templates'));
      expect(engine.config.views.viewPath, endsWith('templates'));
      expect(engine.config.views.cache, isFalse);
      expect(engine.config.templateEngine, isA<LiquidViewEngine>());
    });

    test('config reload updates template directory', () async {
      final engine = testEngine(
        config: EngineConfig(fileSystem: fs),
        fileSystem: fs,
        configItems: {
          'view': {'directory': 'views'},
        },
        providers: [ViewServiceProvider()],
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final override = ConfigImpl();
      override.merge(engine.appConfig.all());
      override.set('view', {'directory': 'shared/views'});

      await engine.replaceConfig(override);
      await Future<void>.delayed(Duration.zero);

      expect(
        engine.config.templateDirectory,
        endsWith(fs.path.join('shared', 'views')),
      );
      expect(
        engine.config.views.viewPath,
        endsWith(fs.path.join('shared', 'views')),
      );
    });

  });
}
