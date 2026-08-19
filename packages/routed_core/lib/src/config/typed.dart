import 'dart:async';

/// A value source that can resolve a typed value from the current runtime.
///
/// Sources are intentionally resolved outside provider implementations. This
/// keeps environment variables, platform bindings, and secret stores at the
/// application boundary instead of spreading string lookups through the
/// framework.
abstract interface class TypedValueSource<T> {
  FutureOr<T> resolve(RuntimeContext runtime);
}

/// Host services available while assembling application configuration.
///
/// Application configuration remains portable data. Host-specific resources
/// such as Cloudflare bindings or IO services belong in [bindings] and are
/// resolved by typed providers separately.
class RuntimeContext {
  RuntimeContext({
    RuntimeEnvironment? environment,
    RuntimeSecrets? secrets,
    Map<Type, Object>? bindings,
  }) : environment = environment ?? RuntimeEnvironment.empty(),
       secrets = secrets ?? RuntimeSecrets.empty(),
       bindings = Map<Type, Object>.unmodifiable(bindings ?? const {});

  final RuntimeEnvironment environment;
  final RuntimeSecrets secrets;
  final Map<Type, Object> bindings;

  T binding<T extends Object>() {
    final value = bindings[T];
    if (value is T) return value;
    throw StateError('Runtime binding ${T.toString()} is not available');
  }

  T? maybeBinding<T extends Object>() {
    final value = bindings[T];
    return value is T ? value : null;
  }
}

/// Typed access to deployment environment values.
class RuntimeEnvironment {
  RuntimeEnvironment(Map<String, String> values)
    : values = Map<String, String>.unmodifiable(values);

  RuntimeEnvironment.empty() : values = const <String, String>{};

  final Map<String, String> values;

  String? string(String name) => values[name];

  String requiredString(String name) {
    final value = string(name);
    if (value == null || value.trim().isEmpty) {
      throw StateError('Environment value "$name" is required');
    }
    return value;
  }

  int? integer(String name) {
    final value = string(name);
    return value == null ? null : int.tryParse(value.trim());
  }

  int requiredInteger(String name) {
    final value = integer(name);
    if (value == null) {
      throw StateError('Environment value "$name" must be an integer');
    }
    return value;
  }

  bool? boolean(String name) {
    final value = string(name)?.trim().toLowerCase();
    if (value == null) return null;
    if (value == '1' || value == 'true' || value == 'yes' || value == 'on') {
      return true;
    }
    if (value == '0' || value == 'false' || value == 'no' || value == 'off') {
      return false;
    }
    return null;
  }
}

/// Typed access to deployment secrets.
///
/// The values are never included in [toString], validation summaries, or
/// generic error output.
class RuntimeSecrets {
  RuntimeSecrets(Map<String, String> values)
    : values = Map<String, String>.unmodifiable(values);

  RuntimeSecrets.empty() : values = const <String, String>{};

  final Map<String, String> values;

  String? string(String name) => values[name];

  String requiredString(String name) {
    final value = string(name);
    if (value == null || value.trim().isEmpty) {
      throw StateError('Secret "$name" is required');
    }
    return value;
  }
}

/// A single eager configuration validation failure.
class ConfigValidationIssue {
  const ConfigValidationIssue({
    required this.configurationType,
    required this.path,
    required this.message,
  });

  final Type configurationType;
  final String path;
  final String message;

  @override
  String toString() {
    final location = path.isEmpty ? configurationType.toString() : path;
    return '$location: $message';
  }
}

/// Raised when one or more typed configurations are invalid.
class ConfigValidationException implements Exception {
  ConfigValidationException(Iterable<ConfigValidationIssue> issues)
    : issues = List<ConfigValidationIssue>.unmodifiable(issues);

  final List<ConfigValidationIssue> issues;

  @override
  String toString() {
    final lines = issues.map((issue) => ' - $issue').join('\n');
    return 'Invalid application configuration:\n$lines';
  }
}

/// Context supplied to typed provider validation.
class ConfigValidationContext {
  ConfigValidationContext({
    required this.configurations,
    required this.runtime,
    required Type configurationType,
    List<ConfigValidationIssue>? issues,
  }) : _configurationType = configurationType,
       _issues = issues ?? <ConfigValidationIssue>[];

  final ConfigStore configurations;
  final RuntimeContext runtime;
  final Type _configurationType;
  final List<ConfigValidationIssue> _issues;

  void error(String path, String message) {
    _issues.add(
      ConfigValidationIssue(
        configurationType: _configurationType,
        path: path,
        message: message,
      ),
    );
  }

  void require(bool condition, String path, String message) {
    if (!condition) error(path, message);
  }

  List<ConfigValidationIssue> get issues =>
      List<ConfigValidationIssue>.unmodifiable(_issues);
}

/// Immutable typed configuration lookup store.
class ConfigStore {
  ConfigStore._(Map<Type, Object> values)
    : _values = Map<Type, Object>.unmodifiable(values);

  factory ConfigStore.empty() => ConfigStore._(<Type, Object>{});

  factory ConfigStore.fromProviders(
    Iterable<TypedConfigurationProvider> providers, {
    RuntimeContext? runtime,
  }) {
    final resolvedRuntime = runtime ?? RuntimeContext();
    final values = <Type, Object>{};
    final entries = <TypedConfigurationProvider>[];
    for (final provider in providers) {
      final type = provider.configurationType;
      if (values.containsKey(type)) {
        throw StateError(
          'Configuration type ${type.toString()} was registered more than once',
        );
      }
      values[type] = provider.configurationObject;
      entries.add(provider);
    }

    final store = ConfigStore._(values);
    final issues = <ConfigValidationIssue>[];
    for (final provider in entries) {
      provider.validateConfiguration(
        ConfigValidationContext(
          configurations: store,
          runtime: resolvedRuntime,
          configurationType: provider.configurationType,
          issues: issues,
        ),
      );
    }
    if (issues.isNotEmpty) {
      throw ConfigValidationException(issues);
    }
    return store;
  }

  final Map<Type, Object> _values;

  T get<T extends Object>() {
    final value = _values[T];
    if (value is T) return value;
    throw StateError('Configuration ${T.toString()} is not registered');
  }

  Object getUntyped(Type type) {
    final value = _values[type];
    if (value != null) return value;
    throw StateError('Configuration ${type.toString()} is not registered');
  }

  T? maybe<T extends Object>() {
    final value = _values[T];
    return value is T ? value : null;
  }

  bool contains<T extends Object>() => _values.containsKey(T);

  Iterable<Object> get values => _values.values;
}

/// Public provider contract for typed application configuration.
abstract interface class TypedConfigurationProvider {
  Type get configurationType;

  Object get configurationObject;

  void validateConfiguration(ConfigValidationContext context);
}
