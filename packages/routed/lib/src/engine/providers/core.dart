import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:routed/routed.dart' show EngineConfig;
import 'package:routed/src/config/specs/core.dart';
import 'package:routed/src/config/specs/http.dart';
import 'package:routed/src/runtime/shutdown.dart';

import '../../config/config.dart' show ConfigImpl;
import '../../config/loader.dart';
import '../../config/registry.dart';
import '../../container/container.dart';
import '../../contracts/contracts.dart' show Config;
import '../../engine/engine.dart';
import '../../provider/config_utils.dart';
import '../../provider/provider.dart'
    show ConfigDefaults, ProvidesDefaultConfig, ServiceProvider;
import '../../utils/deep_copy.dart';

ConfigDefaults _coreDefaults() {
  const coreSpec = CoreConfigSpec();
  const httpSpec = HttpConfigSpec();
  const runtimeSpec = RuntimeConfigSpec();

  return ConfigDefaults(
    docs: [...coreSpec.docs(), ...httpSpec.docs(), ...runtimeSpec.docs()],
    values: {
      ...coreSpec.defaultsWithRoot(),
      ...httpSpec.defaultsWithRoot(),
      ...runtimeSpec.defaultsWithRoot(),
    },
    schemas: {
      ...coreSpec.schemaWithRoot(),
      ...httpSpec.schemaWithRoot(),
      ...runtimeSpec.schemaWithRoot(),
    },
  );
}

/// A service provider that registers core framework services and manages
/// configuration loading.
class CoreServiceProvider extends ServiceProvider with ProvidesDefaultConfig {
  CoreServiceProvider({
    EngineConfig? config,
    Map<String, dynamic>? configItems,
    ConfigLoaderOptions? configOptions,
    ConfigLoader? loader,
  }) : _config = config,
       _configItems = configItems,
       _configOptions = _resolveOptions(configOptions) {
    _loader = loader ?? ConfigLoader(fileSystem: _configOptions.fileSystem);
  }

  @override
  ConfigDefaults get defaultConfig => _coreDefaults();

  final EngineConfig? _config;
  final Map<String, dynamic>? _configItems;
  final ConfigLoaderOptions _configOptions;
  late final ConfigLoader _loader;

  ConfigSnapshot? _snapshot;
  Container? _rootContainer;
  StreamSubscription<FileSystemEvent>? _directoryWatcher;
  final List<StreamSubscription<FileSystemEvent>> _envFileWatchers = [];
  Timer? _debounce;
  ConfigRegistryListener? _registryListener;

  static ConfigLoaderOptions _resolveOptions(ConfigLoaderOptions? provided) {
    final base = provided ?? const ConfigLoaderOptions();
    final defaultsImpl = ConfigImpl(_coreDefaults().values);
    if (base.defaults.isNotEmpty) {
      defaultsImpl.merge(base.defaults);
    }
    return base.copyWith(defaults: deepCopyMap(defaultsImpl.all()));
  }

  @override
  void register(Container container) {
    _rootContainer = container;

    final registry = container.get<ConfigRegistry>();
    final defaultsImpl = ConfigImpl(registry.combinedDefaults());
    if (_configOptions.defaults.isNotEmpty) {
      defaultsImpl.merge(_configOptions.defaults);
    }

    final effectiveOptions = _configOptions.copyWith(
      defaults: deepCopyMap(defaultsImpl.all()),
    );

    final snapshot = _loader.load(
      effectiveOptions,
      overrides: _configItems ?? const {},
    );
    _snapshot = snapshot;

    final initialEngineConfig = _resolveEngineConfig(
      snapshot.config,
      _config ?? EngineConfig(),
    );
    container.instance<EngineConfig>(initialEngineConfig);
    container.instance<Config>(snapshot.config);
    _registryListener = (entry) {
      final currentSnapshot = _snapshot;
      if (currentSnapshot == null) {
        return;
      }
      final rendered = _loader.renderDefaults(
        entry.defaults,
        currentSnapshot.templateContext,
      );
      if (rendered.isEmpty) {
        return;
      }
      currentSnapshot.config.mergeDefaults(rendered);
    };
    registry.addListener(_registryListener!);
  }

  @override
  Future<void> boot(Container container) async {
    if (!_configOptions.watch) {
      return;
    }
    final engine = await container.make<Engine>();
    await _startWatchers(container, engine);
  }

  @override
  Future<void> cleanup(Container container) async {
    if (!identical(container, _rootContainer)) {
      // Request-scoped cleanup should not tear down application-level watchers.
      return;
    }
    if (_registryListener != null) {
      try {
        final registry = container.get<ConfigRegistry>();
        registry.removeListener(_registryListener!);
      } catch (_) {
        // Ignore if registry is no longer available.
      }
      _registryListener = null;
    }
    await _disposeWatchers();
  }

  Future<void> _startWatchers(Container container, Engine engine) async {
    await _disposeWatchers();

    final fs = _configOptions.resolvedFileSystem;
    final directory = fs.directory(_configOptions.configDirectory);
    if (directory.existsSync()) {
      _directoryWatcher = directory
          .watch(recursive: true)
          .listen((event) => _handleFileEvent(container, engine, event));
    }

    _configureEnvFileWatchers(
      container,
      engine,
      environment: _snapshot?.environment ?? '',
    );
  }

  void _handleFileEvent(
    Container container,
    Engine engine,
    FileSystemEvent event,
  ) {
    if (event.isDirectory) return;
    if (!_loader.isWatchedFile(event.path)) return;
    _scheduleReload(container, engine, source: event.path);
  }

  void _configureEnvFileWatchers(
    Container container,
    Engine engine, {
    required String environment,
  }) {
    for (final watcher in _envFileWatchers) {
      watcher.cancel();
    }
    _envFileWatchers.clear();

    final fs = _configOptions.resolvedFileSystem;
    final files = <String>{..._configOptions.envFiles};
    if (environment.isNotEmpty) {
      files.addAll(
        _configOptions.envFiles.map(
          (file) => file.endsWith('.env')
              ? '$file.$environment'
              : '$file.$environment',
        ),
      );
    }

    for (final path in files) {
      final file = fs.file(path);
      final parent = file.parent;
      if (!parent.existsSync()) continue;
      final watcher = parent.watch(recursive: false).listen((event) {
        final normalizedPath = p.normalize(event.path);
        if (normalizedPath != p.normalize(file.path)) {
          return;
        }
        _scheduleReload(container, engine, source: normalizedPath);
      });
      _envFileWatchers.add(watcher);
    }
  }

  void _scheduleReload(
    Container container,
    Engine engine, {
    required String source,
  }) {
    _debounce?.cancel();
    _debounce = Timer(_configOptions.watchDebounce, () {
      _reload(container, engine, source: source);
    });
  }

  Future<void> _reload(
    Container container,
    Engine engine, {
    required String source,
  }) async {
    final snapshot = _loader.load(
      _configOptions,
      overrides: _configItems ?? const {},
    );
    _snapshot = snapshot;

    final engineConfig = container.get<EngineConfig>();
    engine.updateConfig(_resolveEngineConfig(snapshot.config, engineConfig));

    await engine.replaceConfig(
      snapshot.config,
      metadata: {'source': source, 'environment': snapshot.environment},
    );

    _configureEnvFileWatchers(
      container,
      engine,
      environment: snapshot.environment,
    );
  }

  Future<void> _disposeWatchers() async {
    await _directoryWatcher?.cancel();
    _directoryWatcher = null;
    for (final watcher in _envFileWatchers) {
      await watcher.cancel();
    }
    _envFileWatchers.clear();
    _debounce?.cancel();
    _debounce = null;
  }

  EngineConfig _resolveEngineConfig(Config config, EngineConfig base) {
    final shutdown = resolveShutdownConfig(config, base.shutdown);
    final http2Enabled = config.getBoolOrNull('http.http2.enabled');
    final http2AllowCleartext = config.getBoolOrNull(
      'http.http2.allow_cleartext',
    );
    int? http2MaxStreams = config.getIntOrNull(
      'http.http2.max_concurrent_streams',
    );
    if (http2MaxStreams != null && http2MaxStreams <= 0) {
      http2MaxStreams = null;
    }
    final http2IdleTimeout = config.getDuration(
      'http.http2.idle_timeout',
      defaultValue: const Duration(seconds: 30),
    );

    final http2 = base.http2.copyWith(
      enabled: http2Enabled,
      allowCleartext: http2AllowCleartext,
      maxConcurrentStreams: http2MaxStreams,
      idleTimeout: http2IdleTimeout,
    );

    final tlsCertificatePath = config.getStringOrNull(
      'http.tls.certificate_path',
    );
    final tlsKeyPath = config.getStringOrNull('http.tls.key_path');
    final tlsPassword = config.getStringOrNull(
      'http.tls.password',
      allowEmpty: true,
    );
    final tlsRequestClientCertificate = config.getBoolOrNull(
      'http.tls.request_client_certificate',
    );
    final tlsShared = config.getBoolOrNull('http.tls.shared');
    final tlsV6Only = config.getBoolOrNull('http.tls.v6_only');

    return base.copyWith(
      shutdown: shutdown,
      http2: http2,
      tlsCertificatePath: tlsCertificatePath ?? base.tlsCertificatePath,
      tlsKeyPath: tlsKeyPath ?? base.tlsKeyPath,
      tlsCertificatePassword: tlsPassword ?? base.tlsCertificatePassword,
      tlsRequestClientCertificate:
          tlsRequestClientCertificate ?? base.tlsRequestClientCertificate,
      tlsShared: tlsShared ?? base.tlsShared,
      tlsV6Only: tlsV6Only ?? base.tlsV6Only,
    );
  }
}
