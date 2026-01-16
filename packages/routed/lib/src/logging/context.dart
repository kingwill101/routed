import 'dart:async';

import 'package:contextual/contextual.dart' as contextual;
import 'package:routed/src/context/context.dart';
import 'package:routed/src/engine/engine.dart';

import 'logger.dart';

class _LoggerScope {
  _LoggerScope(this.logger, this.context);

  final contextual.Logger logger;
  final Map<String, Object?> context;
}

class LoggingContext {
  LoggingContext._();

  static const _scopeKey = #routed_logger_scope;
  static const _loggerKey = '__routed.logger';
  static const _loggerContextKey = '__routed.logger_context';

  static FutureOr<T> run<T>(
    Engine engine,
    EngineContext context,
    FutureOr<T> Function(contextual.Logger logger) body,
  ) {
    final baseContext = <String, Object?>{
      'request_id': context.request.id,
      'method': context.request.method,
      'path': context.request.uri.path,
    };

    final logger = RoutedLogger.create(baseContext);
    context
      ..set(_loggerKey, logger)
      ..set(_loggerContextKey, baseContext);
    return body(logger);
  }

  static FutureOr<T> withValues<T>(
    Map<String, Object?> values,
    FutureOr<T> Function(contextual.Logger logger) body,
  ) {
    final parent = Zone.current[_scopeKey] as _LoggerScope?;
    final merged = <String, Object?>{}
      ..addAll(parent?.context ?? const {})
      ..addAll(values);
    final scope = _LoggerScope(RoutedLogger.create(merged), merged);
    return _runWithScope(scope, () => body(scope.logger));
  }

  static contextual.Logger currentLogger([EngineContext? context]) {
    if (context != null) {
      final stored = context.get<contextual.Logger>(_loggerKey);
      if (stored != null) {
        return stored;
      }
    }
    final scope = Zone.current[_scopeKey] as _LoggerScope?;
    return scope?.logger ?? RoutedLogger.create({'context': 'routed'});
  }

  static Map<String, Object?> currentValues([EngineContext? context]) {
    if (context != null) {
      final stored = context.get<Map<String, Object?>>(_loggerContextKey);
      if (stored != null) {
        return stored;
      }
    }
    final scope = Zone.current[_scopeKey] as _LoggerScope?;
    return scope?.context ?? const {};
  }

  static FutureOr<T> _runWithScope<T>(
    _LoggerScope scope,
    FutureOr<T> Function() body,
  ) {
    return runZoned(
      body,
      zoneValues: {_scopeKey: scope},
      zoneSpecification: const ZoneSpecification(),
    );
  }
}
