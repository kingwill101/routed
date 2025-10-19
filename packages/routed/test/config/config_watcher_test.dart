import 'dart:async';
import 'dart:io';

import 'package:file/local.dart' as local;
import 'package:path/path.dart' as p;
import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('Config watcher', () {
    late Directory tempDir;
    late String configDir;
    late String envFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('routed_config_test');
      configDir = p.join(tempDir.path, 'config');
      envFile = p.join(tempDir.path, '.env');
      Directory(configDir).createSync(recursive: true);
      File(
        p.join(configDir, 'app.yaml'),
      ).writeAsStringSync('name: Initial\n', flush: true);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('reloads configuration when tracked files change', () async {
      final engine = Engine(
        configOptions: ConfigLoaderOptions(
          defaults: const {
            'app': {'name': 'Default App', 'env': 'development'},
          },
          configDirectory: configDir,
          envFiles: [envFile],
          watch: true,
          watchDebounce: const Duration(milliseconds: 50),
          fileSystem: const local.LocalFileSystem(),
        ),
      );

      await engine.initialize();
      addTearDown(() async {
        await engine.close();
      });

      final eventManager = await engine.make<EventManager>();
      final reloadCompleter = Completer<ConfigReloadedEvent>();
      eventManager.on<ConfigReloadedEvent>().listen((event) {
        if (event.config.get('app.name') == 'Updated') {
          if (!reloadCompleter.isCompleted) {
            reloadCompleter.complete(event);
          }
        }
      });

      await Future<void>.delayed(const Duration(milliseconds: 100));

      File(
        p.join(configDir, 'app.yaml'),
      ).writeAsStringSync('name: Updated\n', flush: true);

      final event = await reloadCompleter.future.timeout(
        const Duration(seconds: 2),
      );

      expect(event.metadata['source'], isNotEmpty);
      final config = await engine.make<Config>();
      expect(config.get('app.name'), equals('Updated'));
    });
  });
}
