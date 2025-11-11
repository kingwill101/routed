import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:routed/providers.dart' show ProviderRegistry;
import 'package:routed/routed.dart';
import 'package:routed_cli/src/args/base_command.dart';
import 'package:routed_cli/src/args/commands/provider_metadata.dart';
import 'package:yaml/yaml.dart';

class ProviderListCommand extends BaseCommand {
  ProviderListCommand({super.logger, super.fileSystem}) {
    argParser.addFlag(
      'config',
      abbr: 'c',
      help: 'Display default configuration for each provider.',
      defaultsTo: false,
    );
  }

  @override
  String get name => 'provider:list';

  @override
  String get description => 'Display configured providers and their status.';

  @override
  String get category => 'Providers';

  @override
  Future<void> run() async {
    return guarded(() async {
      final showConfig = (results?['config'] as bool? ?? false) || verbose;
      final projectRoot = await findProjectRoot();
      if (projectRoot == null) {
        throw UsageException('Not a Routed project.', usage);
      }

      final manifest = await _loadManifest(projectRoot);
      final active = (manifest['providers'] as List).cast<String>();

      logger.info('Provider Manifest');
      for (final registration in ProviderRegistry.instance.registrations) {
        final enabled = active.contains(registration.id) ? 'yes' : 'no';
        ServiceProvider provider;
        try {
          provider = registration.factory();
        } on ProviderConfigException catch (error) {
          final message =
              'Duplicate driver registration detected while loading provider '
              '"${registration.id}". ${error.message}\n'
              'Unregister the existing driver before registering a replacement, '
              'then re-run this command.';
          throw UsageException(message, '');
        }
        final description = registration.description.isNotEmpty
            ? registration.description
            : provider.describe();

        logger.info(
          '${registration.id.padRight(24)} enabled: $enabled'
          '${description.isEmpty ? '' : ' — $description'}',
        );

        if (showConfig) {
          if (provider is ProvidesDefaultConfig) {
            final snapshot = provider.defaultConfig.snapshot();
            logger.info('    config source: ${provider.configSource}');
            if (snapshot.values.isNotEmpty) {
              final yaml = _toYaml(snapshot.values);
              final indented = yaml
                  .split('\n')
                  .where((line) => line.isNotEmpty)
                  .map((line) => '      $line')
                  .join('\n');
              logger.info('    defaults:\n$indented');
            } else {
              logger.info('    defaults: {}');
            }
            if (snapshot.docs.isNotEmpty) {
              logger.info('    documented entries:');
              for (final doc in snapshot.docs) {
                final parts = <String>[doc.path];
                if (doc.type != null) parts.add('type=${doc.type}');
                if (doc.description != null && doc.description!.isNotEmpty) {
                  parts.add(doc.description!);
                }
                final options = doc.resolveOptions();
                if (options != null && options.isNotEmpty) {
                  parts.add('options=[${options.join(", ")}]');
                }
                final summary = parts.join(' — ');
                logger.info('      - $summary');
              }
            }
          } else {
            logger.info('    defaults: (none)');
          }
        }
      }

      final unknown = active
          .where((id) => !ProviderRegistry.instance.has(id))
          .toList();
      if (unknown.isNotEmpty) {
        logger.warn('Unknown providers: ${unknown.join(', ')}');
      }
    });
  }
}

class ProviderEnableCommand extends BaseCommand {
  ProviderEnableCommand({super.logger, super.fileSystem});

  @override
  String get name => 'provider:enable';

  @override
  String get description => 'Enable a provider in config/http.yaml.';

  @override
  String get category => 'Providers';

  @override
  Future<void> run() async {
    return guarded(() async {
      final id = results?.rest.isNotEmpty == true ? results!.rest.first : null;
      if (id == null) {
        throw UsageException('Specify a provider identifier.', usage);
      }

      final projectRoot = await findProjectRoot();
      if (projectRoot == null) {
        throw UsageException('Not a Routed project.', usage);
      }

      final manifest = await _loadManifest(projectRoot);
      final providers = (manifest['providers'] as List).cast<String>();
      if (!ProviderRegistry.instance.has(id)) {
        logger.warn(
          'Provider "$id" is not registered. It will be added to the manifest but may not have defaults.',
        );
      }
      final added = !providers.contains(id);
      if (added) {
        providers.add(id);
      } else {
        logger.info('$id already enabled.');
      }

      if (added || verbose) {
        await _writeManifest(projectRoot, manifest);
        logger.info('Enabled $id');
      } else {
        await _writeManifest(projectRoot, manifest);
      }
    });
  }
}

class ProviderDisableCommand extends BaseCommand {
  ProviderDisableCommand({super.logger, super.fileSystem});

  @override
  String get name => 'provider:disable';

  @override
  String get description => 'Disable a provider in config/http.yaml.';

  @override
  String get category => 'Providers';

  @override
  Future<void> run() async {
    return guarded(() async {
      final id = results?.rest.isNotEmpty == true ? results!.rest.first : null;
      if (id == null) {
        throw UsageException('Specify a provider identifier.', usage);
      }

      final projectRoot = await findProjectRoot();
      if (projectRoot == null) {
        throw UsageException('Not a Routed project.', usage);
      }

      final manifest = await _loadManifest(projectRoot);
      final providers = (manifest['providers'] as List).cast<String>();
      final removed = providers.remove(id);

      await _writeManifest(projectRoot, manifest);

      if (removed) {
        logger.info('Disabled $id');
      } else {
        logger.warn(
          'Provider "$id" is not currently enabled in config/http.yaml.',
        );
      }
    });
  }
}

Future<Map<String, dynamic>> _loadManifest(fs.Directory projectRoot) async {
  final httpFile = projectRoot.fileSystem.file(
    projectRoot.uri.resolve('config/http.yaml').toFilePath(),
  );
  Map<String, dynamic> manifest;
  if (!await httpFile.exists()) {
    manifest = {
      'providers': <String>[],
      'middleware': {'global': <String>[], 'groups': <String, dynamic>{}},
    };
    return manifest;
  }
  final raw = await httpFile.readAsString();
  if (raw.trim().isEmpty) {
    manifest = {
      'providers': <String>[],
      'middleware': {'global': <String>[], 'groups': <String, dynamic>{}},
    };
    return manifest;
  }
  final yaml = loadYaml(raw);
  if (yaml is YamlMap) {
    manifest = _yamlToDart(yaml);
  } else {
    manifest = {
      'providers': <String>[],
      'middleware': {'global': <String>[], 'groups': <String, dynamic>{}},
    };
  }
  final providers = manifest['providers'];
  manifest['providers'] = providers is List
      ? providers.map((e) => e.toString()).toList()
      : <String>[];
  manifest['middleware'] = _coerceMiddlewareNode(manifest['middleware']);
  return manifest;
}

Future<void> _writeManifest(
  fs.Directory projectRoot,
  Map<String, dynamic> manifest,
) async {
  final httpFile = projectRoot.fileSystem.file(
    projectRoot.uri.resolve('config/http.yaml').toFilePath(),
  );
  final content = _toYaml(manifest);
  await httpFile.parent.create(recursive: true);
  await httpFile.writeAsString('$content\n');
}

Map<String, dynamic> _yamlToDart(YamlMap map) {
  final result = <String, dynamic>{};
  map.nodes.forEach((key, value) {
    if (key is YamlScalar && key.value is String) {
      result[key.value as String] = _convertYamlNode(value);
    }
  });
  return result;
}

dynamic _convertYamlNode(YamlNode node) {
  if (node is YamlScalar) {
    return node.value;
  }
  if (node is YamlMap) {
    return _yamlToDart(node);
  }
  if (node is YamlList) {
    return node.nodes.map(_convertYamlNode).toList();
  }
  return null;
}

String _toYaml(Map<String, dynamic> data, {int indent = 0}) {
  final buffer = StringBuffer();
  final spaces = ' ' * indent;
  final keys = data.keys.toList();
  for (var i = 0; i < keys.length; i++) {
    final key = keys[i];
    final value = data[key];
    buffer.write('$spaces$key:');
    if (value is Map<String, dynamic>) {
      if (value.isEmpty) {
        buffer.writeln(' {}');
      } else {
        buffer.writeln();
        buffer.write(_toYaml(value, indent: indent + 2));
      }
    } else if (value is List) {
      if (value.isEmpty) {
        buffer.writeln(' []');
      } else {
        buffer.writeln();
        for (final element in value) {
          if (element is Map<String, dynamic>) {
            buffer.writeln('${' ' * (indent + 2)}-');
            buffer.write(_toYaml(element, indent: indent + 4));
          } else {
            buffer.writeln('${' ' * (indent + 2)}- ${_scalarToYaml(element)}');
          }
        }
      }
    } else {
      buffer.writeln(' ${_scalarToYaml(value)}');
    }
  }
  return buffer.toString();
}

String _scalarToYaml(Object? value) {
  if (value == null) return 'null';
  if (value is bool || value is num) {
    return value.toString();
  }
  final text = value.toString();
  if (text.contains(':') || text.contains('#') || text.contains(' ')) {
    return '"${text.replaceAll('"', '\\"')}"';
  }
  return text;
}

Map<String, dynamic> _coerceMiddlewareNode(Object? value) {
  if (value is Map) {
    final result = <String, dynamic>{};
    value.forEach((key, element) {
      final k = key.toString();
      if (k == 'global') {
        if (element is Iterable) {
          result[k] = element.map((e) => e.toString()).toList();
        } else {
          result[k] = <String>[];
        }
      } else if (k == 'groups') {
        result[k] = _coerceGroupsNode(element);
      } else {
        result[k] = element;
      }
    });
    result.putIfAbsent('global', () => <String>[]);
    result.putIfAbsent('groups', () => <String, dynamic>{});
    return result;
  }
  return {'global': <String>[], 'groups': <String, dynamic>{}};
}

Map<String, dynamic> _coerceGroupsNode(Object? value) {
  if (value is Map) {
    final result = <String, dynamic>{};
    value.forEach((key, element) {
      result[key.toString()] = element is Iterable
          ? element.map((e) => e.toString()).toList()
          : <String>[];
    });
    return result;
  }
  return <String, dynamic>{};
}
