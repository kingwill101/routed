import 'package:contextual/contextual.dart' as contextual;

typedef LoggerFactory =
    contextual.Logger Function(Map<String, Object?> context);

class RoutedLogger {
  RoutedLogger._();

  static LoggerFactory _factory = _defaultFactory;
  static RoutedLogFormat _format = RoutedLogFormat.json;

  static contextual.Logger _defaultFactory(Map<String, Object?> context) {
    final initialContext = <String, dynamic>{};
    for (final entry in context.entries) {
      initialContext[entry.key] = entry.value;
    }

    return contextual.Logger(defaultChannelEnabled: true)
      ..withContext(initialContext);
  }

  static contextual.Logger create(Map<String, Object?> context) =>
      _factory(Map.unmodifiable(context));

  static void configureFactory(LoggerFactory factory) {
    _factory = factory;
  }

  static void reset() {
    _factory = _defaultFactory;
  }

  static void setGlobalFormat(RoutedLogFormat format) {
    _format = format;
  }

  static RoutedLogFormat get globalFormat => _format;
}

enum RoutedLogFormat { json, text }
