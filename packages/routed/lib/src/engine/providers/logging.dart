import 'dart:async';
import 'dart:io';

import 'package:contextual/contextual.dart' as contextual;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/config/specs/logging.dart';
import 'package:routed/src/config/specs/logging_drivers.dart';
import 'package:routed/src/logging/channel_drivers.dart';
import 'package:routed/src/logging/context.dart';
import 'package:routed/src/logging/driver_registry.dart';
import 'package:routed/src/logging/logger.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/router/types.dart';

class LoggingServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  static const LoggingConfigSpec spec = LoggingConfigSpec();
  static const LoggingSingleDriverSpec _singleSpec = LoggingSingleDriverSpec();
  static const LoggingDailyDriverSpec _dailySpec = LoggingDailyDriverSpec();
  static const LoggingStackDriverSpec _stackSpec = LoggingStackDriverSpec();
  static const LoggingWebhookDriverSpec _webhookSpec =
      LoggingWebhookDriverSpec();
  static const LoggingSamplingDriverSpec _samplingSpec =
      LoggingSamplingDriverSpec();
  bool _enabled = true;
  bool _logSuccess = true;
  contextual.Level _level = contextual.Level.info;
  Map<String, dynamic> _extraFields = const {};
  List<String> _headerNames = const [];
  bool _includeStackTraces = false;

  static bool includeStackTraces = false;

  @override
  ConfigDefaults get defaultConfig {
    final values = spec.defaultsWithRoot();
    values['http'] = {
      'middleware_sources': {
        'routed.logging': {
          'global': ['routed.logging.http'],
        },
      },
    };
    return ConfigDefaults(
      docs: [
        const ConfigDocEntry(
          path: 'http.middleware_sources',
          type: 'map',
          description: 'Logging middleware references injected globally.',
          defaultValue: <String, Object?>{
            'routed.logging': <String, Object?>{
              'global': <String>['routed.logging.http'],
            },
          },
        ),
        ...spec.docs(),
      ],
      values: values,
      schemas: spec.schemaWithRoot(),
    );
  }

  @override
  void register(Container container) {
    _ensureDriverRegistry(container);
    final registry = container.get<MiddlewareRegistry>();
    registry.register('routed.logging.http', (_) => _loggingMiddleware);

    if (container.has<Config>()) {
      _applyConfig(container.get<Config>(), container);
    }
  }

  @override
  Future<void> boot(Container container) async {
    if (!container.has<Config>()) {
      return;
    }

    _applyConfig(container.get<Config>(), container);
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    _applyConfig(config, container);
  }

  Middleware get _loggingMiddleware {
    return (EngineContext ctx, Next next) async {
      if (!_enabled) {
        return await next();
      }

      final startedAt = DateTime.now();
      try {
        final response = await next();
        if (_logSuccess) {
          _log(ctx, response.statusCode, DateTime.now().difference(startedAt));
        }
        return response;
      } catch (error, stackTrace) {
        _log(
          ctx,
          ctx.response.statusCode,
          DateTime.now().difference(startedAt),
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    };
  }

  void _log(
    EngineContext ctx,
    int status,
    Duration duration, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final payload = <String, Object?>{
      'request_id': ctx.id,
      'method': ctx.request.method,
      'path': ctx.request.uri.path,
      'status': status,
      'duration_ms': duration.inMilliseconds,
    };

    final loggingContext = LoggingContext.currentValues();
    if (!identical(loggingContext, const {})) {
      payload.addAll(loggingContext);
    }

    for (final header in _headerNames) {
      final value = ctx.request.headers.value(header);
      if (value != null) {
        payload[_headerKey(header)] = value;
      }
    }

    payload.addAll(_extraFields);

    final logger = RoutedLogger.create(payload);

    final timestamp = DateTime.now().toUtc();
    final message =
        '${ctx.request.method} ${ctx.request.uri.path} -> $status (${duration.inMilliseconds}ms)';

    final logEntry = <String, Object?>{
      'timestamp': timestamp.toIso8601String(),
      'message': message,
      ...payload,
    };

    if (error != null) {
      logEntry['error'] = error.toString();
    }

    if (_includeStackTraces && stackTrace != null) {
      logEntry['stack_trace'] = stackTrace.toString();
    }

    if (error != null) {
      logger.error(message);
      if (_includeStackTraces && stackTrace != null) {
        logger.error(stackTrace.toString());
      }
      return;
    }

    logger.log(_level, message);
  }

  void _ensureDriverRegistry(Container container) {
    if (!container.has<LogDriverRegistry>()) {
      container.instance<LogDriverRegistry>(LogDriverRegistry());
    }
    final registry = container.get<LogDriverRegistry>();
    _registerDefaultDrivers(registry);
  }

  void _registerDefaultDrivers(LogDriverRegistry registry) {
    registry.registerIfAbsent(
      'console',
      (ctx) => contextual.ConsoleLogDriver(),
    );
    registry.registerIfAbsent('stdout', (ctx) => contextual.ConsoleLogDriver());
    registry.registerIfAbsent('stderr', (ctx) => StderrLogDriver());
    registry.registerIfAbsent('null', (ctx) => NullLogDriver());
    registry.registerIfAbsent('single', (ctx) {
      final resolved = _singleSpec.fromMap(
        loggingDriverOptions(ctx.options),
        context: LoggingDriverSpecContext(
          name: ctx.name,
          pathBase: ctx.configPath,
          config: ctx.config,
        ),
      );
      return SingleFileLogDriver(resolved.path);
    });
    registry.registerIfAbsent('daily', (ctx) {
      final resolved = _dailySpec.fromMap(
        loggingDriverOptions(ctx.options),
        context: LoggingDriverSpecContext(
          name: ctx.name,
          pathBase: ctx.configPath,
          config: ctx.config,
        ),
      );
      final options = contextual.DailyFileOptions(
        path: resolved.path,
        retentionDays: resolved.retentionDays,
        flushInterval: resolved.flushInterval,
      );
      return contextual.DailyFileLogDriver.fromOptions(
        options,
        useIsolate: resolved.useIsolate,
      );
    });
    registry.registerIfAbsent('stack', (ctx) {
      final resolved = _stackSpec.fromMap(
        loggingDriverOptions(ctx.options),
        context: LoggingDriverSpecContext(
          name: ctx.name,
          pathBase: ctx.configPath,
          config: ctx.config,
        ),
      );
      final drivers = resolved.channels.map(ctx.resolveChannel).toList();
      return contextual.StackLogDriver(
        drivers,
        ignoreExceptions: resolved.ignoreExceptions,
      );
    });
    registry.registerIfAbsent('webhook', (ctx) {
      final resolved = _webhookSpec.fromMap(
        loggingDriverOptions(ctx.options),
        context: LoggingDriverSpecContext(
          name: ctx.name,
          pathBase: ctx.configPath,
          config: ctx.config,
        ),
      );
      final options = contextual.WebhookOptions(
        url: resolved.url,
        headers: resolved.headers,
        timeout: resolved.timeout,
        keepAlive: resolved.keepAlive,
      );
      return contextual.WebhookLogDriver.fromOptions(options);
    });
    registry.registerIfAbsent('sampling', (ctx) {
      final resolved = _samplingSpec.fromMap(
        loggingDriverOptions(ctx.options),
        context: LoggingDriverSpecContext(
          name: ctx.name,
          pathBase: ctx.configPath,
          config: ctx.config,
        ),
      );
      final wrappedDriver = ctx.resolveChannel(resolved.wrapped);
      return contextual.SamplingLogDriver.fromOptions(
        wrappedDriver,
        resolved.rates,
      );
    });
  }

  void _applyConfig(Config config, Container container) {
    final resolved = spec.resolve(config);
    _enabled = resolved.enabled;
    _logSuccess = resolved.logSuccess;
    _level = resolved.level;
    _extraFields = resolved.extraFields;
    _headerNames = resolved.requestHeaders;
    _includeStackTraces = resolved.includeStackTraces;
    includeStackTraces = resolved.includeStackTraces;
    RoutedLogger.setGlobalFormat(resolved.format.formatter);
    _configureLoggerFactory(config, container, resolved);
  }

  String _headerKey(String name) {
    final sanitized = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp('_+'), '_')
        .trim();
    return 'header_${sanitized.isEmpty ? 'unnamed' : sanitized}';
  }
}

void _configureLoggerFactory(
  Config config,
  Container container,
  LoggingConfig settings,
) {
  final resolved = _resolveChannelSettings(settings);
  final registry = container.get<LogDriverRegistry>();
  final builder = _LoggerFactoryBuilder(
    defaultChannel: resolved.defaultChannel,
    channels: resolved.channels,
    registry: registry,
    config: config,
    container: container,
  );
  RoutedLogger.configureSystemFactory(builder.createLogger);
}

_ChannelSettings _resolveChannelSettings(LoggingConfig config) {
  final defaultChannel = _coerceChannelName(config.defaultChannel);
  final envChannel = _coerceChannelName(Platform.environment['LOG_CHANNEL']);

  final channels = <String, _ChannelConfig>{};
  config.channels.forEach((name, channel) {
    final contextPath = 'logging.channels.$name';
    channels[name] = _ChannelConfig(
      name: name,
      driver: channel.driver,
      options: channel.toMap(),
      contextPath: contextPath,
    );
  });

  final resolvedDefault =
      defaultChannel ??
      envChannel ??
      (channels.containsKey('stack')
          ? 'stack'
          : channels.keys.isNotEmpty
          ? channels.keys.first
          : 'stdout');

  return _ChannelSettings(defaultChannel: resolvedDefault, channels: channels);
}

String? _coerceChannelName(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.contains('{{')) {
    return null;
  }
  return trimmed;
}

class _ChannelSettings {
  const _ChannelSettings({
    required this.defaultChannel,
    required this.channels,
  });

  final String defaultChannel;
  final Map<String, _ChannelConfig> channels;
}

class _ChannelConfig {
  const _ChannelConfig({
    required this.name,
    required this.driver,
    required this.options,
    required this.contextPath,
  });

  final String name;
  final String driver;
  final Map<String, Object?> options;
  final String contextPath;
}

class _LoggerFactoryBuilder {
  _LoggerFactoryBuilder({
    required this.defaultChannel,
    required Map<String, _ChannelConfig> channels,
    required this.registry,
    required this.config,
    required this.container,
  }) : _channels = channels;

  final String defaultChannel;
  final Map<String, _ChannelConfig> _channels;
  final LogDriverRegistry registry;
  final Config config;
  final Container container;
  final Map<String, contextual.LogDriver> _driverCache = {};
  final Set<String> _resolving = {};

  contextual.Logger createLogger(Map<String, Object?> context) {
    final formatter = RoutedLogger.globalFormat;
    final logger = contextual.Logger(formatter: formatter)
      ..withContext(context);

    final driver = _driverFor(defaultChannel);
    logger.addChannel(defaultChannel, driver);
    return logger;
  }

  contextual.LogDriver _driverFor(String name) {
    if (_driverCache.containsKey(name)) {
      return _driverCache[name]!;
    }
    if (_resolving.contains(name)) {
      throw ProviderConfigException(
        'Circular logging channel reference detected for "$name"',
      );
    }
    _resolving.add(name);
    final driver = _buildDriver(name);
    _resolving.remove(name);
    _driverCache[name] = driver;
    return driver;
  }

  contextual.LogDriver _buildDriver(String name) {
    final spec = _channels[name];
    if (spec == null) {
      throw ProviderConfigException(
        'Unknown logging channel "$name". Define it under logging.channels.',
      );
    }

    final builder = registry.builderFor(spec.driver);
    if (builder == null) {
      throw ProviderConfigException(
        'Unknown logging driver "${spec.driver}" for channel "$name". '
        'Register the driver using LogDriverRegistry.',
      );
    }

    return builder(
      LogDriverBuilderContext(
        name: spec.name,
        configPath: spec.contextPath,
        options: spec.options,
        config: config,
        container: container,
        resolveChannel: _driverFor,
      ),
    );
  }
}
