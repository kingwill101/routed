import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/provider/config_utils.dart';

import '../spec.dart';

const String _defaultViewEngine = 'liquid';
const String _defaultViewDirectory = 'views';
const bool _defaultViewCache = true;

class ViewConfigContext extends ConfigSpecContext {
  const ViewConfigContext({required this.engineConfig, super.config});

  final EngineConfig engineConfig;
}

class ViewSettings {
  const ViewSettings({
    required this.engine,
    required this.directory,
    required this.cache,
    required this.disk,
  });

  final String engine;
  final String directory;
  final bool cache;
  final String? disk;
}

class ViewConfigSpec extends ConfigSpec<ViewSettings> {
  const ViewConfigSpec();

  @override
  String get root => 'view';

  @override
  Schema? get schema =>
      ConfigSchema.object(
        title: 'View Configuration',
        description: 'Template engine and view rendering settings.',
        properties: {
          'engine': ConfigSchema.string(
        description: 'View engine identifier (e.g. liquid).',
        defaultValue: _defaultViewEngine,
      ),
          'directory': ConfigSchema.string(
        description: 'Path to templates relative to app root or disk.',
        defaultValue: _defaultViewDirectory,
      ),
          'cache': ConfigSchema.boolean(
        description: 'Enable template caching in production environments.',
        defaultValue: _defaultViewCache,
      ),
          'disk': ConfigSchema.string(
        description: 'Optional storage disk to source templates from.',
      ),
        },
      );

  @override
  ViewSettings fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final defaultsMap = defaults(context: context);
    final defaultEngine = defaultsMap['engine'] as String? ?? _defaultViewEngine;
    final defaultDirectory =
        defaultsMap['directory'] as String? ?? _defaultViewDirectory;
    final defaultCache =
        defaultsMap['cache'] as bool? ?? _defaultViewCache;

    final directoryRaw = parseStringLike(
      map['directory'],
      context: 'view.directory',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final directory =
        (directoryRaw == null || directoryRaw.isEmpty)
            ? defaultDirectory
            : directoryRaw;

    final cache =
        parseBoolLike(
          map['cache'],
          context: 'view.cache',
          throwOnInvalid: true,
        ) ??
        defaultCache;

    final engineRaw = parseStringLike(
      map['engine'],
      context: 'view.engine',
      allowEmpty: false,
      throwOnInvalid: true,
    );
    final engine = engineRaw ?? defaultEngine;

    final diskRaw = parseStringLike(
      map['disk'],
      context: 'view.disk',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final disk = (diskRaw == null || diskRaw.isEmpty) ? null : diskRaw;

    return ViewSettings(
      engine: engine,
      directory: directory,
      cache: cache,
      disk: disk,
    );
  }

  @override
  Map<String, dynamic> toMap(ViewSettings value) {
    return {
      'engine': value.engine,
      'directory': value.directory,
      'cache': value.cache,
      'disk': value.disk,
    };
  }
}
