import 'package:contextual/contextual.dart' as contextual;

typedef LoggerFactory =
    contextual.Logger Function(Map<String, Object?> context);

class RoutedLogger {
  RoutedLogger._();

  static LoggerFactory _factory = _defaultFactory;
  static LoggerFactory _systemFactory = _defaultFactory;
  static RoutedLogFormat _format = RoutedLogFormat.json;
  static bool _hasCustomFactory = false;

  static contextual.Logger _defaultFactory(Map<String, Object?> context) {
    final initialContext = <String, dynamic>{};
    for (final entry in context.entries) {
      initialContext[entry.key] = entry.value;
    }

    final formatter = _format == RoutedLogFormat.json
        ? contextual.JsonLogFormatter()
        : contextual.PrettyLogFormatter();

    return contextual.Logger(formatter: formatter)
      ..addChannel('console', contextual.ConsoleLogDriver())
      ..withContext(initialContext);
  }

  static contextual.Logger create(Map<String, Object?> context) =>
      _factory(Map.unmodifiable(context));

  static void configureFactory(LoggerFactory factory) {
    _factory = factory;
    _hasCustomFactory = true;
  }

  static void configureSystemFactory(LoggerFactory factory) {
    _systemFactory = factory;
    if (!_hasCustomFactory) {
      _factory = factory;
    }
  }

  static void reset() {
    _factory = _defaultFactory;
    _systemFactory = _defaultFactory;
    _hasCustomFactory = false;
  }

  static void setGlobalFormat(RoutedLogFormat format) {
    _format = format;
    // Refresh the system factory to ensure default output respects new format.
    configureSystemFactory(_systemFactory);
  }

  static RoutedLogFormat get globalFormat => _format;
}

enum RoutedLogFormat { json, text }
