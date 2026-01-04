import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('ViewServiceProvider', () {
    test('applies directory and engine from config', () async {
      final engine = Engine(
        configItems: {
          'view': {
            'engine': 'liquid',
            'directory': 'templates',
            'cache': false,
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      expect(engine.config.templateDirectory, endsWith('templates'));
      expect(engine.config.views.viewPath, endsWith('templates'));
      expect(engine.config.views.cache, isFalse);
      expect(engine.config.templateEngine, isA<LiquidViewEngine>());
    });

    test('config reload updates template directory', () async {
      final engine = Engine(
        configItems: {
          'view': {'directory': 'views'},
        },
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
        endsWith(p.join('shared', 'views')),
      );
      expect(engine.config.views.viewPath, endsWith(p.join('shared', 'views')));
    });

    test('resolves directory via storage disk', () async {
      final tempDir = Directory.systemTemp.createTempSync('routed_view_disk');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final engine = Engine(
        configItems: {
          'storage': {
            'default': 'templates',
            'disks': {
              'templates': {'driver': 'local', 'root': tempDir.path},
            },
          },
          'view': {
            'engine': 'liquid',
            'disk': 'templates',
            'directory': 'emails',
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      expect(
        engine.config.templateDirectory,
        equals(p.normalize('${tempDir.path}/emails')),
      );
      expect(
        engine.config.views.viewPath,
        equals(p.normalize('${tempDir.path}/emails')),
      );
    });
  });
}
