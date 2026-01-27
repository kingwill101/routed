import 'dart:io';

import 'package:inertia_dart/inertia_dart.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/routed.dart';

const String _defaultSsrUrl = 'http://127.0.0.1:13714';
const String _defaultAssetsBaseUrl = '/';
const String _defaultDevServerScheme = 'http';
const String _defaultHotFile = 'public/hot';

class InertiaHistoryConfig {
  const InertiaHistoryConfig({required this.encrypt});

  final bool encrypt;
}

class InertiaAssetsConfig {
  const InertiaAssetsConfig({
    this.manifestPath,
    this.entry,
    this.baseUrl = _defaultAssetsBaseUrl,
    this.hotFile = _defaultHotFile,
    this.devServerUrl,
    this.devServerHost,
    this.devServerPort,
    this.devServerScheme = _defaultDevServerScheme,
  });

  final String? manifestPath;
  final String? entry;
  final String baseUrl;
  final String? hotFile;
  final String? devServerUrl;
  final String? devServerHost;
  final int? devServerPort;
  final String devServerScheme;

  String? resolveDevServerUrl() {
    final direct = devServerUrl?.trim();
    if (direct != null && direct.isNotEmpty) {
      return _trimTrailingSlash(direct);
    }
    final hotPath = hotFile?.trim();
    if (hotPath != null && hotPath.isNotEmpty) {
      final file = File(hotPath);
      if (file.existsSync()) {
        final contents = file.readAsStringSync().trim();
        if (contents.isNotEmpty) {
          return _trimTrailingSlash(contents);
        }
      }
    }
    final host = devServerHost?.trim();
    final port = devServerPort;
    if (host == null || host.isEmpty || port == null) {
      return null;
    }
    return _trimTrailingSlash('$devServerScheme://$host:$port');
  }
}

class InertiaConfig {
  InertiaConfig({
    required this.version,
    required this.rootView,
    required this.history,
    required this.ssr,
    required this.assets,
    this.versionResolver,
    this.ssrGateway,
  });

  final String version;
  final String? rootView;
  final InertiaHistoryConfig history;
  final InertiaSsrSettings ssr;
  final InertiaAssetsConfig assets;
  final String Function()? versionResolver;
  final SsrGateway? ssrGateway;

  String resolveVersion() {
    final resolved = versionResolver?.call();
    if (resolved != null && resolved.isNotEmpty) {
      return resolved;
    }
    return version;
  }

  InertiaConfig copyWith({
    String? version,
    String? rootView,
    InertiaHistoryConfig? history,
    InertiaSsrSettings? ssr,
    InertiaAssetsConfig? assets,
    String Function()? versionResolver,
    SsrGateway? ssrGateway,
  }) {
    return InertiaConfig(
      version: version ?? this.version,
      rootView: rootView ?? this.rootView,
      history: history ?? this.history,
      ssr: ssr ?? this.ssr,
      assets: assets ?? this.assets,
      versionResolver: versionResolver ?? this.versionResolver,
      ssrGateway: ssrGateway ?? this.ssrGateway,
    );
  }
}

class InertiaConfigSpec extends ConfigSpec<InertiaConfig> {
  const InertiaConfigSpec();

  @override
  String get root => 'inertia';

  @override
  Schema? get schema => ConfigSchema.object(
    title: 'Inertia Configuration',
    description: 'Inertia.js settings for Routed integration.',
    properties: {
      'version': ConfigSchema.string(
        description: 'Asset version string used for cache busting.',
        defaultValue: '',
      ),
      'root_view': ConfigSchema.string(
        description: 'Default template name for initial Inertia responses.',
        defaultValue: '',
      ),
      'history': ConfigSchema.object(
        description: 'History encryption settings.',
        properties: {
          'encrypt': ConfigSchema.boolean(
            description: 'Encrypt history state for Inertia responses.',
            defaultValue: false,
          ),
        },
      ),
      'ssr': ConfigSchema.object(
        description: 'Server-side rendering configuration.',
        properties: {
          'enabled': ConfigSchema.boolean(
            description: 'Enable SSR requests.',
            defaultValue: false,
          ),
          'url': ConfigSchema.string(
            description: 'SSR gateway URL.',
            defaultValue: _defaultSsrUrl,
          ),
          'health_url': ConfigSchema.string(
            description: 'Override the SSR health endpoint URL.',
          ),
          'shutdown_url': ConfigSchema.string(
            description: 'Override the SSR shutdown endpoint URL.',
          ),
          'bundle': ConfigSchema.string(
            description: 'Path to the SSR bundle file.',
          ),
          'ensure_bundle_exists': ConfigSchema.boolean(
            description: 'Require an SSR bundle before rendering.',
            defaultValue: true,
          ),
          'runtime': ConfigSchema.string(
            description: 'Runtime used to execute the SSR bundle.',
            defaultValue: 'node',
          ),
          'runtime_args': ConfigSchema.list(
            items: ConfigSchema.string(),
            description: 'Additional runtime arguments for the SSR process.',
          ),
          'bundle_candidates': ConfigSchema.list(
            items: ConfigSchema.string(),
            description: 'Additional bundle paths to check for SSR.',
          ),
          'working_directory': ConfigSchema.string(
            description: 'Working directory used to resolve the bundle path.',
          ),
          'environment': ConfigSchema.object(
            description: 'Environment variables for the SSR process.',
            additionalProperties: ConfigSchema.string(),
          ),
        },
      ),
      'assets': ConfigSchema.object(
        description: 'Asset manifest configuration for HTML templates.',
        properties: {
          'manifest_path': ConfigSchema.string(
            description: 'Path to a Vite manifest.json file.',
          ),
          'entry': ConfigSchema.string(
            description: 'Default manifest entry for HTML rendering.',
          ),
          'base_url': ConfigSchema.string(
            description: 'Base URL prefix for asset paths.',
            defaultValue: _defaultAssetsBaseUrl,
          ),
          'hot_file': ConfigSchema.string(
            description: 'Path to a Vite dev server hot file.',
            defaultValue: _defaultHotFile,
          ),
          'dev_server_url': ConfigSchema.string(
            description: 'Dev server origin (http://host:port).',
          ),
          'dev_server_host': ConfigSchema.string(
            description: 'Dev server host if URL is not provided.',
          ),
          'dev_server_port': ConfigSchema.integer(
            description: 'Dev server port if URL is not provided.',
          ),
          'dev_server_scheme': ConfigSchema.string(
            description: 'Dev server scheme (http or https).',
            defaultValue: _defaultDevServerScheme,
          ),
        },
      ),
    },
  );

  @override
  InertiaConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final defaultValues = defaults(context: context);
    final defaultVersion = defaultValues['version'] as String? ?? '';
    final defaultRootView = defaultValues['root_view'] as String? ?? '';

    final version =
        parseStringLike(
          map['version'],
          context: 'inertia.version',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        defaultVersion;

    final rootViewRaw =
        parseStringLike(
          map['root_view'],
          context: 'inertia.root_view',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        defaultRootView;
    final rootView = rootViewRaw.trim().isEmpty ? null : rootViewRaw.trim();

    final historyRaw = map['history'];
    final historyMap = historyRaw == null
        ? const <String, dynamic>{}
        : stringKeyedMap(historyRaw, 'inertia.history');
    final historyDefaults =
        defaultValues['history'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final encrypt =
        parseBoolLike(
          historyMap['encrypt'] ?? historyDefaults['encrypt'],
          context: 'inertia.history.encrypt',
          throwOnInvalid: true,
        ) ??
        false;

    final ssrRaw = map['ssr'];
    final ssrMap = ssrRaw == null
        ? const <String, dynamic>{}
        : stringKeyedMap(ssrRaw, 'inertia.ssr');
    final ssrDefaults =
        defaultValues['ssr'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final ssrEnabled =
        parseBoolLike(
          ssrMap['enabled'] ?? ssrDefaults['enabled'],
          context: 'inertia.ssr.enabled',
          throwOnInvalid: true,
        ) ??
        false;
    final ssrUrlRaw =
        parseStringLike(
          ssrMap['url'] ?? ssrDefaults['url'],
          context: 'inertia.ssr.url',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        _defaultSsrUrl;
    final ssrUrl = ssrUrlRaw.trim().isEmpty ? null : Uri.parse(ssrUrlRaw);
    final ssrHealthRaw = parseStringLike(
      ssrMap['health_url'],
      context: 'inertia.ssr.health_url',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final ssrShutdownRaw = parseStringLike(
      ssrMap['shutdown_url'],
      context: 'inertia.ssr.shutdown_url',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final ssrBundle = parseStringLike(
      ssrMap['bundle'],
      context: 'inertia.ssr.bundle',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final ensureBundleExists =
        parseBoolLike(
          ssrMap['ensure_bundle_exists'] ?? ssrDefaults['ensure_bundle_exists'],
          context: 'inertia.ssr.ensure_bundle_exists',
          throwOnInvalid: true,
        ) ??
        true;
    final runtime =
        parseStringLike(
          ssrMap['runtime'] ?? ssrDefaults['runtime'],
          context: 'inertia.ssr.runtime',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        'node';
    final runtimeArgs = _parseStringList(
      ssrMap['runtime_args'] ?? ssrDefaults['runtime_args'],
      context: 'inertia.ssr.runtime_args',
    );
    final bundleCandidates = _parseStringList(
      ssrMap['bundle_candidates'] ?? ssrDefaults['bundle_candidates'],
      context: 'inertia.ssr.bundle_candidates',
    );
    final workingDirectoryPath = parseStringLike(
      ssrMap['working_directory'],
      context: 'inertia.ssr.working_directory',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final environment = _parseStringMap(
      ssrMap['environment'] ?? ssrDefaults['environment'],
      context: 'inertia.ssr.environment',
    );

    final assetsRaw = map['assets'];
    final assetsMap = assetsRaw == null
        ? const <String, dynamic>{}
        : stringKeyedMap(assetsRaw, 'inertia.assets');
    final assetsDefaults =
        defaultValues['assets'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    final manifestPath = parseStringLike(
      assetsMap['manifest_path'],
      context: 'inertia.assets.manifest_path',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final entry = parseStringLike(
      assetsMap['entry'],
      context: 'inertia.assets.entry',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final baseUrl =
        parseStringLike(
          assetsMap['base_url'] ?? assetsDefaults['base_url'],
          context: 'inertia.assets.base_url',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        _defaultAssetsBaseUrl;
    final hotFile = parseStringLike(
      assetsMap['hot_file'] ?? assetsDefaults['hot_file'],
      context: 'inertia.assets.hot_file',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final devServerUrl = parseStringLike(
      assetsMap['dev_server_url'],
      context: 'inertia.assets.dev_server_url',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final devServerHost = parseStringLike(
      assetsMap['dev_server_host'],
      context: 'inertia.assets.dev_server_host',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final devServerPort = parseIntLike(
      assetsMap['dev_server_port'],
      context: 'inertia.assets.dev_server_port',
      nonNegative: true,
      throwOnInvalid: true,
    );
    final devServerScheme =
        parseStringLike(
          assetsMap['dev_server_scheme'] ?? assetsDefaults['dev_server_scheme'],
          context: 'inertia.assets.dev_server_scheme',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        _defaultDevServerScheme;

    return InertiaConfig(
      version: version,
      rootView: rootView,
      history: InertiaHistoryConfig(encrypt: encrypt),
      ssr: InertiaSsrSettings(
        enabled: ssrEnabled,
        endpoint: ssrUrl,
        healthEndpoint: ssrHealthRaw == null || ssrHealthRaw.trim().isEmpty
            ? null
            : Uri.parse(ssrHealthRaw),
        shutdownEndpoint:
            ssrShutdownRaw == null || ssrShutdownRaw.trim().isEmpty
            ? null
            : Uri.parse(ssrShutdownRaw),
        bundle: _nullIfEmpty(ssrBundle),
        ensureBundleExists: ensureBundleExists,
        runtime: runtime,
        runtimeArgs: runtimeArgs,
        bundleCandidates: bundleCandidates,
        workingDirectory:
            workingDirectoryPath == null || workingDirectoryPath.trim().isEmpty
            ? null
            : Directory(workingDirectoryPath),
        environment: environment,
      ),
      assets: InertiaAssetsConfig(
        manifestPath: _nullIfEmpty(manifestPath),
        entry: _nullIfEmpty(entry),
        baseUrl: baseUrl,
        hotFile: _nullIfEmpty(hotFile) ?? _defaultHotFile,
        devServerUrl: _nullIfEmpty(devServerUrl),
        devServerHost: _nullIfEmpty(devServerHost),
        devServerPort: devServerPort,
        devServerScheme: devServerScheme,
      ),
    );
  }

  @override
  Map<String, dynamic> toMap(InertiaConfig value) {
    return {
      'version': value.version,
      'root_view': value.rootView ?? '',
      'history': {'encrypt': value.history.encrypt},
      'ssr': {
        'enabled': value.ssr.enabled,
        'url': value.ssr.endpoint?.toString() ?? '',
        'health_url': value.ssr.healthEndpoint?.toString() ?? '',
        'shutdown_url': value.ssr.shutdownEndpoint?.toString() ?? '',
        'bundle': value.ssr.bundle ?? '',
        'ensure_bundle_exists': value.ssr.ensureBundleExists,
        'runtime': value.ssr.runtime,
        'runtime_args': value.ssr.runtimeArgs,
        'bundle_candidates': value.ssr.bundleCandidates,
        'working_directory': value.ssr.workingDirectory?.path ?? '',
        'environment': value.ssr.environment,
      },
      'assets': {
        'manifest_path': value.assets.manifestPath,
        'entry': value.assets.entry,
        'base_url': value.assets.baseUrl,
        'hot_file': value.assets.hotFile,
        'dev_server_url': value.assets.devServerUrl,
        'dev_server_host': value.assets.devServerHost,
        'dev_server_port': value.assets.devServerPort,
        'dev_server_scheme': value.assets.devServerScheme,
      },
    };
  }
}

String _trimTrailingSlash(String value) {
  if (value.endsWith('/')) {
    return value.substring(0, value.length - 1);
  }
  return value;
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

List<String> _parseStringList(Object? value, {required String context}) {
  if (value == null) return const [];
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const [];
    return trimmed.split(',').map((item) => item.trim()).toList();
  }
  throw ProviderConfigException('$context must be a list of strings');
}

Map<String, String> _parseStringMap(Object? value, {required String context}) {
  if (value == null) return const {};
  final map = stringKeyedMap(value, context);
  return map.map((key, entry) => MapEntry(key, entry?.toString() ?? ''));
}
