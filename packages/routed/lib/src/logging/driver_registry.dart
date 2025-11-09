import 'package:contextual/contextual.dart' as contextual;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;

typedef LogDriverBuilder =
    contextual.LogDriver Function(LogDriverBuilderContext context);

class LogDriverBuilderContext {
  LogDriverBuilderContext({
    required this.name,
    required this.configPath,
    required this.options,
    required this.config,
    required this.container,
    required this.resolveChannel,
  });

  final String name;
  final String configPath;
  final Map<String, Object?> options;
  final Config config;
  final Container container;
  final contextual.LogDriver Function(String channelName) resolveChannel;
}

class LogDriverRegistry {
  final Map<String, LogDriverBuilder> _builders = {};

  void register(
    String name,
    LogDriverBuilder builder, {
    bool override = false,
  }) {
    final key = _normalize(name);
    if (!override && _builders.containsKey(key)) {
      return;
    }
    _builders[key] = builder;
  }

  void registerIfAbsent(String name, LogDriverBuilder builder) {
    register(name, builder, override: false);
  }

  bool contains(String name) => _builders.containsKey(_normalize(name));

  LogDriverBuilder? builderFor(String name) => _builders[_normalize(name)];

  static String _normalize(String name) => name.trim().toLowerCase();
}
