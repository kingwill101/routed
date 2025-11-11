import 'dart:async';

import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart'
    show Config, TranslationLoader, TranslatorContract;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/translation/loaders/file_translation_loader.dart';
import 'package:routed/src/translation/translator.dart' as routed;

/// Provides translation loader + translator bindings using the default
/// filesystem configured by the engine.
class LocalizationServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  file.FileSystem _fallbackFileSystem = const local.LocalFileSystem();

  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
        docs: <ConfigDocEntry>[
          ConfigDocEntry(
            path: 'translation.paths',
            type: 'list<string>',
            description:
                'Directories scanned for `locale/group.(yaml|yml|json)` files.',
            defaultValue: ['resources/lang'],
          ),
          ConfigDocEntry(
            path: 'translation.json_paths',
            type: 'list<string>',
            description:
                'Directories containing flat `<locale>.json` dictionaries.',
            defaultValue: <String>[],
          ),
          ConfigDocEntry(
            path: 'translation.namespaces',
            type: 'map<string,string>',
            description:
                'Vendor namespace hints mapping namespace => absolute directory.',
            defaultValue: <String, String>{},
          ),
        ],
      );

  @override
  void register(Container container) {
    if (container.has<EngineConfig>()) {
      _fallbackFileSystem = container.get<EngineConfig>().fileSystem;
    }
    final config = container.has<Config>() ? container.get<Config>() : null;
    final loader = _buildLoader(container, config);
    final translator = _buildTranslator(container, loader, config);
    container.instance<TranslationLoader>(loader);
    container.instance<TranslatorContract>(translator);
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    final loader = _buildLoader(container, config);
    final translator = _buildTranslator(container, loader, config);
    container.instance<TranslationLoader>(loader);
    container.instance<TranslatorContract>(translator);
  }

  TranslationLoader _buildLoader(Container container, Config? config) {
    final engineConfig =
        container.has<EngineConfig>() ? container.get<EngineConfig>() : null;
    final fs = engineConfig?.fileSystem ?? _fallbackFileSystem;
    final loader = FileTranslationLoader(fileSystem: fs);
    final translationNode = config?.get('translation');
    if (translationNode != null && translationNode is! Map) {
      throw ProviderConfigException('translation must be a map');
    }

    final paths = _readStringList(
      config?.get('translation.paths'),
      defaultValue: const ['resources/lang'],
      context: 'translation.paths',
    );
    loader.setPaths(paths);

    final jsonPaths = _readStringList(
      config?.get('translation.json_paths'),
      defaultValue: const <String>[],
      context: 'translation.json_paths',
    );
    loader.setJsonPaths(jsonPaths);

    final namespaces = _readStringMap(
      config?.get('translation.namespaces'),
      context: 'translation.namespaces',
    );
    loader.setNamespaces(namespaces);

    return loader;
  }

  TranslatorContract _buildTranslator(
    Container container,
    TranslationLoader loader,
    Config? config,
  ) {
    final locale = _readLocale(config?.get('app.locale')) ?? 'en';
    final fallback = _readLocale(config?.get('app.fallback_locale')) ?? locale;
    final translator = routed.Translator(
      loader: loader,
      locale: locale,
      fallbackLocale: fallback,
    );
    return translator;
  }

  List<String> _readStringList(
    Object? value, {
    required List<String> defaultValue,
    required String context,
  }) {
    if (value == null) {
      return defaultValue;
    }
    if (value is String) {
      return value.trim().isEmpty ? <String>[] : <String>[value.trim()];
    }
    if (value is Iterable) {
      final result = <String>[];
      for (final entry in value) {
        if (entry is! String) {
          throw ProviderConfigException('$context entries must be strings');
        }
        final trimmed = entry.trim();
        if (trimmed.isNotEmpty) {
          result.add(trimmed);
        }
      }
      return result;
    }
    throw ProviderConfigException('$context must be a string or list');
  }

  Map<String, String> _readStringMap(
    Object? value, {
    required String context,
  }) {
    if (value == null) {
      return <String, String>{};
    }
    if (value is! Map) {
      throw ProviderConfigException('$context must be a map');
    }
    final result = <String, String>{};
    value.forEach((key, path) {
      if (key is! String || path is! String) {
        throw ProviderConfigException('$context entries must be strings');
      }
      final trimmedKey = key.trim();
      final trimmedPath = path.trim();
      if (trimmedKey.isEmpty || trimmedPath.isEmpty) {
        return;
      }
      result[trimmedKey] = trimmedPath;
    });
    return result;
  }

  String? _readLocale(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw ProviderConfigException('app locale keys must be strings');
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
