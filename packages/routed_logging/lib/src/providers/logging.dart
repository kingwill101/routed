import 'dart:async';

import 'package:contextual/contextual.dart' as contextual;
import 'package:routed_core/routed_core.dart'
    show
        ConsoleLoggingChannelConfig,
        CustomLoggingChannelConfig,
        DailyFileLoggingChannelConfig,
        Engine,
        EventManager,
        LoggingChannelConfig,
        LoggingConfig,
        NullLoggingChannelConfig,
        RoutingErrorEvent,
        SamplingLoggingChannelConfig,
        SingleFileLoggingChannelConfig,
        StackLoggingChannelConfig,
        StderrLoggingChannelConfig,
        StdoutLoggingChannelConfig,
        WebhookLoggingChannelConfig;
import 'package:routed_core/src/container/container.dart';
import 'package:routed_core/src/context/context.dart';
import 'package:routed_core/src/engine/middleware_registry.dart';
import 'package:routed_core/src/provider/provider.dart';
import 'package:routed_core/src/provider/typed_provider.dart';
import 'package:routed_core/src/router/types.dart';
import 'package:routed_logging/src/logging/channel_drivers.dart';
import 'package:routed_logging/src/logging/context.dart';
import 'package:routed_logging/src/logging/driver_registry.dart';
import 'package:routed_logging/src/logging/logger.dart';

/// Configures request logging and logging channel drivers for an engine.
class LoggingServiceProvider extends ServiceProvider
    with ProvidesTypedConfiguration<LoggingConfig> {
  /// Creates a logging provider with optional typed [configuration].
  LoggingServiceProvider([LoggingConfig? configuration])
    : configuration = configuration ?? LoggingConfig();

  /// The typed logging configuration applied during engine boot.
  @override
  final LoggingConfig configuration;

  bool _enabled = true;
  bool _logSuccess = true;
  contextual.Level _level = contextual.Level.info;
  Map<String, dynamic> _extraFields = const {};
  List<String> _headerNames = const [];
  bool _includeStackTraces = false;
  StreamSubscription<RoutingErrorEvent>? _errorSubscription;

  /// Whether request stack traces are included in log output by default.
  static bool includeStackTraces = false;

  static const _startedAtKey = 'routed.logging.started_at';

  @override
  void register(Container container) {
    _ensureDriverRegistry(container);
    if (container.has<MiddlewareRegistry>()) {
      container.get<MiddlewareRegistry>().register(
        'routed.logging.http',
        (_) => _loggingMiddleware,
      );
    }
  }

  @override
  Future<void> boot(Container container) async {
    if (!container.has<Engine>()) {
      return;
    }

    _applyConfig(configuration, container);
    container.get<Engine>().middlewares.insert(0, _loggingMiddleware);
    _subscribeToRoutingErrors(container);
  }

  @override
  Future<void> cleanup(Container container) async {
    await _errorSubscription?.cancel();
    _errorSubscription = null;
  }

  Middleware get _loggingMiddleware {
    return (EngineContext ctx, Next next) async {
      if (!_enabled) {
        return await next();
      }

      final startedAt = DateTime.now();
      ctx.set(_startedAtKey, startedAt);
      final engine = ctx.engine;
      if (engine == null) {
        return await next();
      }

      return LoggingContext.run(engine, ctx, (_) async {
        try {
          final response = await next();
          if (_logSuccess) {
            _log(
              ctx,
              response.statusCode,
              DateTime.now().difference(startedAt),
            );
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
      });
    };
  }

  void _subscribeToRoutingErrors(Container container) {
    if (!container.has<EventManager>()) {
      return;
    }
    unawaited(_errorSubscription?.cancel() ?? Future<void>.value());
    _errorSubscription = container
        .get<EventManager>()
        .listen<RoutingErrorEvent>((event) {
          if (!_enabled) {
            return;
          }
          final startedAt = event.context.get<DateTime>(_startedAtKey);
          _log(
            event.context,
            event.context.response.statusCode,
            startedAt == null
                ? Duration.zero
                : DateTime.now().difference(startedAt),
            error: event.error,
            stackTrace: event.stackTrace,
            message: 'Unhandled exception',
          );
        });
  }

  void _log(
    EngineContext ctx,
    int status,
    Duration duration, {
    Object? error,
    StackTrace? stackTrace,
    String message = 'Request failed',
  }) {
    final method = ctx.request.method;
    final path = ctx.request.uri.path;
    final durationMs = duration.inMilliseconds;

    // Build structured context with all the details
    final payload = <String, Object?>{
      'request_id': ctx.id,
      'method': method,
      'path': path,
      'status': status,
      'duration_ms': durationMs,
    };

    // Add any custom logging context from the request
    final loggingContext = LoggingContext.currentValues(ctx);
    if (!identical(loggingContext, const {})) {
      payload.addAll(loggingContext);
    }

    // Add configured request headers
    for (final header in _headerNames) {
      final value = ctx.request.headers.value(header);
      if (value != null) {
        payload[_headerKey(header)] = value;
      }
    }

    // Add any extra fields from config
    payload.addAll(_extraFields);

    if (error != null) {
      payload['error'] = error.toString();
      if (_includeStackTraces && stackTrace != null) {
        payload['stack_trace'] = stackTrace.toString();
      }
    }

    final logger = RoutedLogger.create(payload);

    if (error != null) {
      logger.error(message);
      return;
    }

    logger.log(_level, 'Request completed');
  }

  void _ensureDriverRegistry(Container container) {
    if (!container.has<LogDriverRegistry>()) {
      container.instance<LogDriverRegistry>(LogDriverRegistry());
    }
  }

  void _applyConfig(LoggingConfig resolved, Container container) {
    _enabled = resolved.enabled;
    _logSuccess = resolved.logSuccess;
    _level = resolved.level;
    _extraFields = resolved.extraFields;
    _headerNames = resolved.requestHeaders;
    _includeStackTraces = resolved.includeStackTraces;
    includeStackTraces = resolved.includeStackTraces;
    RoutedLogger.setGlobalFormat(resolved.format.formatter);
    _configureLoggerFactory(container, resolved);
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

void _configureLoggerFactory(Container container, LoggingConfig settings) {
  final registry = container.get<LogDriverRegistry>();
  final builder = _LoggerFactoryBuilder(
    defaultChannel: settings.defaultChannel ?? 'stdout',
    channels: settings.channels,
    registry: registry,
    config: settings,
    container: container,
  );
  RoutedLogger.configureSystemFactory(builder.createLogger);
}

class _LoggerFactoryBuilder {
  _LoggerFactoryBuilder({
    required this.defaultChannel,
    required Map<String, LoggingChannelConfig> channels,
    required this.registry,
    required this.config,
    required this.container,
  }) : _channels = channels;

  final String defaultChannel;
  final Map<String, LoggingChannelConfig> _channels;
  final LogDriverRegistry registry;
  final LoggingConfig config;
  final Container container;
  final Map<String, contextual.LogDriver> _driverCache = {};
  final Set<String> _resolving = {};

  contextual.Logger createLogger(Map<String, Object?> context) {
    final formatter = RoutedLogger.globalFormat;
    final channelOverride = _resolveChannelOverride(context);
    final cleanContext = Map<String, Object?>.from(context)
      ..remove(RoutedLogger.channelOverrideKey);
    final logger = contextual.Logger(formatter: formatter)
      ..withContext(cleanContext);

    final channel = channelOverride ?? defaultChannel;
    final driver = _driverFor(channel);
    logger.addChannel(channel, driver);
    return logger;
  }

  String? _resolveChannelOverride(Map<String, Object?> context) {
    final value = context[RoutedLogger.channelOverrideKey];
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
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
    final channel = _channels[name];
    if (channel == null) {
      throw ProviderConfigException(
        'Unknown logging channel "$name". Define it under logging.channels.',
      );
    }

    switch (channel) {
      case ConsoleLoggingChannelConfig():
      case StdoutLoggingChannelConfig():
        return contextual.ConsoleLogDriver();
      case StderrLoggingChannelConfig():
        return StderrLogDriver();
      case NullLoggingChannelConfig():
        return NullLogDriver();
      case SingleFileLoggingChannelConfig(:final path):
        return SingleFileLogDriver(path);
      case DailyFileLoggingChannelConfig(
        :final path,
        :final retentionDays,
        :final flushInterval,
        :final useIsolate,
      ):
        return contextual.DailyFileLogDriver.fromOptions(
          contextual.DailyFileOptions(
            path: path,
            retentionDays: retentionDays,
            flushInterval: flushInterval,
          ),
          useIsolate: useIsolate,
        );
      case StackLoggingChannelConfig(:final channels, :final ignoreExceptions):
        return contextual.StackLogDriver(
          channels.map(_driverFor).toList(growable: false),
          ignoreExceptions: ignoreExceptions,
        );
      case WebhookLoggingChannelConfig(
        :final url,
        :final headers,
        :final timeout,
        :final keepAlive,
      ):
        return contextual.WebhookLogDriver.fromOptions(
          contextual.WebhookOptions(
            url: url,
            headers: headers,
            timeout: timeout,
            keepAlive: keepAlive,
          ),
        );
      case SamplingLoggingChannelConfig(:final wrappedChannel, :final rates):
        return contextual.SamplingLogDriver.fromOptions(
          _driverFor(wrappedChannel),
          rates,
        );
      case CustomLoggingChannelConfig(:final driver, :final options):
        final builder = registry.builderFor(driver);
        if (builder == null) {
          throw ProviderConfigException(
            'Unknown custom logging driver "$driver" for channel "$name". '
            'Register it using LogDriverRegistry.',
          );
        }
        return builder(
          LogDriverBuilderContext(
            name: channel.name,
            configPath: 'logging.channels.$name',
            options: options,
            config: config,
            container: container,
            resolveChannel: _driverFor,
          ),
        );
    }
  }
}
