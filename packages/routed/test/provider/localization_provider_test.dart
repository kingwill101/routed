import 'package:file/memory.dart';
import 'package:routed/src/config/config.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/engine/providers/localization.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/translation/loaders/file_translation_loader.dart';
import 'package:routed/src/translation/locale_manager.dart';
import 'package:routed/src/translation/locale_resolver_registry.dart';
import 'package:routed/src/translation/locale_resolution.dart';
import 'package:routed/src/translation/resolvers.dart';
import 'package:test/test.dart';

void main() {
  group('LocalizationServiceProvider', () {
    late Container container;
    late MemoryFileSystem fs;
    late LocalizationServiceProvider provider;

    setUp(() {
      container = Container();
      fs = MemoryFileSystem();
      container.instance<EngineConfig>(EngineConfig(fileSystem: fs));
      container.instance<MiddlewareRegistry>(MiddlewareRegistry());
      provider = LocalizationServiceProvider();
    });

    test('registers loader and translator using config values', () {
      final config = ConfigImpl({
        'app': {'locale': 'fr', 'fallback_locale': 'en'},
        'translation': {
          'paths': ['lang'],
          'json_paths': ['lang/json'],
          'namespaces': {'demo': 'packages/demo/lang'},
        },
      });
      container.instance<Config>(config);

      provider.register(container);

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

    test('defaults fallback locale to app.locale when absent', () {
      final config = ConfigImpl({
        'app': {'locale': 'es'},
      });
      container.instance<Config>(config);

      provider.register(container);

      final translator = container.get<TranslatorContract>();
      expect(translator.locale, equals('es'));
      expect(translator.fallbackLocale, equals('es'));
    });

    test('throws when translation config is not a map', () {
      final config = ConfigImpl({'translation': 'invalid'});
      container.instance<Config>(config);

      expect(
        () => provider.register(container),
        throwsA(isA<ProviderConfigException>()),
      );
    });

    test('onConfigReload rebuilds loader and translator', () async {
      final initial = ConfigImpl({
        'app': {'locale': 'en'},
      });
      container.instance<Config>(initial);
      provider.register(container);

      final updated = ConfigImpl({
        'app': {'locale': 'de', 'fallback_locale': 'en'},
      });
      container.instance<Config>(updated);
      await provider.onConfigReload(container, updated);

      final translator = container.get<TranslatorContract>();
      expect(translator.locale, equals('de'));
      expect(translator.fallbackLocale, equals('en'));

      final manager = container.get<LocaleManager>();
      expect(manager.defaultLocale, equals('de'));
      expect(manager.fallbackLocale, equals('en'));
    });

    test('builds resolver order from configuration', () {
      final config = ConfigImpl({
        'app': {'locale': 'en'},
        'translation': {
          'resolvers': ['cookie', 'header'],
          'cookie': {'name': 'preferred'},
        },
      });
      container.instance<Config>(config);

      provider.register(container);

      final manager = container.get<LocaleManager>();
      expect(
        manager.resolve(
          LocaleResolutionContext(
            header: (_) => 'fr',
            query: (_) => null,
            cookie: (_) => 'pt',
            sessionValue: null,
          ),
        ),
        equals('pt'),
      );
    });

    test('supports custom resolver registration via registry', () {
      LocaleResolverRegistry.instance.register('static-locale', (ctx) {
        final locale = ctx.option<String>('locale') ?? 'en';
        return _StaticLocaleResolver(locale);
      });

      final config = ConfigImpl({
        'app': {'locale': 'en'},
        'translation': {
          'paths': ['lang'],
          'resolvers': ['static-locale'],
          'resolver_options': {
            'static-locale': {'locale': 'es'},
          },
        },
      });
      container.instance<Config>(config);

      provider.register(container);

      final manager = container.get<LocaleManager>();
      final locale = manager.resolve(
        LocaleResolutionContext(
          header: (_) => null,
          query: (_) => null,
          cookie: (_) => null,
          sessionValue: null,
        ),
      );
      expect(locale, equals('es'));
    });

    test('default resolver list reflects registered entries', () {
      LocaleResolverRegistry.instance.register('default-check', (ctx) {
        return _StaticLocaleResolver('nl');
      });

      final defaults = provider.defaultConfig.values;
      final translationDefaults =
          defaults['translation'] as Map<String, dynamic>?;

      expect(translationDefaults, isNotNull);
      final resolverList =
          translationDefaults!['resolvers'] as List<dynamic>? ?? const [];

      expect(
        resolverList.map((entry) => entry.toString()),
        contains('default-check'),
      );
    });

    test('throws when resolver id is unknown', () {
      final config = ConfigImpl({
        'translation': {
          'resolvers': ['unknown'],
        },
      });
      container.instance<Config>(config);

      expect(
        () => provider.register(container),
        throwsA(isA<ProviderConfigException>()),
      );
    });
  });
}

class _StaticLocaleResolver extends LocaleResolver {
  _StaticLocaleResolver(this.locale);

  final String locale;

  @override
  String? resolve(LocaleResolutionContext context) => locale;
}
