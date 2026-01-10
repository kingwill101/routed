import 'package:contextual/contextual.dart' as contextual;
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

import '../spec.dart';

class LoggingDriverSpecContext extends ConfigSpecContext {
  const LoggingDriverSpecContext({
    required this.name,
    required this.pathBase,
    super.config,
  });

  final String name;
  final String pathBase;

  String path(String segment) =>
      pathBase.isEmpty ? segment : '$pathBase.$segment';
}

Map<String, dynamic> loggingDriverOptions(Map<String, Object?> options) {
  final map = <String, dynamic>{};
  options.forEach((key, value) {
    map[key.toString()] = value;
  });
  return map;
}

String _pathFor(
  ConfigSpecContext? context,
  String fallbackBase,
  String segment,
) {
  final base = context is LoggingDriverSpecContext
      ? context.pathBase
      : fallbackBase;
  return base.isEmpty ? segment : '$base.$segment';
}

class LoggingSingleDriverConfig {
  const LoggingSingleDriverConfig({required this.path});

  final String path;
}

class LoggingSingleDriverSpec extends ConfigSpec<LoggingSingleDriverConfig> {
  const LoggingSingleDriverSpec();

  @override
  String get root => 'logging.channels.*';

  @override
  Schema? get schema => ConfigSchema.object(
    title: 'Single Log Channel',
    description: 'Logs to a single file.',
    properties: {
      'path': ConfigSchema.string(
        description: 'Path to the log file.',
        defaultValue: 'storage/logs/routed.log',
      ),
    },
  );

  @override
  LoggingSingleDriverConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final path =
        _stringOption(
          map,
          ['path', 'file'],
          context: context,
          defaultValue: 'storage/logs/routed.log',
        ) ??
        'storage/logs/routed.log';
    return LoggingSingleDriverConfig(path: path);
  }

  @override
  Map<String, dynamic> toMap(LoggingSingleDriverConfig value) {
    return {'path': value.path};
  }
}

class LoggingDailyDriverConfig {
  const LoggingDailyDriverConfig({
    required this.path,
    required this.retentionDays,
    required this.flushInterval,
    required this.useIsolate,
  });

  final String path;
  final int retentionDays;
  final Duration flushInterval;
  final bool useIsolate;
}

class LoggingDailyDriverSpec extends ConfigSpec<LoggingDailyDriverConfig> {
  const LoggingDailyDriverSpec();

  @override
  String get root => 'logging.channels.*';

  @override
  Schema? get schema => ConfigSchema.object(
    title: 'Daily Log Channel',
    description: 'Logs to daily rotating files.',
    properties: {
      'path': ConfigSchema.string(
        description: 'Directory path for log files.',
        defaultValue: 'storage/logs/routed',
      ),
      'retention_days': ConfigSchema.integer(
        description: 'Number of days to keep logs.',
        defaultValue: 14,
      ),
      'flush_interval': ConfigSchema.integer(
        description: 'Interval in milliseconds to flush logs.',
        defaultValue: 500,
      ),
      'use_isolate': ConfigSchema.boolean(
        description: 'Use a separate isolate for file I/O.',
        defaultValue: false,
      ),
    },
  );

  @override
  LoggingDailyDriverConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final path =
        _stringOption(
          map,
          ['path', 'directory'],
          context: context,
          defaultValue: 'storage/logs/routed',
        ) ??
        'storage/logs/routed';
    final retention =
        _intFrom(map, [
          'retentionDays',
          'retention_days',
          'days',
        ], context: context) ??
        14;
    final flushInterval = _durationFrom(
      map['flushInterval'] ?? map['flush_interval'],
      context: context,
      fallback: const Duration(milliseconds: 500),
    );
    final useIsolate =
        _boolFrom(map, ['useIsolate', 'use_isolate'], context: context) ??
        false;

    return LoggingDailyDriverConfig(
      path: path,
      retentionDays: retention,
      flushInterval: flushInterval,
      useIsolate: useIsolate,
    );
  }

  @override
  Map<String, dynamic> toMap(LoggingDailyDriverConfig value) {
    return {
      'path': value.path,
      'retention_days': value.retentionDays,
      'flush_interval': value.flushInterval.inMilliseconds,
      'use_isolate': value.useIsolate,
    };
  }
}

class LoggingStackDriverConfig {
  const LoggingStackDriverConfig({
    required this.channels,
    required this.ignoreExceptions,
  });

  final List<String> channels;
  final bool ignoreExceptions;
}

class LoggingStackDriverSpec extends ConfigSpec<LoggingStackDriverConfig> {
  const LoggingStackDriverSpec();

  @override
  String get root => 'logging.channels.*';

  @override
  Schema? get schema => ConfigSchema.object(
    title: 'Stack Log Channel',
    description: 'Combines multiple channels.',
    properties: {
      'channels': ConfigSchema.list(
        description: 'List of channel names to include in the stack.',
        items: ConfigSchema.string(),
        defaultValue: const <String>[],
      ),
      'ignore_exceptions': ConfigSchema.boolean(
        description: 'Ignore exceptions from underlying channels.',
        defaultValue: false,
      ),
    },
  );

  @override
  LoggingStackDriverConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final channels =
        parseStringList(
          map['channels'],
          context: _pathFor(context, root, 'channels'),
          allowEmptyResult: true,
          throwOnInvalid: false,
        ) ??
        const <String>[];
    if (channels.isEmpty) {
      final contextPath = _pathFor(context, root, 'channels');
      final name = context is LoggingDriverSpecContext
          ? context.name
          : 'unknown';
      throw ProviderConfigException(
        'logging channel "$name" must specify at least one entry in $contextPath',
      );
    }

    final ignore =
        parseBoolLike(
          map['ignore_exceptions'],
          context: _pathFor(context, root, 'ignore_exceptions'),
          throwOnInvalid: false,
        ) ??
        false;

    return LoggingStackDriverConfig(
      channels: channels,
      ignoreExceptions: ignore,
    );
  }

  @override
  Map<String, dynamic> toMap(LoggingStackDriverConfig value) {
    return {
      'channels': value.channels,
      'ignore_exceptions': value.ignoreExceptions,
    };
  }
}

class LoggingWebhookDriverConfig {
  const LoggingWebhookDriverConfig({
    required this.url,
    required this.headers,
    required this.timeout,
    required this.keepAlive,
  });

  final Uri url;
  final Map<String, String>? headers;
  final Duration timeout;
  final bool keepAlive;
}

class LoggingWebhookDriverSpec extends ConfigSpec<LoggingWebhookDriverConfig> {
  const LoggingWebhookDriverSpec();

  @override
  String get root => 'logging.channels.*';

  @override
  Schema? get schema => ConfigSchema.object(
    title: 'Webhook Log Channel',
    description: 'Sends logs to a webhook URL.',
    properties: {
      'url': ConfigSchema.string(
        description: 'The webhook URL.',
        defaultValue: '',
      ),
      'headers': ConfigSchema.object(
        description: 'HTTP headers to include in the request.',
        additionalProperties: true,
      ),
      'timeout': ConfigSchema.integer(
        description: 'Request timeout in milliseconds.',
        defaultValue: 5000,
      ),
      'keep_alive': ConfigSchema.boolean(
        description: 'Use persistent connections.',
        defaultValue: true,
      ),
    },
  );

  @override
  LoggingWebhookDriverConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final rawUrl =
        _stringOption(
          map,
          ['url', 'endpoint', 'uri'],
          context: context,
          defaultValue: '',
        ) ??
        '';
    late Uri uri;
    try {
      uri = Uri.parse(rawUrl);
    } catch (_) {
      throw ProviderConfigException(
        'logging channel has an invalid webhook url: $rawUrl',
      );
    }

    final headers = _stringMap(map['headers']);
    final timeout = _durationFrom(
      map['timeout'] ?? map['timeout_ms'],
      context: context,
      fallback: const Duration(seconds: 5),
    );
    final keepAlive =
        _boolFrom(
          map,
          ['keep_alive', 'keepAlive'],
          context: context,
          defaultValue: true,
        ) ??
        true;

    return LoggingWebhookDriverConfig(
      url: uri,
      headers: headers,
      timeout: timeout,
      keepAlive: keepAlive,
    );
  }

  @override
  Map<String, dynamic> toMap(LoggingWebhookDriverConfig value) {
    return {
      'url': value.url.toString(),
      'headers': value.headers,
      'timeout': value.timeout.inMilliseconds,
      'keep_alive': value.keepAlive,
    };
  }
}

class LoggingSamplingDriverConfig {
  const LoggingSamplingDriverConfig({
    required this.wrapped,
    required this.rates,
  });

  final String wrapped;
  final Map<contextual.Level, double> rates;
}

class LoggingSamplingDriverSpec
    extends ConfigSpec<LoggingSamplingDriverConfig> {
  const LoggingSamplingDriverSpec();

  @override
  String get root => 'logging.channels.*';

  @override
  Schema? get schema => ConfigSchema.object(
    title: 'Sampling Log Channel',
    description: 'Samples logs at configured rates.',
    properties: {
      'wrapped': ConfigSchema.string(description: 'The channel to wrap.'),
      'rates': ConfigSchema.object(
        description: 'Sampling rates per log level (0.0 to 1.0).',
        additionalProperties: true,
      ),
    },
  );

  @override
  LoggingSamplingDriverConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final wrapped = _stringOption(map, [
      'wrapped',
      'wrapped_channel',
      'channel',
    ], context: context);
    if (wrapped == null || wrapped.isEmpty) {
      final name = context is LoggingDriverSpecContext
          ? context.name
          : 'unknown';
      final path = _pathFor(context, root, 'wrapped_channel');
      throw ProviderConfigException(
        'logging channel "$name" must specify a wrapped channel ($path)',
      );
    }
    final rates = _parseSamplingRates(map['rates'], context: context);
    return LoggingSamplingDriverConfig(wrapped: wrapped, rates: rates);
  }

  @override
  Map<String, dynamic> toMap(LoggingSamplingDriverConfig value) {
    final rates = <String, double>{};
    value.rates.forEach((level, rate) {
      rates[level.name] = rate;
    });
    return {'wrapped': value.wrapped, 'rates': rates};
  }
}

String? _stringOption(
  Map<String, dynamic> options,
  List<String> keys, {
  required ConfigSpecContext? context,
  String? defaultValue,
}) {
  for (final key in keys) {
    final value = options[key];
    if (value != null) {
      final parsed = parseStringLike(
        value,
        context: _pathFor(context, 'logging.channels.*', key),
        allowEmpty: false,
        coerceNonString: true,
        throwOnInvalid: false,
      );
      if (parsed != null && parsed.isNotEmpty) {
        return parsed;
      }
    }
  }
  return defaultValue;
}

int? _intFrom(
  Map<String, dynamic> options,
  List<String> keys, {
  required ConfigSpecContext? context,
}) {
  for (final key in keys) {
    final value = options[key];
    if (value != null) {
      final parsed = parseIntLike(
        value,
        context: _pathFor(context, 'logging.channels.*', key),
        throwOnInvalid: false,
      );
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

bool? _boolFrom(
  Map<String, dynamic> options,
  List<String> keys, {
  required ConfigSpecContext? context,
  bool? defaultValue,
}) {
  for (final key in keys) {
    final value = options[key];
    if (value != null) {
      final parsed = parseBoolLike(
        value,
        context: _pathFor(context, 'logging.channels.*', key),
        throwOnInvalid: false,
      );
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return defaultValue;
}

Duration _durationFrom(
  Object? value, {
  required ConfigSpecContext? context,
  Duration? fallback,
}) {
  if (value == null) {
    return fallback ?? const Duration(milliseconds: 500);
  }
  if (value is Duration) {
    return value;
  }
  final parsed = value is num
      ? parseDurationLike(
          '${value}ms',
          context: _pathFor(context, 'logging.channels.*', 'duration'),
          throwOnInvalid: false,
        )
      : parseDurationLike(
          value,
          context: _pathFor(context, 'logging.channels.*', 'duration'),
          throwOnInvalid: false,
        );
  if (parsed != null) {
    return parsed;
  }
  return fallback ?? const Duration(milliseconds: 500);
}

Map<String, String>? _stringMap(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! Map) {
    return null;
  }
  final filtered = <String, dynamic>{};
  value.forEach((key, entryValue) {
    if (entryValue != null) {
      filtered[key.toString()] = entryValue;
    }
  });
  if (filtered.isEmpty) {
    return null;
  }
  final parsed = parseStringMap(
    filtered,
    context: 'logging.headers',
    allowEmptyValues: true,
    coerceValues: true,
  );
  return parsed.isEmpty ? null : parsed;
}

Map<contextual.Level, double> _parseSamplingRates(
  Object? value, {
  required ConfigSpecContext? context,
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

double? _doubleFromValue(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
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
