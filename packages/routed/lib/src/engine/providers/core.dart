import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:routed/routed.dart' show EngineConfig;
import 'package:routed/src/runtime/shutdown.dart';

import '../../config/config.dart' show ConfigImpl;
import '../../config/loader.dart';
import '../../config/registry.dart';
import '../../container/container.dart';
import '../../contracts/contracts.dart' show Config;
import '../../engine/engine.dart';
import '../../engine/middleware_registry.dart';
import '../../provider/config_utils.dart';
import '../../provider/provider.dart'
    show
        ConfigDefaults,
        ConfigDocEntry,
        ProvidesDefaultConfig,
        ServiceProvider,
        configDocMetaInheritFromEnv;
import '../../utils/deep_copy.dart';
import '../../view/engine_manager.dart';

ConfigDefaults _coreDefaults() => const ConfigDefaults(
  docs: <ConfigDocEntry>[
    ConfigDocEntry(
      path: 'app.name',
      type: 'string',
      description: 'Application display name.',
      defaultValue: "{{ env.APP_NAME | default: 'Routed App' }}",
      metadata: {configDocMetaInheritFromEnv: 'APP_NAME'},
    ),
    ConfigDocEntry(
      path: 'app.env',
      type: 'string',
      description:
          'Runtime environment identifier (development, production, etc.).',
      defaultValue: 'production',
      metadata: {configDocMetaInheritFromEnv: 'APP_ENV'},
    ),
    ConfigDocEntry(
      path: 'app.debug',
      type: 'bool',
      description: 'Enables verbose application debugging.',
      defaultValue: false,
      metadata: {configDocMetaInheritFromEnv: 'APP_DEBUG'},
    ),
    ConfigDocEntry(
      path: 'app.key',
      type: 'string',
      description: 'Application encryption key used for signed payloads.',
      defaultValue: "{{ env.APP_KEY | default: 'change-me' }}",
      metadata: {configDocMetaInheritFromEnv: 'APP_KEY'},
    ),
    ConfigDocEntry(
      path: 'app.url',
      type: 'string',
      description: 'Base URL used in generated links.',
      defaultValue: 'http://localhost',
    ),
    ConfigDocEntry(
      path: 'app.timezone',
      type: 'string',
      description: 'Default timezone applied to dates.',
      defaultValue: 'UTC',
    ),
    ConfigDocEntry(
      path: 'app.locale',
      type: 'string',
      description: 'Primary locale identifier used for localized content.',
      defaultValue: 'en',
    ),
    ConfigDocEntry(
      path: 'app.fallback_locale',
      type: 'string',
      description: 'Locale used when a translation key is missing.',
      defaultValue: 'en',
    ),
    ConfigDocEntry(
      path: 'app.faker_locale',
      type: 'string',
      description: 'Locale applied to Faker-generated seed data.',
      defaultValue: 'en_US',
    ),
    ConfigDocEntry(
      path: 'app.cipher',
      type: 'string',
      description: 'Default cipher used for encrypted payloads.',
      defaultValue: 'AES-256-CBC',
    ),
    ConfigDocEntry(
      path: 'app.cache_prefix',
      type: 'string',
      description: 'Prefix applied to cache keys for array and simple stores.',
      defaultValue: '',
    ),
    ConfigDocEntry(
      path: 'app.previous_keys',
      type: 'list<string>',
      description: 'Previous APP_KEY values accepted during key rotation.',
      defaultValue: <String>[],
    ),
    ConfigDocEntry(
      path: 'app.maintenance.driver',
      type: 'string',
      description: 'Driver responsible for toggling maintenance mode.',
      defaultValue: 'file',
    ),
    ConfigDocEntry(
      path: 'app.maintenance.store',
      type: 'string',
      description: 'Backing store used by the maintenance driver.',
      defaultValue: 'database',
    ),
    ConfigDocEntry(
      path: 'runtime.shutdown.enabled',
      type: 'bool',
      description: 'Enable graceful shutdown signal handling.',
      defaultValue: true,
    ),
    ConfigDocEntry(
      path: 'runtime.shutdown.grace_period',
      type: 'duration',
      description: 'Time to wait for in-flight requests before forcing close.',
      defaultValue: '20s',
    ),
    ConfigDocEntry(
      path: 'runtime.shutdown.force_after',
      type: 'duration',
      description: 'Absolute time limit before shutdown completes.',
      defaultValue: '1m',
    ),
    ConfigDocEntry(
      path: 'runtime.shutdown.exit_code',
      type: 'int',
      description: 'Process exit code returned after graceful shutdown.',
      defaultValue: 0,
    ),
    ConfigDocEntry(
      path: 'runtime.shutdown.notify_readiness',
      type: 'bool',
      description: 'Mark readiness probes unhealthy while draining.',
      defaultValue: true,
    ),
    ConfigDocEntry(
      path: 'runtime.shutdown.signals',
      type: 'list<string>',
      description: 'Signals that trigger graceful shutdown.',
      defaultValue: ['sigint', 'sigterm'],
    ),
    ConfigDocEntry(
      path: 'http.providers',
      type: 'list<string>',
      description: 'Service providers registered for the HTTP pipeline.',
      defaultValue: [
        'routed.core',
        'routed.routing',
        'routed.cache',
        'routed.sessions',
        'routed.uploads',
        'routed.cors',
        'routed.security',
        'routed.auth',
        'routed.logging',
        'routed.observability',
        'routed.compression',
        'routed.rate_limit',
        'routed.storage',
        'routed.static',
        'routed.views',
      ],
    ),
    ConfigDocEntry(
      path: 'http.middleware.global',
      type: 'list<string>',
      description: 'Middleware executed for every HTTP request.',
      defaultValue: <String>[],
    ),
    ConfigDocEntry(
      path: 'http.middleware.groups',
      type: 'map<string, list<string>>',
      description: 'Named middleware groups applied to route collections.',
      defaultValue: <String, List<String>>{},
    ),
    ConfigDocEntry(
      path: 'http.middleware_sources',
      type: 'map',
      description:
          'Automatically registered observability middleware references.',
      defaultValue: <String, Object?>{
        'routed.observability': <String, Object?>{
          'global': <String>[
            'routed.observability.health',
            'routed.observability.tracing',
            'routed.observability.metrics',
          ],
        },
      },
    ),
    ConfigDocEntry(
      path: 'http.http2.enabled',
      type: 'bool',
      description: 'Enable HTTP/2 (ALPN h2) on secure listeners.',
    ),
    ConfigDocEntry(
      path: 'http.http2.allow_cleartext',
      type: 'bool',
      description:
          'Allow HTTP/2 without TLS (h2c). Typically false in production.',
    ),
    ConfigDocEntry(
      path: 'http.http2.max_concurrent_streams',
      type: 'int',
      description: 'Advertised max concurrent streams per HTTP/2 connection.',
    ),
    ConfigDocEntry(
      path: 'http.http2.idle_timeout',
      type: 'duration',
      description: 'Optional idle timeout applied to HTTP/2 connections.',
    ),
    ConfigDocEntry(
      path: 'http.tls.certificate_path',
      type: 'string',
      description: 'Path to the PEM certificate chain used for TLS.',
    ),
    ConfigDocEntry(
      path: 'http.tls.key_path',
      type: 'string',
      description:
          'Path to the private key corresponding to the TLS certificate.',
    ),
    ConfigDocEntry(
      path: 'http.tls.password',
      type: 'string',
      description: 'Optional password protecting the certificate/key files.',
    ),
    ConfigDocEntry(
      path: 'http.tls.request_client_certificate',
      type: 'bool',
      description: 'Request client certificates during TLS handshakes.',
    ),
    ConfigDocEntry(
      path: 'http.tls.shared',
      type: 'bool',
      description:
          'Allow multiple isolates/processes to share the TLS listener.',
    ),
    ConfigDocEntry(
      path: 'http.tls.v6_only',
      type: 'bool',
      description:
          'Restrict TLS listener to IPv6 only (disables IPv4 dual stack).',
    ),
  ],
);

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
    container.instance<ViewEngineManager>(ViewEngineManager());
    container.instance<MiddlewareRegistry>(MiddlewareRegistry());
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
    final http2Enabled = parseBoolLike(
      config.get('http.http2.enabled'),
      context: 'http.http2.enabled',
      stringMappings: const {'true': true, 'false': false},
      throwOnInvalid: false,
    );
    final http2AllowCleartext = parseBoolLike(
      config.get('http.http2.allow_cleartext'),
      context: 'http.http2.allow_cleartext',
      stringMappings: const {'true': true, 'false': false},
      throwOnInvalid: false,
    );
    int? http2MaxStreams = parseIntLike(
      config.get('http.http2.max_concurrent_streams'),
      context: 'http.http2.max_concurrent_streams',
      throwOnInvalid: false,
    );
    if (http2MaxStreams != null && http2MaxStreams <= 0) {
      http2MaxStreams = null;
    }
    final http2IdleTimeout = parseDurationLike(
      config.get('http.http2.idle_timeout'),
      context: 'http.http2.idle_timeout',
      throwOnInvalid: false,
    );

    final http2 = base.http2.copyWith(
      enabled: http2Enabled,
      allowCleartext: http2AllowCleartext,
      maxConcurrentStreams: http2MaxStreams,
      idleTimeout: http2IdleTimeout,
    );

    final tlsCertificatePath = parseStringLike(
      config.get('http.tls.certificate_path'),
      context: 'http.tls.certificate_path',
      throwOnInvalid: false,
    );
    final tlsKeyPath = parseStringLike(
      config.get('http.tls.key_path'),
      context: 'http.tls.key_path',
      throwOnInvalid: false,
    );
    final tlsPassword = parseStringLike(
      config.get('http.tls.password'),
      context: 'http.tls.password',
      allowEmpty: true,
      throwOnInvalid: false,
    );
    final tlsRequestClientCertificate = parseBoolLike(
      config.get('http.tls.request_client_certificate'),
      context: 'http.tls.request_client_certificate',
      stringMappings: const {'true': true, 'false': false},
      throwOnInvalid: false,
    );
    final tlsShared = parseBoolLike(
      config.get('http.tls.shared'),
      context: 'http.tls.shared',
      stringMappings: const {'true': true, 'false': false},
      throwOnInvalid: false,
    );
    final tlsV6Only = parseBoolLike(
      config.get('http.tls.v6_only'),
      context: 'http.tls.v6_only',
      stringMappings: const {'true': true, 'false': false},
      throwOnInvalid: false,
    );

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
