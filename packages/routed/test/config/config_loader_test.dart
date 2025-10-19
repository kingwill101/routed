import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:routed/src/config/loader.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigLoader', () {
    late MemoryFileSystem fs;
    late ConfigLoader loader;
    late String configDir;
    late String envFile;

    setUp(() {
      fs = MemoryFileSystem();
      loader = ConfigLoader(fileSystem: fs);
      configDir = '/project/config';
      envFile = '/project/.env';
      fs.directory(configDir).createSync(recursive: true);
    });

    test('applies precedence defaults < env < files < overrides', () {
      fs.file(envFile).writeAsStringSync('APP__NAME=Env App\nAPP__ENV=testing');
      fs.file(p.join(configDir, 'app.yaml')).writeAsStringSync('''
name: File App
features:
  enabled: true
''');
      fs.directory(p.join(configDir, 'testing')).createSync(recursive: true);
      fs
          .file(p.join(configDir, 'testing', 'app.toml'))
          .writeAsStringSync('debug = false');
      fs
          .file(p.join(configDir, 'database.json'))
          .writeAsStringSync('{"host": "file-host"}');

      final options = ConfigLoaderOptions(
        defaults: const {
          'app': {'name': 'Default App', 'env': 'development', 'debug': true},
        },
        configDirectory: configDir,
        envFiles: [envFile],
        environment: 'staging',
        fileSystem: fs,
      );

      final overrides = {
        'app': {'tagline': 'Runtime'},
      };

      final snapshot = loader.load(options, overrides: overrides);
      final config = snapshot.config;

      expect(snapshot.environment, equals('testing'));
      expect(config.get('app.name'), equals('File App'));
      expect(config.get('app.debug'), isFalse);
      expect(config.get('app.features.enabled'), isTrue);
      expect(config.get('app.tagline'), equals('Runtime'));
      expect(config.get('database.host'), equals('file-host'));
    });

    test('normalizes environment keys with double underscores', () {
      fs.file(envFile).writeAsStringSync('DATABASE__HOST=env-host');

      final options = ConfigLoaderOptions(
        defaults: const {
          'database': {'host': 'default-host'},
        },
        configDirectory: configDir,
        envFiles: [envFile],
        fileSystem: fs,
      );

      final snapshot = loader.load(options);
      expect(snapshot.config.get('database.host'), equals('env-host'));
    });
  });
}
