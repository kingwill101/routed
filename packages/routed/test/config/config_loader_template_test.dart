import 'package:file/memory.dart';
import 'package:routed/src/config/loader.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigLoader liquid templates', () {
    test('renders {{ VAR }} placeholders using .env values', () {
      final fs = MemoryFileSystem.test();
      fs.file('.env')
        ..createSync(recursive: true)
        ..writeAsStringSync('NAME=Routed');
      fs.directory('config').createSync();
      fs.file('config/app.yaml')
        ..createSync()
        ..writeAsStringSync('greeting: "Hello {{ NAME }}!"');

      final loader = ConfigLoader(fileSystem: fs);
      final options = ConfigLoaderOptions(
        configDirectory: 'config',
        envFiles: ['.env'],
        fileSystem: fs,
      );

      final snapshot = loader.load(options);
      expect(snapshot.config.get('app.greeting'), equals('Hello Routed!'));
    });

    test('renders {{ env.VAR }} placeholders using .env values', () {
      final fs = MemoryFileSystem.test();
      fs.file('.env')
        ..createSync(recursive: true)
        ..writeAsStringSync('NAME=Platform');
      fs.directory('config').createSync();
      fs.file('config/app.yaml')
        ..createSync()
        ..writeAsStringSync('greeting: "Hello {{ env.NAME }}!"');

      final loader = ConfigLoader(fileSystem: fs);
      final options = ConfigLoaderOptions(
        configDirectory: 'config',
        envFiles: ['.env'],
        fileSystem: fs,
      );

      final snapshot = loader.load(options);
      expect(snapshot.config.get('app.greeting'), equals('Hello Platform!'));
    });

    test(
      'renders placeholders in JSON configs using environment variables',
      () {
        final fs = MemoryFileSystem.test();
        fs.directory('config').createSync();
        fs.file('config/app.json')
          ..createSync()
          ..writeAsStringSync('{"secret": "{{ env.APP_SECRET }}"}');

        final loader = ConfigLoader(fileSystem: fs);
        final options = ConfigLoaderOptions(
          configDirectory: 'config',
          envFiles: const [],
          fileSystem: fs,
        );

        final snapshot = loader.load(
          options,
          overrides: const {'APP_SECRET': 'inline-secret'},
        );

        expect(snapshot.config.get('app.secret'), equals('inline-secret'));
      },
    );

    test('supports nested context lookups from double underscore env keys', () {
      final fs = MemoryFileSystem.test();
      fs.file('.env')
        ..createSync(recursive: true)
        ..writeAsStringSync('SESSION__CONFIG__APP_KEY=liquid-key');
      fs.directory('config').createSync();
      fs.file('config/session.yaml')
        ..createSync()
        ..writeAsStringSync('app_key: "{{ session.config.app_key }}"');

      final loader = ConfigLoader(fileSystem: fs);
      final options = ConfigLoaderOptions(
        configDirectory: 'config',
        envFiles: ['.env'],
        fileSystem: fs,
      );

      final snapshot = loader.load(options);
      expect(snapshot.config.get('session.app_key'), equals('liquid-key'));
    });

    test('applies liquid filters before decoding config files', () {
      final fs = MemoryFileSystem.test();
      fs.directory('config').createSync();
      fs.file('config/app.yaml')
        ..createSync()
        ..writeAsStringSync('greeting: "{{ GREETING | default: "Hello" }}"');

      final loader = ConfigLoader(fileSystem: fs);
      final options = ConfigLoaderOptions(
        configDirectory: 'config',
        envFiles: const [],
        fileSystem: fs,
      );

      final snapshot = loader.load(options);
      expect(snapshot.config.get('app.greeting'), equals('Hello'));
    });

    test('renders list entries with double-underscore env keys', () {
      final fs = MemoryFileSystem.test();
      fs.file('.env')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          [
            'STATIC__MOUNTS__0__ROUTE=/assets',
            'STATIC__MOUNTS__0__DISK=assets',
            'STATIC__MOUNTS__0__PATH=public/assets',
          ].join('\n'),
        );
      fs.directory('config').createSync();
      fs.file('config/static.yaml')
        ..createSync()
        ..writeAsStringSync('''
mounts:
  - route: "{{ static.mounts[0].route | default: '/assets' }}"
    disk: "{{ static.mounts[0].disk | default: 'assets' }}"
    path: "{{ static.mounts[0].path | default: '' }}"
''');

      final loader = ConfigLoader(fileSystem: fs);
      final options = ConfigLoaderOptions(
        configDirectory: 'config',
        envFiles: ['.env'],
        fileSystem: fs,
      );

      final snapshot = loader.load(options);
      final mounts = snapshot.config.get('static.mounts') as List;
      expect(mounts, hasLength(1));
      final first = Map<String, dynamic>.from(mounts.first as Map);
      expect(first['route'], equals('/assets'));
      expect(first['disk'], equals('assets'));
      expect(first['path'], equals('public/assets'));
    });
  });
}
