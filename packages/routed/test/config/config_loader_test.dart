import 'package:file/memory.dart';
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
      fs.file(fs.path.join(configDir, 'app.yaml')).writeAsStringSync('''
name: File App
features:
  enabled: true
''');
      fs
          .directory(fs.path.join(configDir, 'testing'))
          .createSync(recursive: true);
      fs
          .file(fs.path.join(configDir, 'testing', 'app.toml'))
          .writeAsStringSync('debug = false');
      fs
          .file(fs.path.join(configDir, 'database.json'))
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
      expect(config.get<String>('app.name'), equals('File App'));
      expect(config.get<bool>('app.debug'), isFalse);
      expect(config.get<bool>('app.features.enabled'), isTrue);
      expect(config.get<String>('app.tagline'), equals('Runtime'));
      expect(config.get<String>('database.host'), equals('file-host'));
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
      expect(snapshot.config.get<String>('database.host'), equals('env-host'));
    });

    test('uses config directory parent when configDirectory is config folder', () {
      fs
          .file(fs.path.join(configDir, 'app.yaml'))
          .writeAsStringSync('name: Demo');

      final options = ConfigLoaderOptions(
        defaults: const {
          'app': {'name': 'Default'},
        },
        configDirectory: configDir,
        fileSystem: fs,
      );

      final snapshot = loader.load(options);
      expect(snapshot.config.get<String>('app.root'), equals('/project'));
    });

    test('uses config directory itself when it is the project root', () {
      final rootDir = '/project';
      fs
          .file(fs.path.join(rootDir, 'app.yaml'))
          .writeAsStringSync('name: Root App');

      final options = ConfigLoaderOptions(
        defaults: const {
          'app': {'name': 'Default'},
        },
        configDirectory: rootDir,
        fileSystem: fs,
      );

      final snapshot = loader.load(options);
      expect(snapshot.config.get<String>('app.root'), equals(rootDir));
    });
  });
}
