import 'dart:io' show SameSite;

import 'package:file/memory.dart';
import 'package:routed/providers.dart';
import 'package:routed/routed.dart';
import 'package:routed/session.dart';
import 'package:test/test.dart';
import '../test_engine.dart';

void main() {
  group('SessionServiceProvider', () {
    late MemoryFileSystem fs;

    setUp(() {
      fs = MemoryFileSystem();
    });

    test('configures cookie driver with extended options', () async {
      final appKey = SecureCookie.generateKey();
      final engine = testEngine(
        configItems: {
          'app': {'name': 'Demo App', 'key': appKey},
          'session': {
            'enabled': true,
            'driver': 'cookie',
            'cookie': 'demo_session',
            'lifetime': 90,
            'expire_on_close': true,
            'http_only': false,
            'same_site': 'strict',
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final config = await engine.make<SessionConfig>();
      expect(config.cookieName, equals('demo_session'));
      expect(config.maxAge, equals(const Duration(minutes: 90)));
      expect(config.expireOnClose, isTrue);
      expect(config.defaultOptions.maxAge, isNull);
      expect(config.defaultOptions.sameSite, equals(SameSite.strict));
      expect(config.httpOnly, isFalse);
      expect(config.store, isA<CookieStore>());
      expect(config.codecs, isNotEmpty);
    });

    test('configures file driver with lottery', () async {
      final appKey = SecureCookie.generateKey();
      final temp = fs.systemTempDirectory.createTempSync('session_store');
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });

      final engine = testEngine(
        config: EngineConfig(fileSystem: fs),
        fileSystem: fs,
        configItems: {
          'app': {'key': appKey},
          'session': {
            'enabled': true,
            'driver': 'file',
            'files': temp.path,
            'lottery': [1, 2],
            'path': '/app',
            'secure': true,
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final config = await engine.make<SessionConfig>();
      expect(config.store, isA<FilesystemStore>());
      final store = config.store as FilesystemStore;
      expect(store.storageDir, equals(temp.path));
      expect(store.lottery, equals([1, 2]));
      expect(config.defaultOptions.path, equals('/app'));
      expect(config.defaultOptions.secure, isTrue);
    });

    test('configures cache-backed driver using cache store', () async {
      final appKey = SecureCookie.generateKey();
      final engine = testEngine(
        configItems: {
          'app': {'key': appKey},
          'cache': {
            'default': 'session',
            'stores': {
              'session': {'driver': 'array'},
            },
          },
          'session': {
            'enabled': true,
            'driver': 'redis',
            'store': 'session',
            'cache_prefix': 'sess:',
            'same_site': 'none',
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final config = await engine.make<SessionConfig>();
      expect(config.store, isA<CacheSessionStore>());
      final store = config.store as CacheSessionStore;
      expect(store.cachePrefix, equals('sess:'));
      expect(config.defaultOptions.sameSite, equals(SameSite.none));
    });

    test('configures array driver with in-memory store', () async {
      final appKey = SecureCookie.generateKey();
      final engine = testEngine(
        configItems: {
          'app': {'key': appKey},
          'session': {
            'enabled': true,
            'driver': 'array',
            'lifetime': 30,
            'http_only': true,
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final config = await engine.make<SessionConfig>();
      expect(config.store, isA<MemorySessionStore>());
      expect(config.maxAge, equals(const Duration(minutes: 30)));
      expect(config.httpOnly, isTrue);
    });

    test('throws when no key is configured', () {
      expect(
        () => testEngine(
          configItems: {
            'app': {'key': ''},
            'session': {'enabled': true, 'driver': 'cookie'},
          },
        ),
        throwsA(isA<ProviderConfigException>()),
      );
    });

    test('rebuilds session config on config reload', () async {
      final appKey = SecureCookie.generateKey();
      final engine = testEngine(
        configItems: {
          'app': {'key': appKey},
          'session': {
            'enabled': true,
            'driver': 'cookie',
            'cookie': 'initial',
            'lifetime': 45,
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final before = await engine.make<SessionConfig>();
      expect(before.cookieName, equals('initial'));
      expect(before.maxAge, equals(const Duration(minutes: 45)));
      expect(before.store, isA<CookieStore>());

      final override = ConfigImpl();
      override.merge(engine.appConfig.all());
      override.set('session', {
        'enabled': true,
        'driver': 'array',
        'cookie': 'runtime',
        'lifetime': 10,
        'http_only': false,
      });

      await engine.replaceConfig(override);

      final after = await engine.make<SessionConfig>();
      expect(after.cookieName, equals('runtime'));
      expect(after.maxAge, equals(const Duration(minutes: 10)));
      expect(after.httpOnly, isFalse);
      expect(after.store, isA<MemorySessionStore>());
    });

    test(
      'removes managed session config when session config removed',
      () async {
        final appKey = SecureCookie.generateKey();
        final engine = testEngine(
          configItems: {
            'app': {'key': appKey},
            'session': {'enabled': true, 'driver': 'cookie'},
          },
        );
        addTearDown(() async => await engine.close());
        await engine.initialize();

        expect(engine.container.has<SessionConfig>(), isTrue);

        final override = ConfigImpl();
        override.merge(engine.appConfig.all());
        override.set('session', null);

        await engine.replaceConfig(override);

        expect(engine.container.has<SessionConfig>(), isFalse);
      },
    );

    test('documents built-in session driver options', () {
      final provider = SessionServiceProvider();
      final docPaths = provider.defaultConfig.docs
          .map((entry) => entry.path)
          .toSet();
      expect(
        docPaths.containsAll(<String>[
          'session.encrypt',
          'session.files',
          'session.store',
        ]),
        isTrue,
      );
    });

    test('registerDriver enables custom session driver', () async {
      SessionServiceProvider.registerDriver('custom', (context) {
        final options = context.options.copyWith(partitioned: true);
        return SessionConfig.cookie(
          codecs: context.codecs,
          cookieName: context.cookieName,
          maxAge: context.lifetime,
          expireOnClose: context.expireOnClose,
          options: options,
        );
      }, overrideExisting: true);
      addTearDown(() {
        SessionServiceProvider.unregisterDriver('custom');
      });

      final appKey = SecureCookie.generateKey();
      final engine = testEngine(
        configItems: {
          'app': {'key': appKey},
          'session': {
            'enabled': true,
            'driver': 'custom',
            'cookie': 'custom-session',
            'partitioned': false,
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final config = await engine.make<SessionConfig>();
      expect(config.cookieName, equals('custom-session'));
      expect(config.partitioned, isTrue);
      expect(config.store, isA<CookieStore>());
    });

    test(
      'custom driver override takes precedence over built-in cookie',
      () async {
        SessionServiceProvider.unregisterDriver('cookie');
        SessionServiceProvider.registerDriver('cookie', (context) {
          final options = context.options.copyWith(sameSite: SameSite.strict);
          return SessionConfig.cookie(
            codecs: context.codecs,
            cookieName: context.cookieName,
            maxAge: context.lifetime,
            expireOnClose: context.expireOnClose,
            options: options,
          );
        }, overrideExisting: true);
        addTearDown(() {
          SessionServiceProvider.unregisterDriver('cookie');
          SessionServiceProvider.registerDriver(
            'cookie',
            (context) => SessionConfig.cookie(
              codecs: context.codecs,
              cookieName: context.cookieName,
              maxAge: context.lifetime,
              expireOnClose: context.expireOnClose,
              options: context.options,
            ),
            documentation: (ctx) => <ConfigDocEntry>[
              ConfigDocEntry(
                path: ctx.path('encrypt'),
                type: 'bool',
                description:
                    'Controls whether cookie-based session payloads are encrypted.',
              ),
            ],
            overrideExisting: true,
          );
        });

        final appKey = SecureCookie.generateKey();
        final engine = testEngine(
          configItems: {
            'app': {'key': appKey},
            'session': {
              'enabled': true,
              'driver': 'cookie',
              'same_site': 'lax',
              'cookie': 'override-session',
            },
          },
        );
        addTearDown(() async => await engine.close());
        await engine.initialize();

        final config = await engine.make<SessionConfig>();
        expect(config.sameSite, equals(SameSite.strict));
        expect(config.cookieName, equals('override-session'));
      },
    );

    test('documents custom session driver options', () {
      SessionServiceProvider.registerDriver(
        'docs-driver',
        (context) => SessionConfig.cookie(
          codecs: context.codecs,
          cookieName: context.cookieName,
          maxAge: context.lifetime,
          expireOnClose: context.expireOnClose,
          options: context.options,
        ),
        documentation: (context) => <ConfigDocEntry>[
          ConfigDocEntry(
            path: context.path('api_key'),
            type: 'string',
            description: 'API key required for docs-driver session backend.',
          ),
        ],
        overrideExisting: true,
      );
      addTearDown(() {
        SessionServiceProvider.unregisterDriver('docs-driver');
      });

      final provider = SessionServiceProvider();
      final docPaths = provider.defaultConfig.docs
          .map((entry) => entry.path)
          .toSet();
      expect(docPaths, contains('session.api_key'));
    });

    test('registerDriver prevents duplicate registrations', () {
      SessionConfig builder(SessionDriverBuilderContext context) {
        return SessionConfig.cookie(
          appKey: SecureCookie.generateKey(),
          codecs: context.codecs,
          cookieName: context.cookieName,
          maxAge: context.lifetime,
          expireOnClose: context.expireOnClose,
          options: context.options,
        );
      }

      SessionServiceProvider.registerDriver(
        'session-dup',
        builder,
        overrideExisting: true,
      );
      addTearDown(() {
        SessionServiceProvider.unregisterDriver('session-dup');
      });

      expect(
        () => SessionServiceProvider.registerDriver('session-dup', builder),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('session-dup'),
          ),
        ),
      );
    });
  });
}
