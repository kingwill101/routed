import 'package:contextual/contextual.dart' as contextual;

/// Creates a logger initialized with [context].
typedef LoggerFactory =
    contextual.Logger Function(Map<String, Object?> context);

/// Creates loggers using the configured Routed logging factory.
class RoutedLogger {
  RoutedLogger._();

  /// Context key used by configured factories to select a logging channel.
  static const String channelOverrideKey = '__routed.log_channel';

  static LoggerFactory _factory = _defaultFactory;
  static LoggerFactory _systemFactory = _defaultFactory;
  static contextual.LogMessageFormatter _format =
      contextual.PlainTextLogFormatter();
  static bool _hasCustomFactory = false;

  static contextual.Logger _defaultFactory(Map<String, Object?> context) {
    final initialContext = <String, dynamic>{};
    for (final entry in context.entries) {
      initialContext[entry.key] = entry.value;
    }

    return contextual.Logger(formatter: _format)
      ..addChannel('console', contextual.ConsoleLogDriver())
      ..withContext(initialContext);
  }

  /// Creates a logger with [context].
  static contextual.Logger create(Map<String, Object?> context) =>
      _factory(Map.unmodifiable(context));

  /// Creates a logger with [channel] selected as a channel override.
  static contextual.Logger createForChannel(
    String channel,
    Map<String, Object?> context,
  ) {
    final merged = <String, Object?>{...context, channelOverrideKey: channel};
    return create(merged);
  }

  /// Sets the application logger [factory].
  static void configureFactory(LoggerFactory factory) {
    _factory = factory;
    _hasCustomFactory = true;
  }

  /// Sets the system logger [factory] used when no application factory exists.
  static void configureSystemFactory(LoggerFactory factory) {
    _systemFactory = factory;
    if (!_hasCustomFactory) {
      _factory = factory;
    }
  }

  /// Restores the default logger factories and formatter.
  static void reset() {
    _factory = _defaultFactory;
    _systemFactory = _defaultFactory;
    _hasCustomFactory = false;
  }

  /// Sets the formatter used by loggers created by the default factory.
  static void setGlobalFormat(contextual.LogMessageFormatter format) {
    _format = format;
    // Refresh the system factory to ensure default output respects new format.
    configureSystemFactory(_systemFactory);
  }

  /// The formatter used by the default logger factory.
  static contextual.LogMessageFormatter get globalFormat => _format;
}
