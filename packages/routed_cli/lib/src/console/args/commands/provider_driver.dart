import 'dart:async';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:routed_cli/src/console/args/base_command.dart';

class ProviderDriverCommand extends BaseCommand {
  ProviderDriverCommand({super.logger, super.fileSystem}) {
    argParser
      ..addOption(
        'type',
        abbr: 't',
        help: 'Driver category to scaffold (storage, cache, or session).',
        allowed: const ['storage', 'cache', 'session'],
        allowedHelp: const {
          'storage': 'Generate a storage driver starter.',
          'cache': 'Generate a cache store driver starter.',
          'session': 'Generate a session driver starter.',
        },
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Relative directory where the driver file will be written.',
        valueHelp: 'lib/drivers/<type>',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Overwrite the target file if it already exists.',
        negatable: true,
        defaultsTo: false,
      );
  }

  @override
  String get name => 'provider:driver';

  @override
  String get description =>
      'Generate a starter file for a custom storage, cache, or session driver.';

  @override
  String get category => 'Providers';

  @override
  Future<void> run() async {
    return guarded(() async {
      final projectRoot = await findProjectRoot();
      if (projectRoot == null) {
        throw UsageException('Not a Routed project.', usage);
      }

      final rest = results?.rest ?? const <String>[];
      var type = (results?['type'] as String?)?.toLowerCase();
      String identifier;

      if (type == null || type.isEmpty) {
        if (rest.isEmpty) {
          throw UsageException(
            'Specify a driver name (and optionally a type).',
            usage,
          );
        }
        if (rest.length == 1) {
          type = 'storage';
          identifier = rest[0];
        } else if (rest.length == 2) {
          type = rest[0].toLowerCase();
          identifier = rest[1];
        } else {
          throw UsageException(
            'Too many positional arguments. Usage: provider:driver [type] <name>',
            usage,
          );
        }
      } else {
        if (rest.isEmpty) {
          throw UsageException('Specify a driver name.', usage);
        }
        identifier = rest[0];
        if (rest.length > 1) {
          throw UsageException(
            'Too many positional arguments. Only supply the driver name when --type is used.',
            usage,
          );
        }
      }

      if (type != 'storage' && type != 'cache' && type != 'session') {
        throw UsageException(
          'Unsupported driver type "$type". Use "storage", "cache", or "session".',
          usage,
        );
      }

      final normalized = _normalizeIdentifier(identifier);
      if (normalized.isEmpty) {
        throw UsageException(
          'Driver identifier must contain at least one alphanumeric character.',
          usage,
        );
      }

      final outputOption = results?['output'] as String?;
      final defaultOutput = switch (type) {
        'storage' => 'lib/drivers/storage',
        'cache' => 'lib/drivers/cache',
        _ => 'lib/drivers/session',
      };
      final outputDirRelative = (outputOption == null || outputOption.isEmpty)
          ? defaultOutput
          : outputOption;

      final fileName = switch (type) {
        'storage' => '${normalized}_storage_driver.dart',
        'cache' => '${normalized}_cache_driver.dart',
        _ => '${normalized}_session_driver.dart',
      };

      final targetFile = fileSystem.file(
        joinPath([projectRoot.path, outputDirRelative, fileName]),
      );

      final force = results?['force'] as bool? ?? false;
      if (await targetFile.exists() && !force) {
        throw UsageException(
          'File "${p.relative(targetFile.path, from: projectRoot.path)}" '
          'already exists. Use --force to overwrite.',
          usage,
        );
      }

      final pascal = _pascalCase(normalized);
      final contents = switch (type) {
        'storage' => _renderStorageTemplate(normalized, pascal),
        'cache' => _renderCacheTemplate(normalized, pascal),
        _ => _renderSessionTemplate(normalized, pascal),
      };

      await writeTextFile(targetFile, contents);

      final relative = p.relative(targetFile.path, from: projectRoot.path);
      logger.info('Created driver starter at $relative');
    });
  }
}

String _normalizeIdentifier(String input) {
  final lowered = input.toLowerCase();
  final replaced = lowered.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  final normalized = replaced
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return normalized;
}

String _pascalCase(String input) {
  final parts = input.split(RegExp(r'[_\-]+')).where((p) => p.isNotEmpty);
  return parts.map((part) => part[0].toUpperCase() + part.substring(1)).join();
}

String _renderStorageTemplate(String identifier, String pascal) {
  final constantName = '${identifier.toUpperCase()}_STORAGE_DRIVER';
  final registerName = 'register${pascal}StorageDriver';

  return '''
import 'package:routed/routed.dart';

const String $constantName = '$identifier';

void $registerName() {
  // Register a custom disk at boot via StorageManager (package:server_storage):
  // manager.registerDisk($constantName, LocalStorageDisk(root: '...', fileSystem: ...));
}
''';
}

String _renderCacheTemplate(String identifier, String pascal) {
  final factoryName = '${pascal}CacheStoreFactory';
  final registerName = 'register${pascal}CacheDriver';
  final constantName = '${identifier.toUpperCase()}_CACHE_DRIVER';

  return '''
import 'package:routed_cache/routed_cache.dart';
import 'package:server_cache/server_cache.dart';
import 'package:server_contracts/server_contracts.dart';

const String $constantName = '$identifier';

/// Implements [StoreFactory] for the `$identifier` cache driver.
///
/// Wire into your app with:
///   final store = $factoryName().create({...});
///   Engine(providers: [RoutedCacheProvider(store)]);
class $factoryName implements StoreFactory {
  @override
  Store create(Map<String, dynamic> config) {
    final directory = config['cache_dir'] as String? ??
        'storage/framework/cache/$identifier';
    // TODO: return your [Store] implementation for \$directory.
    throw UnimplementedError(
      'Implement the $identifier cache store for "\$directory".',
    );
  }
}

void $registerName() {
  // No global CacheManager registry — construct and pass to RoutedCacheProvider.
}
''';
}

String _renderSessionTemplate(String identifier, String pascal) {
  final registerName = 'register${pascal}SessionDriver';

  return '''
import 'dart:async';

import 'package:routed_sessions/routed_sessions.dart';
import 'package:server_sessions/server_sessions.dart';

/// Custom [SessionStore] for the `$identifier` driver.
///
/// Wire into your app with:
///   Engine(providers: [RoutedSessionsProvider(_${pascal}SessionStore(...))]);
class _${pascal}SessionStore implements SessionStore {
  _${pascal}SessionStore({required this.apiKey, required this.root});

  final String apiKey;
  final String root;

  // TODO: implement SessionStore.read / write for the $identifier backend.
}

void $registerName() {
  // No global SessionServiceProvider registry — construct RoutedSessionsProvider.
}
''';
}

