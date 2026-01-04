import 'dart:async';
import 'dart:io';

import 'package:contextual/contextual.dart' as contextual;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/logging/channel_drivers.dart';
import 'package:routed/src/logging/context.dart';
import 'package:routed/src/logging/driver_registry.dart';
import 'package:routed/src/logging/logger.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/router/types.dart';

/// Registers logging defaults and related middleware identifiers.
const Map<String, Object?> _defaultLoggingChannels = {
  'stack': {
    'driver': 'stack',
    'channels': ['single', 'stdout'],
    'ignore_exceptions': false,
  },
  'single': {'driver': 'single', 'path': 'storage/logs/routed.log'},
  'daily': {
    'driver': 'daily',
    'path': 'storage/logs/routed',
    'days': 14,
    'use_isolate': false,
  },
  'stderr': {'driver': 'stderr'},
  'stdout': {'driver': 'stdout'},
  'null': {'driver': 'null'},
};

class LoggingServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  bool _enabled = true;
  bool _logSuccess = true;
  contextual.Level _level = contextual.Level.info;
  Map<String, dynamic> _extraFields = const {};
  List<String> _headerNames = const [];
  bool _includeStackTraces = false;

  static bool includeStackTraces = false;

  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    docs: <ConfigDocEntry>[
      ConfigDocEntry(
        path: 'http.middleware_sources',
        type: 'map',
        description: 'Logging middleware references injected globally.',
        defaultValue: <String, Object?>{
          'routed.logging': <String, Object?>{
            'global': <String>['routed.logging.http'],
          },
        },
      ),
      ConfigDocEntry(
        path: 'logging.default',
        type: 'string',
        description: 'Default log channel name (stack, single, stderr, etc.).',
        defaultValue: 'stack',
        metadata: {configDocMetaInheritFromEnv: 'LOG_CHANNEL'},
      ),
      ConfigDocEntry(
        path: 'logging.channels',
        type: 'map',
        description:
            'Map of log channel definitions (stack, single, daily, stderr, null).',
        defaultValue: _defaultLoggingChannels,
      ),
      ConfigDocEntry(
        path: 'logging.enabled',
        type: 'bool',
        description: 'Enable structured application logging.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: 'logging.level',
        type: 'string',
        description: 'Default log level for application logging.',
        options: ['debug', 'info'],
        defaultValue: 'info',
      ),
      ConfigDocEntry(
        path: 'logging.errors_only',
        type: 'bool',
        description: 'Only emit logs for failing requests when true.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'logging.extra_fields',
        type: 'map',
        description: 'Additional fields appended to every log entry.',
        defaultValue: <String, Object?>{},
      ),
      ConfigDocEntry(
        path: 'logging.include_stack_traces',
        type: 'bool',
        description: 'Include stack traces in request error logs when enabled.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'logging.format',
        type: 'string',
        description: 'Log output format (json or text).',
        options: ["json", "null", "plain", "pretty", "raw"],
        defaultValue: 'pretty',
      ),
      ConfigDocEntry(
        path: 'logging.request_headers',
        type: 'list<string>',
        description: 'Headers captured globally on every log entry.',
        defaultValue: <String>[],
      ),
    ],
  );

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
      final path = _stringOption(ctx.options, ['path', 'file']);
      return SingleFileLogDriver(
        (path == null || path.isEmpty) ? 'storage/logs/routed.log' : path,
      );
    });
    registry.registerIfAbsent('daily', (ctx) {
      final path =
          _stringOption(ctx.options, ['path', 'directory']) ??
          'storage/logs/routed';
      final retention =
          _intFrom(ctx.options, ['retentionDays', 'retention_days', 'days']) ??
          14;
      final flushInterval = _durationFrom(
        ctx.options['flushInterval'] ?? ctx.options['flush_interval'],
        fallback: const Duration(milliseconds: 500),
      );
      final optionsMap = {
        for (final entry in ctx.options.entries)
          entry.key.toString(): entry.value,
      };
      final useIsolate =
          optionsMap.getBool('useIsolate') || optionsMap.getBool('use_isolate');
      final options = contextual.DailyFileOptions(
        path: path,
        retentionDays: retention,
        flushInterval: flushInterval,
      );
      return contextual.DailyFileLogDriver.fromOptions(
        options,
        useIsolate: useIsolate,
      );
    });
    registry.registerIfAbsent('stack', (ctx) {
      final optionsMap = {
        for (final entry in ctx.options.entries)
          entry.key.toString(): entry.value,
      };
      final channels = optionsMap.getStringList('channels') ?? const <String>[];
      if (channels.isEmpty) {
        throw ProviderConfigException(
          'logging channel "${ctx.name}" must specify at least one entry in ${ctx.configPath}.channels',
        );
      }
      final ignore = optionsMap.getBool('ignore_exceptions');
      final drivers = channels.map(ctx.resolveChannel).toList();
      return contextual.StackLogDriver(drivers, ignoreExceptions: ignore);
    });
    registry.registerIfAbsent('webhook', (ctx) {
      final optionsMap = {
        for (final entry in ctx.options.entries)
          entry.key.toString(): entry.value,
      };
      final rawUrl =
          _stringOption(ctx.options, ['url', 'endpoint', 'uri']) ?? '';
      late Uri uri;
      try {
        uri = Uri.parse(rawUrl);
      } catch (_) {
        throw ProviderConfigException(
          'logging channel "${ctx.name}" has an invalid webhook url: $rawUrl',
        );
      }
      final headers = _stringMap(ctx.options['headers']);
      final timeout = _durationFrom(
        ctx.options['timeout'] ?? ctx.options['timeout_ms'],
        fallback: const Duration(seconds: 5),
      );
      final keepAlive =
          optionsMap.getBool('keep_alive', defaultValue: true) ||
          optionsMap.getBool('keepAlive', defaultValue: true);
      final options = contextual.WebhookOptions(
        url: uri,
        headers: headers,
        timeout: timeout,
        keepAlive: keepAlive,
      );
      return contextual.WebhookLogDriver.fromOptions(options);
    });
    registry.registerIfAbsent('sampling', (ctx) {
      final wrapped = _stringOption(ctx.options, [
        'wrapped',
        'wrapped_channel',
        'channel',
      ]);
      if (wrapped == null || wrapped.isEmpty) {
        throw ProviderConfigException(
          'logging channel "${ctx.name}" must specify a wrapped channel (${ctx.configPath}.wrapped_channel)',
        );
      }
      final rates = _parseSamplingRates(
        ctx.options['rates'],
        contextPath: '${ctx.configPath}.rates',
      );
      final wrappedDriver = ctx.resolveChannel(wrapped);
      return contextual.SamplingLogDriver.fromOptions(wrappedDriver, rates);
    });
  }

  void _applyConfig(Config config, Container container) {
    final resolved = _resolveLoggingConfig(config);
    _enabled = resolved.enabled;
    _logSuccess = resolved.logSuccess;
    _level = resolved.level;
    _extraFields = resolved.extraFields;
    _headerNames = resolved.headerNames;
    _includeStackTraces = resolved.includeStackTraces;
    includeStackTraces = resolved.includeStackTraces;
    RoutedLogger.setGlobalFormat(resolved.format);
    _configureLoggerFactory(config, container);
  }

  _LoggingConfig _resolveLoggingConfig(Config config) {
    final merged = mergeConfigCandidates([
      ConfigMapCandidate.fromConfig(config, 'logging'),
    ]);

    final enabled = merged.getBool('enabled', defaultValue: true);
    final errorsOnly = merged.getBool('errors_only');

    final levelToken = merged.getString('level');
    final level = _parseLevel(levelToken);

    final extraFields =
        merged.containsKey('extra_fields') && merged['extra_fields'] != null
        ? stringKeyedMap(
            merged['extra_fields']! as Object,
            'logging.extra_fields',
          )
        : const <String, dynamic>{};

    final headerNamesRaw = merged['request_headers'];
    List<String> headerNames;
    if (headerNamesRaw != null) {
      if (headerNamesRaw is! List) {
        throw ProviderConfigException('logging.request_headers must be a list');
      }
      headerNames = [];
      for (var i = 0; i < headerNamesRaw.length; i++) {
        final item = headerNamesRaw[i];
        if (item is! String) {
          throw ProviderConfigException(
            'logging.request_headers[$i] must be a string',
          );
        }
        headerNames.add(item);
      }
    } else {
      headerNames = const [];
    }

    final includeStackTraces = merged.getBool('include_stack_traces');

    final formatToken =
        merged.getString('format')?.toLowerCase().trim() ?? 'plain';

    final format = switch (formatToken) {
      "pretty" => contextual.PrettyLogFormatter(),
      "raw" => contextual.RawLogFormatter(),
      "null" => contextual.JsonLogFormatter(),
      "json" => contextual.JsonLogFormatter(),
      "plain" => contextual.PlainTextLogFormatter(),
      _ => contextual.PlainTextLogFormatter(),
    };

    return _LoggingConfig(
      enabled: enabled,
      logSuccess: !errorsOnly,
      level: level,
      extraFields: extraFields,
      headerNames: headerNames,
      includeStackTraces: includeStackTraces,
      format: format,
    );
  }

  contextual.Level _parseLevel(String? raw) {
    final token = raw?.trim();
    if (token == null || token.isEmpty) {
      return contextual.Level.info;
    }
    final needle = token.toLowerCase();
    for (final level in contextual.Level.levels) {
      if (level.name.toLowerCase() == needle ||
          level.toString().toLowerCase() == needle) {
        return level;
      }
    }
    throw ProviderConfigException(
      'logging.level must be one of: '
      '${contextual.Level.levels.map((l) => l.name).join(', ')}',
    );
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

class _LoggingConfig {
  const _LoggingConfig({
    required this.enabled,
    required this.logSuccess,
    required this.level,
    required this.extraFields,
    required this.headerNames,
    required this.includeStackTraces,
    required this.format,
  });

  final bool enabled;
  final bool logSuccess;
  final contextual.Level level;
  final Map<String, dynamic> extraFields;
  final List<String> headerNames;
  final bool includeStackTraces;
  final contextual.LogMessageFormatter format;
}

void _configureLoggerFactory(Config config, Container container) {
  final settings = _resolveChannelSettings(config);
  final registry = container.get<LogDriverRegistry>();
  final builder = _LoggerFactoryBuilder(
    defaultChannel: settings.defaultChannel,
    channels: settings.channels,
    registry: registry,
    config: config,
    container: container,
  );
  RoutedLogger.configureSystemFactory(builder.createLogger);
}

_ChannelSettings _resolveChannelSettings(Config config) {
  final configValue = config.getStringOrNull('logging.default')?.trim();
  final defaultChannel = _coerceChannelName(configValue);
  final envChannel = _coerceChannelName(Platform.environment['LOG_CHANNEL']);

  final node = config.get<Map<String, Object?>>('logging.channels');
  final channels = <String, _ChannelConfig>{};
  if (node is Map<String, Object?>) {
    final map = stringKeyedMap(node, 'logging.channels');
    map.forEach((name, value) {
      final contextPath = 'logging.channels.$name';
      final channelMap = value is Map<String, Object?>
          ? stringKeyedMap(value, contextPath)
          : const <String, Object?>{};
      final rawDriver =
          channelMap.getString('driver')?.toLowerCase().trim() ?? 'stack';
      channels[name] = _ChannelConfig(
        name: name,
        driver: rawDriver,
        options: channelMap,
        contextPath: contextPath,
      );
    });
  }

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

Map<contextual.Level, double> _parseSamplingRates(
  Object? value, {
  required String contextPath,
}) {
  final result = <contextual.Level, double>{};
  if (value is Map) {
    value.forEach((key, rateValue) {
      final level = _levelFromName(key?.toString() ?? '');
      final rate = _doubleFromValue(rateValue);
      if (level != null && rate != null) {
        result[level] = rate.clamp(0.0, 1.0);
      }
    });
  }
  return result;
}

String? _stringOption(Map<String, Object?> options, List<String> keys) {
  for (final key in keys) {
    final value = options[key];
    if (value != null) {
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
  }
  return null;
}

int? _intFrom(Map<String, Object?> options, List<String> keys) {
  for (final key in keys) {
    final value = options[key];
    if (value != null) {
      final parsed = _intFromValue(value);
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

int? _intFromValue(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _doubleFromValue(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

Duration _durationFrom(Object? value, {Duration? fallback}) {
  if (value == null) {
    return fallback ?? const Duration(milliseconds: 500);
  }
  if (value is Duration) {
    return value;
  }
  if (value is num) {
    return Duration(milliseconds: value.toInt());
  }
  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty) {
    return fallback ?? const Duration(milliseconds: 500);
  }
  if (text.endsWith('ms')) {
    final amount = int.tryParse(text.substring(0, text.length - 2).trim());
    if (amount != null) {
      return Duration(milliseconds: amount);
    }
  }
  if (text.endsWith('s')) {
    final amount = double.tryParse(text.substring(0, text.length - 1).trim());
    if (amount != null) {
      return Duration(milliseconds: (amount * 1000).round());
    }
  }
  final numeric = double.tryParse(text);
  if (numeric != null) {
    return Duration(milliseconds: numeric.round());
  }
  return fallback ?? const Duration(milliseconds: 500);
}

Map<String, String>? _stringMap(Object? value) {
  if (value is Map) {
    final result = <String, String>{};
    value.forEach((key, entryValue) {
      if (key != null && entryValue != null) {
        result[key.toString()] = entryValue.toString();
      }
    });
    return result.isEmpty ? null : result;
  }
  return null;
}

contextual.Level? _levelFromName(String name) {
  final needle = name.trim().toLowerCase();
  if (needle.isEmpty) {
    return null;
  }
  for (final level in contextual.Level.values) {
    if (level.name.toLowerCase() == needle) {
      return level;
    }
  }
  return null;
}
