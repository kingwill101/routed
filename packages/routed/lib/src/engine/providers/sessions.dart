import 'dart:io';

import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/cache/repository.dart' as cache;
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/config.dart' show SessionConfig;
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/engine/storage_defaults.dart';
import 'package:routed/src/engine/storage_paths.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/sessions/cache_store.dart';
import 'package:routed/src/sessions/memory_store.dart';
import 'package:routed/src/sessions/middleware.dart';
import 'package:routed/src/sessions/options.dart';
import 'package:routed/src/sessions/secure_cookie.dart';
import 'package:routed/src/support/named_registry.dart';

/// Signature for a function that converts a [SessionDriverBuilderContext] to a
/// fully-formed [SessionConfig] instance.
typedef SessionDriverBuilder =
    SessionConfig Function(SessionDriverBuilderContext context);

/// Signature for a callback that returns documentation describing a driver’s
/// configuration options.
///
/// The returned list is merged into the global configuration docs produced by
/// [SessionServiceProvider].
typedef SessionDriverDocBuilder =
    List<ConfigDocEntry> Function(SessionDriverDocContext context);

typedef SessionDriverValidator =
    void Function(SessionDriverBuilderContext context);

/// Context passed to a [SessionDriverBuilder].
///
/// The object aggregates every bit of information a driver might need to build
/// a concrete [SessionConfig].  Fields are intentionally kept immutable to
/// ensure the builder operates on a consistent snapshot of configuration.
class SessionDriverBuilderContext {
  SessionDriverBuilderContext({
    required this.container,
    required this.rootConfig,
    required this.raw,
    required this.driver,
    required this.cookieName,
    required this.lifetime,
    required this.expireOnClose,
    required this.encrypt,
    required this.options,
    required this.codecs,
    required this.cachePrefix,
    required this.keys,
    this.lottery,
    this.cacheManager,
    this.storageDefaults,
  });

  /// Application service container.
  final Container container;

  /// The root application configuration.
  final Config rootConfig;

  /// Parsed “session” map after normalisation/merging.
  final Map<String, dynamic> raw;

  /// Normalised driver identifier (e.g. “cookie”, “redis”).
  final String driver;

  /// Cookie name that will be sent back to the client.
  final String cookieName;

  /// Logical session lifetime.
  final Duration lifetime;

  /// Whether the session should be discarded when the browser closes.
  final bool expireOnClose;

  /// Whether the payload is encrypted when using cookie-based storage.
  final bool encrypt;

  /// Resolved cookie options.
  final Options options;

  /// Ordered list of [SecureCookie] codecs (primary first).
  final List<SecureCookie> codecs;

  /// Prefix applied to all cache keys for cache-backed drivers.
  final String cachePrefix;

  /// Application secret(s) used when signing/encrypting cookies.
  final List<String> keys;

  /// Odds used by _file_ drivers to trigger garbage collection.
  final List<int>? lottery;

  /// Lazily-injected cache manager (may be `null` for non cache drivers).
  final CacheManager? cacheManager;

  /// Storage defaults reported by the storage provider.
  final StorageDefaults? storageDefaults;

  /// Returns the cache [cache.Repository] identified by [name] or throws
  /// [ProviderConfigException] if the cache manager is absent.
  cache.Repository requireCacheStore(String name) {
    final manager = cacheManager;
    if (manager == null) {
      throw ProviderConfigException(
        'Cache manager is required for cache-backed session drivers.',
      );
    }
    return manager.store(name);
  }
}

/// Context object supplied to a [SessionDriverDocBuilder].
///
/// It mainly exists to help the builder derive fully-qualified configuration
/// paths.
class SessionDriverDocContext {
  SessionDriverDocContext({required this.driver, required this.pathBase});

  /// Normalised driver identifier being documented.
  final String driver;

  /// Root configuration path (e.g. “session”).
  final String pathBase;

  /// Produces a full configuration path by appending [segment] to
  /// [pathBase] using a dot separator.
  String path(String segment) => '$pathBase.$segment';
}

/// Registry responsible for managing session driver registrations.
///
/// Third-party packages can use [register] and [unregister] to expose their own
/// drivers at runtime.  The class is a thin singleton wrapper around a map,
/// deliberately avoiding any global state beyond the registry itself.
class SessionDriverRegistry extends NamedRegistry<SessionDriverRegistration> {
  SessionDriverRegistry._internal();

  /// Singleton accessor.
  static final SessionDriverRegistry instance =
      SessionDriverRegistry._internal();

  /// Registers a new session [driver].
  ///
  /// Supplying [documentation] allows the driver to contribute to
  /// configuration documentation.  When [overrideExisting] is `false`,
  /// an existing registration with the same name will be left untouched.
  void register(
    String driver,
    SessionDriverBuilder builder, {
    SessionDriverDocBuilder? documentation,
    bool overrideExisting = true,
    SessionDriverValidator? validator,
    List<String> requiresConfig = const [],
  }) {
    final registration = SessionDriverRegistration(
      builder: builder,
      documentation: documentation,
      validator: validator,
      requiresConfig: requiresConfig,
      origin: StackTrace.current,
    );
    final stored = registerEntry(
      driver,
      registration,
      overrideExisting: overrideExisting,
    );
    if (!stored) {
      return;
    }
  }

  /// Removes the registration associated with [driver] if it exists.
  void unregister(String driver) => unregisterEntry(driver);

  /// Returns `true` if a registration exists for [driver].
  bool contains(String driver) => containsEntry(driver);

  /// Retrieves the builder associated with [driver] or `null` when absent.
  SessionDriverBuilder? builderFor(String driver) =>
      registrationFor(driver)?.builder;

  SessionDriverRegistration? registrationFor(String driver) => getEntry(driver);

  void ensureRequirements(
    String driver,
    SessionDriverBuilderContext context,
    SessionDriverRegistration registration,
  ) {
    for (final key in registration.requiresConfig) {
      final value = context.raw[key];
      if (value == null) {
        throw ProviderConfigException(
          'Session driver "$driver" requires configuration key "$key".',
        );
      }
      if (value is String && value.trim().isEmpty) {
        throw ProviderConfigException(
          'Session driver "$driver" requires configuration key "$key" to be non-empty.',
        );
      }
    }
  }

  void runValidator(
    String driver,
    SessionDriverBuilderContext context,
    SessionDriverRegistration registration,
  ) {
    final validator = registration.validator;
    if (validator == null) {
      return;
    }
    try {
      validator(context);
    } on ProviderConfigException {
      rethrow;
    } catch (error) {
      throw ProviderConfigException(
        'Session driver "$driver" validation failed: $error',
      );
    }
  }

  /// Returns a sorted list of available driver names, ensuring that [include]
  /// is always present in the result.
  List<String> availableDrivers({Iterable<String> include = const []}) {
    final result = <String>{...include};
    result.addAll(entryNames);
    final list = result.toList()..sort();
    return list;
  }

  /// Collates documentation from all registered drivers.
  List<ConfigDocEntry> documentation({required String pathBase}) {
    final docs = <ConfigDocEntry>[];
    entries.forEach((driver, registration) {
      final builder = registration.documentation;
      if (builder == null) {
        return;
      }
      final entries = builder(
        SessionDriverDocContext(driver: driver, pathBase: pathBase),
      );
      if (entries.isNotEmpty) {
        docs.addAll(entries);
      }
    });
    return docs;
  }

  @override
  bool onDuplicate(
    String name,
    SessionDriverRegistration existing,
    bool overrideExisting,
  ) {
    if (!overrideExisting) {
      return false;
    }
    throw ProviderConfigException(
      'Session driver "$name" is already registered.\n'
      'Original registration stack trace:\n${existing.origin}',
    );
  }
}

class SessionDriverRegistration {
  SessionDriverRegistration({
    required this.builder,
    required this.origin,
    this.documentation,
    this.validator,
    this.requiresConfig = const [],
  });

  final SessionDriverBuilder builder;
  final StackTrace origin;
  final SessionDriverDocBuilder? documentation;
  final SessionDriverValidator? validator;
  final List<String> requiresConfig;
}

/// Service provider that wires all session-related services and publishes
/// default configuration.
///
/// The provider also exposes a lightweight plugin system allowing packages to
/// add new session drivers at runtime.
class SessionServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  static const List<String> _builtInDrivers = <String>[
    'cookie',
    'file',
    'array',
    'redis',
    'cache',
  ];

  static bool _defaultsRegistered = false;
  bool _managesConfig = false;

  /// Default configuration as understood by the framework.
  @override
  ConfigDefaults get defaultConfig => ConfigDefaults(
    docs: <ConfigDocEntry>[
      ConfigDocEntry(
        path: 'session.driver',
        type: 'string',
        description: 'Session backend to use.',
        optionsBuilder: () =>
            SessionServiceProvider.availableDriverNames(includeBuiltIns: true),
        defaultValue: 'cookie',
        metadata: const {configDocMetaInheritFromEnv: 'SESSION_DRIVER'},
      ),
      const ConfigDocEntry(
        path: 'session.lifetime',
        type: 'int',
        description: 'Session lifetime in minutes.',
        defaultValue: 120,
      ),
      const ConfigDocEntry(
        path: 'session.expire_on_close',
        type: 'bool',
        description: 'Expire sessions when the browser closes.',
        defaultValue: false,
      ),
      const ConfigDocEntry(
        path: 'session.encrypt',
        type: 'bool',
        description: 'Encrypt session payloads when using cookie drivers.',
        defaultValue: true,
      ),
      const ConfigDocEntry(
        path: 'session.cookie',
        type: 'string',
        description:
            'Cookie name used for identifying the session when using cookie-based drivers.',
        example: 'routed_app_session',
        defaultValue: "{{ env.SESSION_COOKIE | default: 'routed-session' }}",
        metadata: {configDocMetaInheritFromEnv: 'SESSION_COOKIE'},
      ),
      const ConfigDocEntry(
        path: 'session.path',
        type: 'string',
        description: 'Cookie path scope for the session identifier.',
        defaultValue: '/',
      ),
      const ConfigDocEntry(
        path: 'session.domain',
        type: 'string',
        description: 'Cookie domain override for session cookies.',
        defaultValue: null,
      ),
      const ConfigDocEntry(
        path: 'session.secure',
        type: 'bool',
        description: 'Require HTTPS when sending session cookies.',
        defaultValue: false,
      ),
      const ConfigDocEntry(
        path: 'session.http_only',
        type: 'bool',
        description: 'Mark session cookies as HTTP-only.',
        defaultValue: true,
      ),
      const ConfigDocEntry(
        path: 'session.partitioned',
        type: 'bool',
        description: 'Enable partitioned cookies for session storage.',
        defaultValue: false,
      ),
      const ConfigDocEntry(
        path: 'session.cache_prefix',
        type: 'string',
        description:
            'Prefix applied to cache keys when using cache-backed session drivers.',
        defaultValue: 'session:',
      ),
      const ConfigDocEntry(
        path: 'session.same_site',
        type: 'string',
        description: 'SameSite policy applied to the session cookie.',
        options: <String>['lax', 'strict', 'none'],
        defaultValue: 'lax',
      ),
      const ConfigDocEntry(
        path: 'session.files',
        type: 'string',
        description: 'Filesystem path used by file-based session drivers.',
        defaultValue: 'storage/framework/sessions',
      ),
      const ConfigDocEntry(
        path: 'session.lottery',
        type: 'list<int>',
        description:
            'Odds used by some drivers to trigger garbage collection (numerator, denominator).',
        defaultValue: [2, 100],
      ),
      const ConfigDocEntry(
        path: 'session.previous_keys',
        type: 'list<string>',
        description:
            'Historical keys accepted when rotating session secrets. New sessions always use the current key.',
        defaultValue: <String>[],
      ),
      const ConfigDocEntry(
        path: 'http.features.sessions.enabled',
        type: 'bool',
        description: 'Enable the built-in sessions middleware and services.',
        defaultValue: false,
      ),
      ...SessionServiceProvider.driverDocumentation(),
      const ConfigDocEntry(
        path: 'http.middleware_sources',
        type: 'map',
        description: 'Session middleware references injected globally/groups.',
        defaultValue: <String, Object?>{
          'routed.sessions': <String, Object?>{
            'global': <String>['routed.sessions.start'],
            'groups': <String, Object?>{
              'web': <String>['routed.sessions.start'],
            },
          },
        },
      ),
    ],
  );

  /// Returns a list of registered driver names, with optional built-ins.
  static List<String> availableDriverNames({bool includeBuiltIns = false}) {
    _ensureDefaultDriversRegistered();
    final include = includeBuiltIns ? _builtInDrivers : const <String>[];
    return SessionDriverRegistry.instance
        .availableDrivers(include: include)
        .toList();
  }

  /// Collects documentation for every registered driver.
  static List<ConfigDocEntry> driverDocumentation() {
    _ensureDefaultDriversRegistered();
    return SessionDriverRegistry.instance.documentation(pathBase: 'session');
  }

  /// Ensures that built-in drivers are registered once and only once.
  static void _ensureDefaultDriversRegistered() {
    if (_defaultsRegistered) {
      return;
    }
    registerDriver(
      'cookie',
      _buildCookieDriver,
      documentation: _cookieDriverDocs,
      overrideExisting: false,
    );
    registerDriver(
      'file',
      _buildFileDriver,
      documentation: _fileDriverDocs,
      overrideExisting: false,
    );
    registerDriver(
      'array',
      _buildArrayDriver,
      documentation: _arrayDriverDocs,
      overrideExisting: false,
    );
    for (final driver in const ['redis', 'cache']) {
      registerDriver(
        driver,
        _buildCacheBackedDriver,
        documentation: _cacheBackedDriverDocs,
        overrideExisting: false,
        validator: _validateCacheBackedDriver,
      );
    }
    _defaultsRegistered = true;
  }

  // ---------------------------------------------------------------------------
  // Driver builders
  // ---------------------------------------------------------------------------

  static SessionConfig _buildCookieDriver(SessionDriverBuilderContext context) {
    return SessionConfig.cookie(
      codecs: context.codecs,
      cookieName: context.cookieName,
      maxAge: context.lifetime,
      expireOnClose: context.expireOnClose,
      options: context.options,
    );
  }

  static SessionConfig _buildFileDriver(SessionDriverBuilderContext context) {
    final raw = context.raw;
    final configuredPath =
        parseStringLike(
          raw['files'],
          context: 'session.files',
          allowEmpty: true,
          coerceNonString: true,
          throwOnInvalid: false,
        ) ??
        parseStringLike(
          raw['storage_path'],
          context: 'session.storage_path',
          allowEmpty: true,
          coerceNonString: true,
          throwOnInvalid: false,
        ) ??
        raw['path']?.toString();

    final storageDefaults = context.storageDefaults;
    final storagePath = () {
      if (configuredPath != null && configuredPath.trim().isNotEmpty) {
        final trimmed = configuredPath.trim();
        if (storageDefaults != null) {
          return storageDefaults.resolve(trimmed);
        }
        return normalizeStoragePath(context.rootConfig, trimmed);
      }
      if (storageDefaults != null) {
        return storageDefaults.frameworkPath('sessions');
      }
      return resolveFrameworkStoragePath(context.rootConfig, child: 'sessions');
    }();

    return SessionConfig.file(
      appKey: context.keys.first,
      codecs: context.codecs,
      storagePath: storagePath,
      cookieName: context.cookieName,
      maxAge: context.lifetime,
      expireOnClose: context.expireOnClose,
      options: context.options,
      lottery: context.lottery,
    );
  }

  static SessionConfig _buildArrayDriver(SessionDriverBuilderContext context) {
    final store = MemorySessionStore(
      codecs: context.codecs,
      defaultOptions: context.options,
      lifetime: context.lifetime,
    );

    return SessionConfig(
      cookieName: context.cookieName,
      store: store,
      maxAge: context.lifetime,
      path: context.options.path ?? '/',
      secure: context.options.secure ?? false,
      httpOnly: context.options.httpOnly ?? true,
      defaultOptions: context.options,
      expireOnClose: context.expireOnClose,
      sameSite: context.options.sameSite,
      partitioned: context.options.partitioned,
      codecs: context.codecs,
    );
  }

  static String _resolveCacheStoreName(SessionDriverBuilderContext context) {
    return parseStringLike(
          context.raw['store'],
          context: 'session.store',
          allowEmpty: true,
          coerceNonString: true,
          throwOnInvalid: false,
        ) ??
        (context.driver == 'database' ? 'database' : context.driver);
  }

  static SessionConfig _buildCacheBackedDriver(
    SessionDriverBuilderContext context,
  ) {
    final cacheManager = context.cacheManager;
    if (cacheManager == null) {
      throw ProviderConfigException(
        'Cache manager is required for cache-backed session drivers.',
      );
    }

    final storeName = _resolveCacheStoreName(context);
    final repository = cacheManager.store(storeName);

    final store = CacheSessionStore(
      repository: repository,
      codecs: context.codecs,
      defaultOptions: context.options,
      cachePrefix: context.cachePrefix,
      lifetime: context.lifetime,
    );

    return SessionConfig(
      cookieName: context.cookieName,
      store: store,
      maxAge: context.lifetime,
      path: context.options.path ?? '/',
      secure: context.options.secure ?? false,
      httpOnly: context.options.httpOnly ?? true,
      defaultOptions: context.options,
      expireOnClose: context.expireOnClose,
      sameSite: context.options.sameSite,
      partitioned: context.options.partitioned,
      codecs: context.codecs,
    );
  }

  static void _validateCacheBackedDriver(SessionDriverBuilderContext context) {
    final cacheManager = context.cacheManager;
    if (cacheManager == null) {
      throw ProviderConfigException(
        'Cache manager is required for cache-backed session drivers.',
      );
    }
    final storeName = _resolveCacheStoreName(context);
    if (!cacheManager.hasStore(storeName)) {
      final available = cacheManager.storeNames;
      final hint = available.isEmpty
          ? 'No cache stores are configured.'
          : 'Available stores: ${available.join(", ")}';
      throw ProviderConfigException(
        'Session cache store [$storeName] is not defined. $hint',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Driver documentation helpers
  // ---------------------------------------------------------------------------

  static List<ConfigDocEntry> _cookieDriverDocs(
    SessionDriverDocContext context,
  ) {
    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: context.path('encrypt'),
        type: 'bool',
        description:
            'Controls whether cookie-based session payloads are encrypted.',
      ),
    ];
  }

  static List<ConfigDocEntry> _fileDriverDocs(SessionDriverDocContext context) {
    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: context.path('files'),
        type: 'string',
        description:
            'Directory path used to persist session files. Defaults to '
            'storage/framework/sessions based on your storage configuration.',
        metadata: const {
          'default_note':
              'Computed from storage defaults (storage/framework/sessions).',
          'validation': 'Must resolve to an accessible directory path.',
        },
      ),
      ConfigDocEntry(
        path: context.path('lottery'),
        type: 'list<int>',
        description:
            'Cleanup lottery odds for pruning stale sessions (e.g., [2, 100]).',
        defaultValue: const [2, 100],
        metadata: const {'validation': 'Provide two integers [wins, total].'},
      ),
    ];
  }

  static List<ConfigDocEntry> _arrayDriverDocs(
    SessionDriverDocContext context,
  ) => const <ConfigDocEntry>[];

  static List<ConfigDocEntry> _cacheBackedDriverDocs(
    SessionDriverDocContext context,
  ) {
    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: context.path('store'),
        type: 'string',
        description:
            'Cache store name used when persisting sessions via cache-backed drivers. '
            'Defaults to the driver name when omitted.',
        metadata: const {
          'validation': 'Must match a configured cache store name.',
        },
      ),
    ];
  }

  /// Convenience wrapper around [SessionDriverRegistry.register].
  static void registerDriver(
    String driver,
    SessionDriverBuilder builder, {
    SessionDriverDocBuilder? documentation,
    bool overrideExisting = true,
    SessionDriverValidator? validator,
    List<String> requiresConfig = const [],
  }) {
    SessionDriverRegistry.instance.register(
      driver,
      builder,
      documentation: documentation,
      overrideExisting: overrideExisting,
      validator: validator,
      requiresConfig: requiresConfig,
    );
  }

  /// Convenience wrapper around [SessionDriverRegistry.unregister].
  static void unregisterDriver(String driver) {
    SessionDriverRegistry.instance.unregister(driver);
  }

  // ---------------------------------------------------------------------------
  // ServiceProvider overrides
  // ---------------------------------------------------------------------------

  @override
  void register(Container container) {
    final appConfig = container.get<Config>();
    final resolved = _resolveSessionConfig(container, appConfig);
    if (resolved != null) {
      container.instance<SessionConfig>(resolved);
      _managesConfig = true;
    } else {
      _managesConfig = false;
    }

    final registry = container.get<MiddlewareRegistry>();
    registry.register('routed.sessions.start', (c) {
      SessionConfig? config;
      if (c.has<SessionConfig>()) {
        config = c.get<SessionConfig>();
      } else {
        config = _resolveSessionConfig(c, c.get<Config>());
        if (config != null) {
          c.instance<SessionConfig>(config);
        }
      }

      if (config == null) {
        return (ctx, next) async => await next();
      }
      return sessionMiddleware(store: config.store, name: config.cookieName);
    });
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    final resolved = _resolveSessionConfig(container, config);
    if (resolved == null) {
      if (_managesConfig) {
        container.remove<SessionConfig>();
        _managesConfig = false;
      }
      return;
    }

    container.instance<SessionConfig>(resolved);
    _managesConfig = true;
  }

  // ---------------------------------------------------------------------------
  // Configuration helpers
  // ---------------------------------------------------------------------------

  SessionConfig? _resolveSessionConfig(Container container, Config config) {
    final direct = config.get('session.config');
    if (direct is SessionConfig) {
      return direct;
    }
    if (direct is Map) {
      return _sessionConfigFromMap(
        container,
        config,
        Map<String, dynamic>.from(direct),
      );
    }

    final sessionNode = config.get('session');
    if (sessionNode is SessionConfig) {
      return sessionNode;
    }
    if (sessionNode is Map) {
      return _sessionConfigFromMap(
        container,
        config,
        Map<String, dynamic>.from(sessionNode),
      );
    }
    return null;
  }

  SessionConfig? _sessionConfigFromMap(
    Container container,
    Config root,
    Map<String, dynamic> raw,
  ) {
    final merged = Map<String, dynamic>.from(raw);
    if (merged.containsKey('config') && merged['config'] is Map) {
      merged.addAll(Map<String, dynamic>.from(merged['config'] as Map));
    }

    final driver = _string(merged['driver'])?.toLowerCase() ?? 'cookie';

    final cookieName =
        _string(merged['cookie']) ??
        _string(merged['cookie_name']) ??
        _string(merged['name']) ??
        _defaultCookieName(root);

    final lifetime = _resolveLifetime(merged);
    final expireOnClose = _bool(merged['expire_on_close']) ?? false;
    final encrypt = _bool(merged['encrypt']) ?? (driver == 'cookie');
    final cookiePath = _string(merged['path']) ?? '/';
    final domain =
        _string(merged['domain']) ?? _string(merged['cookie_domain']);
    final secure = _boolNullable(merged['secure']);
    final httpOnly = _bool(merged['http_only']) ?? true;
    final sameSite = _parseSameSite(merged['same_site']);
    final partitioned = _bool(merged['partitioned']);
    final lottery = _parseLottery(merged['lottery']);
    final cachePrefix = _string(merged['cache_prefix']) ?? 'session:';

    final options = Options(
      path: cookiePath,
      domain: domain,
      maxAge: expireOnClose ? null : lifetime.inSeconds,
      secure: secure,
      httpOnly: httpOnly,
      sameSite: sameSite,
      partitioned: partitioned,
    );

    final keys = _resolveKeys(merged, root);
    if (keys.isEmpty) {
      throw ProviderConfigException(
        'session.app_key or app.key is required for session cookies.',
      );
    }

    late final List<SecureCookie> codecs;
    try {
      codecs = <SecureCookie>[
        SecureCookie(key: keys.first, useEncryption: encrypt, useSigning: true),
        ...keys
            .skip(1)
            .map(
              (key) => SecureCookie(
                key: key,
                useEncryption: encrypt,
                useSigning: true,
              ),
            ),
      ];
    } on FormatException catch (error) {
      throw ProviderConfigException(
        'session.app_key or app.key must be a valid base64-encoded key: '
        '${error.message}',
      );
    }

    _ensureDefaultDriversRegistered();
    final registry = SessionDriverRegistry.instance;
    final context = SessionDriverBuilderContext(
      container: container,
      rootConfig: root,
      raw: merged,
      driver: driver,
      cookieName: cookieName,
      lifetime: lifetime,
      expireOnClose: expireOnClose,
      encrypt: encrypt,
      options: options,
      codecs: codecs,
      cachePrefix: cachePrefix,
      keys: keys,
      lottery: lottery,
      cacheManager: container.has<CacheManager>()
          ? container.get<CacheManager>()
          : null,
      storageDefaults: container.has<StorageDefaults>()
          ? container.get<StorageDefaults>()
          : null,
    );

    final registration = registry.registrationFor(driver);
    if (registration == null) {
      final available =
          registry.availableDrivers(include: _builtInDrivers).toList()..sort();
      final message = available.isEmpty
          ? 'No session drivers are registered.'
          : 'Registered drivers: ${available.join(", ")}.';
      throw ProviderConfigException(
        'Unsupported session driver "$driver". $message',
      );
    }
    final builder = registration.builder;
    registry.ensureRequirements(driver, context, registration);
    registry.runValidator(driver, context, registration);
    return builder(context);
  }

  // ---------------------------------------------------------------------------
  // Primitive helpers
  // ---------------------------------------------------------------------------

  Duration _resolveLifetime(Map<String, dynamic> source) {
    final lifetimeMinutes = _int(source['lifetime']);
    if (lifetimeMinutes != null) {
      return Duration(minutes: lifetimeMinutes);
    }
    final maxAgeSeconds = _int(source['max_age']);
    if (maxAgeSeconds != null) {
      return Duration(seconds: maxAgeSeconds);
    }
    return const Duration(minutes: 120);
  }

  List<String> _resolveKeys(Map<String, dynamic> map, Config root) {
    final candidates = <String?>[
      _string(map['key']),
      _string(map['app_key']),
      _string(map['secret']),
      _string(root.get('session.app_key')),
      _string(root.get('app.key')),
    ];
    final result = <String>[];
    for (final candidate in candidates) {
      if (candidate != null && candidate.isNotEmpty) {
        result.add(candidate);
        break;
      }
    }
    final additional = <String>[
      ..._stringList(map['previous_keys']),
      ..._stringList(root.get('session.previous_keys')),
      ..._stringList(root.get('app.previous_keys')),
    ];
    for (final key in additional) {
      if (key.isNotEmpty && !result.contains(key)) {
        result.add(key);
      }
    }
    return result;
  }

  String _defaultCookieName(Config config) {
    final appName = _string(config.get('app.name')) ?? 'routed';
    final slug = appName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${slug.isEmpty ? 'routed' : slug}-session';
  }

  SameSite? _parseSameSite(dynamic value) {
    final normalized = _string(value)?.toLowerCase();
    switch (normalized) {
      case null:
      case '':
      case 'null':
        return null;
      case 'lax':
        return SameSite.lax;
      case 'strict':
        return SameSite.strict;
      case 'none':
        return SameSite.none;
      default:
        throw ProviderConfigException(
          'session.same_site must be "lax", "strict", "none", or null',
        );
    }
  }

  List<int>? _parseLottery(dynamic value) {
    if (value == null) return null;
    final list = <int>[];
    if (value is List) {
      for (final entry in value) {
        final parsed = _int(entry);
        if (parsed != null) {
          list.add(parsed);
        }
      }
    } else if (value is String) {
      final parts = value
          .split(',')
          .map((part) => _int(part.trim()))
          .whereType<int>()
          .toList();
      list.addAll(parts);
    }
    if (list.length == 2) {
      return list;
    }
    if (list.isEmpty) {
      return null;
    }
    throw ProviderConfigException('session.lottery must contain two integers.');
  }

  bool? _boolNullable(dynamic value) {
    return parseBoolLike(value, context: 'session', throwOnInvalid: false);
  }

  bool? _bool(dynamic value) {
    return parseBoolLike(value, context: 'session', throwOnInvalid: false);
  }

  int? _int(dynamic value) {
    return parseIntLike(value, context: 'session', throwOnInvalid: false);
  }

  String? _string(dynamic value) {
    return parseStringLike(
      value,
      context: 'session',
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );
  }

  List<String> _stringList(dynamic value) {
    return parseStringList(
          value,
          context: 'session',
          allowCommaSeparated: true,
          allowEmptyResult: true,
          coerceNonStringEntries: true,
          throwOnInvalid: false,
        ) ??
        const [];
  }
}
