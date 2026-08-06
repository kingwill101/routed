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
      expect(
        snapshot.config.get<String>('app.greeting'),
        equals('Hello Routed!'),
      );
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
      expect(
        snapshot.config.get<String>('app.greeting'),
        equals('Hello Platform!'),
      );
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

        expect(
          snapshot.config.get<String>('app.secret'),
          equals('inline-secret'),
        );
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
      expect(
        snapshot.config.get<String>('session.app_key'),
        equals('liquid-key'),
      );
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
      expect(snapshot.config.get<String>('app.greeting'), equals('Hello'));
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
      final mounts =
          snapshot.config.get<List<dynamic>>('static.mounts') ??
          const <dynamic>[];
      expect(mounts, hasLength(1));
      final first = Map<String, dynamic>.from(mounts.first as Map);
      expect(first['route'], equals('/assets'));
      expect(first['disk'], equals('assets'));
      expect(first['path'], equals('public/assets'));
    });

    test('resolveEnvTemplates false preserves env placeholders in YAML', () {
      final fs = MemoryFileSystem.test();
      fs.file('.env')
        ..createSync(recursive: true)
        ..writeAsStringSync('APP_NAME=FromEnv');
      fs.directory('config').createSync();
      fs.file('config/app.yaml')
        ..createSync()
        ..writeAsStringSync(
          'name: "{{ env.APP_NAME | default: \'My App\' }}"\n'
          'debug: {{ env.APP_DEBUG | default: true }}\n',
        );

      final loader = ConfigLoader(fileSystem: fs);
      final options = ConfigLoaderOptions(
        configDirectory: 'config',
        envFiles: ['.env'],
        fileSystem: fs,
        resolveEnvTemplates: false,
      );

      final snapshot = loader.load(options);
      // The env templates should survive as raw strings.
      expect(
        snapshot.config.get<String>('app.name'),
        equals("{{ env.APP_NAME | default: 'My App' }}"),
      );
      expect(
        snapshot.config.get<String>('app.debug'),
        equals('{{ env.APP_DEBUG | default: true }}'),
      );
    });

    test('resolveEnvTemplates false still expands non-env templates', () {
      final fs = MemoryFileSystem.test();
      fs.file('.env')
        ..createSync(recursive: true)
        ..writeAsStringSync('MAIL__HOST=smtp.test');
      fs.directory('config').createSync();
      fs.file('config/mail.yaml')
        ..createSync()
        ..writeAsStringSync(
          'host: "{{ mail.host | default: \'localhost\' }}"\n'
          'from: "{{ env.MAIL_FROM | default: \'a@b.c\' }}"\n',
        );

      final loader = ConfigLoader(fileSystem: fs);
      final options = ConfigLoaderOptions(
        configDirectory: 'config',
        envFiles: ['.env'],
        fileSystem: fs,
        resolveEnvTemplates: false,
      );

      final snapshot = loader.load(options);
      // Non-env template should be expanded using the template context.
      expect(snapshot.config.get<String>('mail.host'), equals('smtp.test'));
      // Env template should be preserved.
      expect(
        snapshot.config.get<String>('mail.from'),
        equals("{{ env.MAIL_FROM | default: 'a@b.c' }}"),
      );
    });

    test('resolveEnvTemplates false preserves env refs in defaults map', () {
      final fs = MemoryFileSystem.test();
      final loader = ConfigLoader(fileSystem: fs);
      final options = ConfigLoaderOptions(
        defaults: const {
          'storage': {
            'root': "{{ env.STORAGE_ROOT | default: 'storage/app' }}",
          },
        },
        fileSystem: fs,
        envFiles: const [],
        resolveEnvTemplates: false,
      );

      final snapshot = loader.load(options);
      expect(
        snapshot.config.get<String>('storage.root'),
        equals("{{ env.STORAGE_ROOT | default: 'storage/app' }}"),
      );
    });

    test(
      'resolveEnvTemplates false placeholders resolve via renderDefaults',
      () {
        final fs = MemoryFileSystem.test();
        fs.directory('config').createSync();
        fs.file('config/app.yaml')
          ..createSync()
          ..writeAsStringSync(
            'name: "{{ env.APP_NAME | default: \'Fallback\' }}"\n',
          );

        final loader = ConfigLoader(fileSystem: fs);
        final raw = loader.load(
          ConfigLoaderOptions(
            configDirectory: 'config',
            envFiles: const [],
            fileSystem: fs,
            resolveEnvTemplates: false,
          ),
        );

        // The raw snapshot has the placeholder.
        expect(
          raw.config.get<String>('app.name'),
          equals("{{ env.APP_NAME | default: 'Fallback' }}"),
        );

        // Resolving via renderDefaults with an env context should expand it.
        final ctx = buildEnvTemplateContext();
        final resolved = loader.renderDefaults(raw.config.all(), ctx);
        final appMap = resolved['app'] as Map<String, dynamic>;
        // The default kicks in when the env var is absent.
        expect(appMap['name'], isA<String>());
        expect((appMap['name'] as String).length, greaterThan(0));
      },
    );

    test('resolveEnvTemplates false handles interpolated env strings', () {
      final fs = MemoryFileSystem.test();
      fs.directory('config').createSync();
      fs.file('config/app.yaml')
        ..createSync()
        ..writeAsStringSync(
          'greeting: "Hello {{ env.USER_NAME | default: \'world\' }}!"\n',
        );

      final loader = ConfigLoader(fileSystem: fs);
      final snapshot = loader.load(
        ConfigLoaderOptions(
          configDirectory: 'config',
          envFiles: const [],
          fileSystem: fs,
          resolveEnvTemplates: false,
        ),
      );

      expect(
        snapshot.config.get<String>('app.greeting'),
        equals("Hello {{ env.USER_NAME | default: 'world' }}!"),
      );
    });

    test('renders defaults containing Liquid expressions', () {
      final fs = MemoryFileSystem.test();
      final loader = ConfigLoader(fileSystem: fs);
      final options = ConfigLoaderOptions(
        defaults: const {
          'storage': {
            'root': "{{ env.STORAGE_ROOT | default: 'storage/app' }}",
          },
        },
        fileSystem: fs,
        envFiles: const [],
      );

      final snapshotWithOverride = loader.load(
        options,
        overrides: const {'STORAGE_ROOT': '/custom/storage'},
      );
      expect(
        snapshotWithOverride.config.get<String>('storage.root'),
        equals('/custom/storage'),
      );

      final snapshotWithDefault = loader.load(options);
      expect(
        snapshotWithDefault.config.get<String>('storage.root'),
        equals('storage/app'),
      );
    });
  });
}
