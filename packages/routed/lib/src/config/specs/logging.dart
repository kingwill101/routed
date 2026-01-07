import 'package:contextual/contextual.dart' as contextual;
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

import '../spec.dart';

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

class LoggingChannelConfig {
  LoggingChannelConfig({
    required this.name,
    required this.driver,
    Map<String, dynamic>? options,
  }) : options = options ?? const <String, dynamic>{};

  final String name;
  final String driver;
  final Map<String, dynamic> options;

  factory LoggingChannelConfig.fromMap(
    String name,
    Map<String, dynamic> map, {
    required String context,
  }) {
    final rawDriver = map['driver'];
    final driver = parseStringLike(
      rawDriver,
      context: '$context.driver',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final resolvedDriver =
        (driver == null || driver.isEmpty) ? 'stack' : driver.toLowerCase();
    final options = <String, dynamic>{};
    map.forEach((key, value) {
      options[key.toString()] = value;
    });
    options['driver'] = resolvedDriver;
    return LoggingChannelConfig(
      name: name,
      driver: resolvedDriver,
      options: options,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{...options};
    map['driver'] = driver;
    return map;
  }
}

class LoggingFormatConfig {
  LoggingFormatConfig(this.token, this.formatter);

  final String token;
  final contextual.LogMessageFormatter formatter;
}

class LoggingConfig {
  LoggingConfig({
    required this.enabled,
    required this.errorsOnly,
    required this.level,
    required this.extraFields,
    required this.requestHeaders,
    required this.includeStackTraces,
    required this.format,
    required this.channels,
    this.defaultChannel,
  });

  final bool enabled;
  final bool errorsOnly;
  final contextual.Level level;
  final Map<String, dynamic> extraFields;
  final List<String> requestHeaders;
  final bool includeStackTraces;
  final LoggingFormatConfig format;
  final String? defaultChannel;
  final Map<String, LoggingChannelConfig> channels;

  bool get logSuccess => !errorsOnly;
}

class LoggingConfigSpec extends ConfigSpec<LoggingConfig> {
  const LoggingConfigSpec();

  @override
  String get root => 'logging';

  @override
  Map<String, dynamic> defaults({ConfigSpecContext? context}) {
    return {
      'default': 'stack',
      'channels': _defaultLoggingChannels,
      'enabled': true,
      'level': 'info',
      'errors_only': false,
      'extra_fields': const <String, Object?>{},
      'include_stack_traces': false,
      'format': 'pretty',
      'request_headers': const <String>[],
    };
  }

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    final base = pathBase ?? root;
    String path(String segment) => base.isEmpty ? segment : '$base.$segment';

    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: path('default'),
        type: 'string',
        description: 'Default log channel name (stack, single, stderr, etc.).',
        defaultValue: 'stack',
        metadata: {configDocMetaInheritFromEnv: 'LOG_CHANNEL'},
      ),
      ConfigDocEntry(
        path: path('channels'),
        type: 'map',
        description:
            'Map of log channel definitions (stack, single, daily, stderr, null).',
        defaultValue: _defaultLoggingChannels,
      ),
      ConfigDocEntry(
        path: path('enabled'),
        type: 'bool',
        description: 'Enable structured application logging.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: path('level'),
        type: 'string',
        description: 'Default log level for application logging.',
        options: ['debug', 'info'],
        defaultValue: 'info',
      ),
      ConfigDocEntry(
        path: path('errors_only'),
        type: 'bool',
        description: 'Only emit logs for failing requests when true.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: path('extra_fields'),
        type: 'map',
        description: 'Additional fields appended to every log entry.',
        defaultValue: const <String, Object?>{},
      ),
      ConfigDocEntry(
        path: path('include_stack_traces'),
        type: 'bool',
        description: 'Include stack traces in request error logs when enabled.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: path('format'),
        type: 'string',
        description: 'Log output format (json or text).',
        options: ["json", "null", "plain", "pretty", "raw"],
        defaultValue: 'pretty',
      ),
      ConfigDocEntry(
        path: path('request_headers'),
        type: 'list<string>',
        description: 'Headers captured globally on every log entry.',
        defaultValue: const <String>[],
      ),
    ];
  }

  @override
  LoggingConfig fromMap(Map<String, dynamic> map, {ConfigSpecContext? context}) {
    final enabled =
        parseBoolLike(
          map['enabled'],
          context: 'logging.enabled',
          throwOnInvalid: true,
        ) ??
        true;

    final errorsOnly =
        parseBoolLike(
          map['errors_only'],
          context: 'logging.errors_only',
          throwOnInvalid: true,
        ) ??
        false;

    final includeStackTraces =
        parseBoolLike(
          map['include_stack_traces'],
          context: 'logging.include_stack_traces',
          throwOnInvalid: true,
        ) ??
        false;

    String? defaultChannel;
    final defaultChannelValue = parseStringLike(
      map['default'],
      context: 'logging.default',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    if (defaultChannelValue != null && defaultChannelValue.isNotEmpty) {
      defaultChannel = defaultChannelValue;
    }

    final extraFieldsValue = map['extra_fields'];
    final Map<String, dynamic> extraFields;
    if (extraFieldsValue == null) {
      extraFields = const <String, dynamic>{};
    } else {
      extraFields =
          stringKeyedMap(extraFieldsValue as Object, 'logging.extra_fields');
    }

    final headerNames =
        parseStringList(
          map['request_headers'],
          context: 'logging.request_headers',
          allowEmptyResult: true,
          throwOnInvalid: true,
        ) ??
        const <String>[];

    final levelValue = parseStringLike(
      map['level'],
      context: 'logging.level',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final contextual.Level level;
    if (levelValue == null || levelValue.isEmpty) {
      level = contextual.Level.info;
    } else {
      final needle = levelValue.toLowerCase();
      contextual.Level? resolved;
      for (final candidate in contextual.Level.levels) {
        if (candidate.name.toLowerCase() == needle ||
            candidate.toString().toLowerCase() == needle) {
          resolved = candidate;
          break;
        }
      }
      if (resolved == null) {
        throw ProviderConfigException(
          'logging.level must be one of: '
          '${contextual.Level.levels.map((l) => l.name).join(', ')}',
        );
      }
      level = resolved;
    }

    final formatValue = parseStringLike(
      map['format'],
      context: 'logging.format',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final LoggingFormatConfig format;
    if (formatValue == null || formatValue.isEmpty) {
      format = LoggingFormatConfig('pretty', contextual.PrettyLogFormatter());
    } else {
      final token = formatValue.toLowerCase();
      format = switch (token) {
        'pretty' =>
          LoggingFormatConfig('pretty', contextual.PrettyLogFormatter()),
        'raw' => LoggingFormatConfig('raw', contextual.RawLogFormatter()),
        'null' => LoggingFormatConfig('null', contextual.JsonLogFormatter()),
        'json' => LoggingFormatConfig('json', contextual.JsonLogFormatter()),
        'plain' =>
          LoggingFormatConfig('plain', contextual.PlainTextLogFormatter()),
        _ => LoggingFormatConfig('plain', contextual.PlainTextLogFormatter()),
      };
    }

    final channels = <String, LoggingChannelConfig>{};
    final rawChannels = map['channels'];
    if (rawChannels != null) {
      final channelDefs = parseNestedMap(
        rawChannels,
        context: 'logging.channels',
        throwOnInvalid: true,
        allowNullEntries: false,
      );
      channelDefs.forEach((name, channelMap) {
        channels[name] = LoggingChannelConfig.fromMap(
          name,
          Map<String, dynamic>.from(channelMap),
          context: 'logging.channels.$name',
        );
      });
    }

    return LoggingConfig(
      enabled: enabled,
      errorsOnly: errorsOnly,
      level: level,
      extraFields: extraFields,
      requestHeaders: headerNames,
      includeStackTraces: includeStackTraces,
      format: format,
      defaultChannel: defaultChannel,
      channels: channels,
    );
  }

  @override
  Map<String, dynamic> toMap(LoggingConfig value) {
    return {
      'default': value.defaultChannel,
      'channels': value.channels.map(
        (key, channel) => MapEntry(key, channel.toMap()),
      ),
      'enabled': value.enabled,
      'level': value.level.name,
      'errors_only': value.errorsOnly,
      'extra_fields': value.extraFields,
      'include_stack_traces': value.includeStackTraces,
      'format': value.format.token,
      'request_headers': value.requestHeaders,
    };
  }
}
