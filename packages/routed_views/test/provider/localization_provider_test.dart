import 'package:file/memory.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_views/routed_views.dart';
import 'package:test/test.dart';

void main() {
  group('LocalizationServiceProvider', () {
    late Container container;
    late MemoryFileSystem fs;

    setUp(() {
      container = Container();
      fs = MemoryFileSystem();
      container
        ..instance<EngineConfig>(EngineConfig(fileSystem: fs))
        ..instance<MiddlewareRegistry>(MiddlewareRegistry());
    });

    test('registers loader and translator using typed configuration', () async {
      final provider = LocalizationServiceProvider(
        LocalizationConfig(
          defaultLocale: 'fr',
          fallbackLocale: 'en',
          paths: ['lang'],
          jsonPaths: ['lang/json'],
          namespaces: {'demo': 'packages/demo/lang'},
        ),
      );

      // Registration must complete before the asynchronous boot phase starts.
      // ignore: cascade_invocations
      provider.register(container);
      await provider.boot(container);

      final loader =
          container.get<TranslationLoader>() as FileTranslationLoader;
      expect(loader.paths, contains('lang'));
      expect(loader.jsonPaths, contains('lang/json'));
      expect(loader.namespaces['demo'], equals('packages/demo/lang'));

      final translator = container.get<TranslatorContract>();
      expect(translator.locale, equals('fr'));
      expect(translator.fallbackLocale, equals('en'));

      final manager = container.get<LocaleManager>();
      expect(manager.defaultLocale, equals('fr'));
      expect(manager.fallbackLocale, equals('en'));

      final registry = container.get<MiddlewareRegistry>();
      expect(registry.has('routed.localization'), isTrue);
    });

    test('defaults fallback locale to the default locale', () async {
      final provider = LocalizationServiceProvider(
        LocalizationConfig(defaultLocale: 'es'),
      );

      // Registration must complete before the asynchronous boot phase starts.
      // ignore: cascade_invocations
      provider.register(container);
      await provider.boot(container);

      final translator = container.get<TranslatorContract>();
      expect(translator.locale, equals('es'));
      expect(translator.fallbackLocale, equals('es'));
    });

    test('uses the configured resolver order', () async {
      final provider = LocalizationServiceProvider(
        LocalizationConfig(
          resolvers: [
            CookieLocaleResolver(cookieName: 'preferred'),
            HeaderLocaleResolver(),
          ],
          cookieName: 'preferred',
        ),
      );

      // Registration must complete before the asynchronous boot phase starts.
      // ignore: cascade_invocations
      provider.register(container);
      await provider.boot(container);

      final manager = container.get<LocaleManager>();
      expect(
        manager.resolve(
          LocaleResolutionContext(
            header: (_) => 'fr',
            query: (_) => null,
            cookie: (_) => 'pt',
          ),
        ),
        equals('pt'),
      );
    });

    test('supports custom resolver instances', () async {
      final provider = LocalizationServiceProvider(
        LocalizationConfig(resolvers: [_StaticLocaleResolver('es')]),
      );

      // Registration must complete before the asynchronous boot phase starts.
      // ignore: cascade_invocations
      provider.register(container);
      await provider.boot(container);

      final manager = container.get<LocaleManager>();
      final locale = manager.resolve(
        LocaleResolutionContext(
          header: (_) => null,
          query: (_) => null,
          cookie: (_) => null,
        ),
      );
      expect(locale, equals('es'));
    });

    test('rejects an empty resolver chain during typed validation', () async {
      final provider = LocalizationServiceProvider(
        LocalizationConfig(resolvers: const []),
      );

      expect(
        () => ConfigStore.fromProviders([provider]),
        throwsA(isA<ConfigValidationException>()),
      );
    });
  });
}

class _StaticLocaleResolver implements LocaleResolver {
  _StaticLocaleResolver(this.locale);

  final String locale;

  @override
  String? resolve(LocaleResolutionContext context) => locale;
}
