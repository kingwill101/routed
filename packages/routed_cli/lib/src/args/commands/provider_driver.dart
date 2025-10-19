import 'dart:async';
import 'package:args/command_runner.dart';
import 'package:file/file.dart' as fs;
import 'package:path/path.dart' as p;
import 'package:routed_cli/src/args/base_command.dart';

class ProviderDriverCommand extends BaseCommand {
  ProviderDriverCommand({super.logger, super.fileSystem}) {
    argParser
      ..addOption(
        'type',
        abbr: 't',
        help: 'Driver category to scaffold (storage or cache).',
        allowed: const ['storage', 'cache'],
        allowedHelp: const {
          'storage': 'Generate a storage driver starter.',
          'cache': 'Generate a cache store driver starter.',
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
      'Generate a starter file for a custom storage or cache driver.';

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

      if (type != 'storage' && type != 'cache') {
        throw UsageException(
          'Unsupported driver type "$type". Use "storage" or "cache".',
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
      final defaultOutput = type == 'storage'
          ? 'lib/drivers/storage'
          : 'lib/drivers/cache';
      final outputDirRelative = (outputOption == null || outputOption.isEmpty)
          ? defaultOutput
          : outputOption;

      final fileName = type == 'storage'
          ? '${normalized}_storage_driver.dart'
          : '${normalized}_cache_driver.dart';

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
      final contents = type == 'storage'
          ? _renderStorageTemplate(normalized, pascal)
          : _renderCacheTemplate(normalized, pascal);

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
  StorageServiceProvider.registerDriver(
    $constantName,
    (context) {
      // TODO: Replace with your StorageDisk implementation.
      final root =
          context.configuration['root']?.toString() ?? 'storage/\${context.diskName}';
      return LocalStorageDisk(
        root: root,
        fileSystem: context.manager.defaultFileSystem,
      );
    },
    documentation: (ctx) => <ConfigDocEntry>[
      // Describe driver-specific options, for example:
      // ConfigDocEntry(
      //   path: ctx.path('token'),
      //   type: 'string',
      //   description: 'API token used to authenticate requests.',
      // ),
    ],
  );
}
''';
}

String _renderCacheTemplate(String identifier, String pascal) {
  final factoryName = '${pascal}CacheStoreFactory';
  final registerName = 'register${pascal}CacheDriver';

  return '''
import 'package:routed/routed.dart';

class $factoryName extends StoreFactory {
  @override
  Store create(Map<String, dynamic> config) {
    // TODO: Build and return your cache Store implementation.
    throw UnimplementedError('Create the $identifier cache store.');
  }
}

void $registerName() {
  CacheManager.registerDriver(
    '$identifier',
    () => $factoryName(),
    documentation: (ctx) => <ConfigDocEntry>[
      // Describe driver-specific options, for example:
      // ConfigDocEntry(
      //   path: ctx.path('endpoint'),
      //   type: 'string',
      //   description: 'Service endpoint used by this driver.',
      // ),
    ],
  );
}
''';
}
