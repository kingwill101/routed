import 'package:file/memory.dart';
import 'package:routed/src/config/config.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/providers/localization.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/translation/loaders/file_translation_loader.dart';
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
    });
  });
}
