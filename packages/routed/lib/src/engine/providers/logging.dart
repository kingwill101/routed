import 'dart:async';

import 'dart:convert';

import 'package:routed/src/container/container.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/logging/context.dart';
import 'package:routed/src/logging/logger.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/router/types.dart';

/// Registers logging defaults and related middleware identifiers.
class LoggingServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  bool _enabled = true;
  bool _logSuccess = true;
  _LogLevel _level = _LogLevel.info;
  Map<String, dynamic> _extraFields = const {};
  List<String> _headerNames = const [];
  bool _includeStackTraces = false;

  static bool includeStackTraces = false;

  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    values: {
      'http': {
        'middleware_sources': {
          'routed.logging': {
            'global': ['routed.logging.http'],
          },
        },
      },
    },
    docs: <ConfigDocEntry>[
      ConfigDocEntry(
        path: 'http.features.logging.enabled',
        type: 'bool',
        description: 'Toggles HTTP logging middleware.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: 'http.features.logging.level',
        type: 'string',
        description: 'Log verbosity for HTTP middleware.',
        options: ['debug', 'info'],
        defaultValue: 'info',
      ),
      ConfigDocEntry(
        path: 'http.features.logging.errors_only',
        type: 'bool',
        description: 'Only log requests that throw an error.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'http.features.logging.request_headers',
        type: 'list<string>',
        description:
            'Request headers mirrored into the log payload (e.g. correlation IDs).',
        defaultValue: <String>[],
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
        options: ['json', 'text'],
        defaultValue: 'json',
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
    final registry = container.get<MiddlewareRegistry>();
    registry.register('routed.logging.http', (_) => _loggingMiddleware);

    if (container.has<Config>()) {
      _applyConfig(container.get<Config>());
    }
  }

  @override
  Future<void> boot(Container container) async {
    if (!container.has<Config>()) {
      return;
    }

    _applyConfig(container.get<Config>());
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    _applyConfig(config);
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
      'level': error != null
          ? 'ERROR'
          : _level == _LogLevel.debug
          ? 'DEBUG'
          : 'INFO',
      'message': message,
      ...payload,
    };

    if (error != null) {
      logEntry['error'] = error.toString();
    }
    if (_includeStackTraces && stackTrace != null) {
      logEntry['stack_trace'] = stackTrace.toString();
    }

    final formatted = RoutedLogger.globalFormat == RoutedLogFormat.json
        ? jsonEncode(logEntry)
        : message;

    if (error != null) {
      logger.error(formatted);
      if (RoutedLogger.globalFormat != RoutedLogFormat.json &&
          _includeStackTraces &&
          stackTrace != null) {
        logger.error(stackTrace.toString());
      }
      return;
    }

    switch (_level) {
      case _LogLevel.info:
        logger.info(formatted);
        break;
      case _LogLevel.debug:
        logger.debug(formatted);
        break;
    }
  }

  void _applyConfig(Config config) {
    final resolved = _resolveLoggingConfig(config);
    _enabled = resolved.enabled;
    _logSuccess = resolved.logSuccess;
    _level = resolved.level;
    _extraFields = resolved.extraFields;
    _headerNames = resolved.headerNames;
    _includeStackTraces = resolved.includeStackTraces;
    includeStackTraces = resolved.includeStackTraces;
    RoutedLogger.setGlobalFormat(resolved.format);
  }

  _LoggingConfig _resolveLoggingConfig(Config config) {
    final merged = mergeConfigCandidates([
      ConfigMapCandidate.fromConfig(config, 'http.features.logging'),
      ConfigMapCandidate.fromConfig(config, 'logging'),
    ]);

    final enabled =
        parseBoolLike(
          merged['enabled'],
          context: 'logging.enabled',
          stringMappings: const {'true': true, 'false': false},
          throwOnInvalid: false,
        ) ??
        true;
    final errorsOnly =
        parseBoolLike(
          merged['errors_only'],
          context: 'logging.errors_only',
          stringMappings: const {'true': true, 'false': false},
          throwOnInvalid: false,
        ) ??
        false;

    final levelToken = parseStringLike(
      merged['level'],
      context: 'logging.level',
      coerceNonString: true,
      throwOnInvalid: false,
    );
    final level = _parseLevel(levelToken);

    final extraFields =
        merged.containsKey('extra_fields') && merged['extra_fields'] != null
        ? stringKeyedMap(
            merged['extra_fields']! as Object,
            'logging.extra_fields',
          )
        : const <String, dynamic>{};

    final headerNames =
        parseStringList(
          merged['request_headers'],
          context: 'logging.request_headers',
          allowEmptyResult: true,
          coerceNonStringEntries: false,
        ) ??
        const [];

    final includeStackTraces =
        parseBoolLike(
          merged['include_stack_traces'],
          context: 'logging.include_stack_traces',
          stringMappings: const {'true': true, 'false': false},
          throwOnInvalid: false,
        ) ??
        false;

    final formatToken =
        parseStringLike(
          merged['format'],
          context: 'logging.format',
          throwOnInvalid: false,
        )?.toLowerCase().trim() ??
        'json';
    final format = formatToken == 'text'
        ? RoutedLogFormat.text
        : RoutedLogFormat.json;

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

  _LogLevel _parseLevel(String? raw) {
    if (raw == null) {
      return _LogLevel.info;
    }
    switch (raw.trim().toLowerCase()) {
      case 'debug':
        return _LogLevel.debug;
      case 'info':
        return _LogLevel.info;
      default:
        throw ProviderConfigException(
          'logging.level must be "info" or "debug"',
        );
    }
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

enum _LogLevel { info, debug }

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
  final _LogLevel level;
  final Map<String, dynamic> extraFields;
  final List<String> headerNames;
  final bool includeStackTraces;
  final RoutedLogFormat format;
}
