import 'dart:async';

/// A value source that can resolve a typed value from the current runtime.
///
/// Sources are intentionally resolved outside provider implementations. This
/// keeps environment variables, platform bindings, and secret stores at the
/// application boundary instead of spreading string lookups through the
/// framework.
abstract interface class TypedValueSource<T> {
  /// Resolves a value using the supplied [runtime] context.
  FutureOr<T> resolve(RuntimeContext runtime);
}

/// Host services available while assembling application configuration.
///
/// Application configuration remains portable data. Host-specific resources
/// such as Cloudflare bindings or IO services belong in [bindings] and are
/// resolved by typed providers separately.
class RuntimeContext {
  /// Creates a runtime context from optional host services and values.
  RuntimeContext({
    RuntimeEnvironment? environment,
    RuntimeSecrets? secrets,
    Map<Type, Object>? bindings,
  }) : environment = environment ?? RuntimeEnvironment.empty(),
       secrets = secrets ?? RuntimeSecrets.empty(),
       bindings = Map<Type, Object>.unmodifiable(bindings ?? const {});

  /// Deployment environment values available during configuration.
  final RuntimeEnvironment environment;

  /// Secret values available during configuration.
  final RuntimeSecrets secrets;

  /// Host services keyed by their runtime type.
  final Map<Type, Object> bindings;

  /// Returns the required host binding of type [T].
  T binding<T extends Object>() {
    final value = bindings[T];
    if (value is T) return value;
    throw StateError('Runtime binding $T is not available');
  }

  /// Returns the host binding of type [T], or `null` when it is unavailable.
  T? maybeBinding<T extends Object>() {
    final value = bindings[T];
    return value is T ? value : null;
  }
}

/// Typed access to deployment environment values.
class RuntimeEnvironment {
  /// Creates an environment from [values].
  RuntimeEnvironment(Map<String, String> values)
    : values = Map<String, String>.unmodifiable(values);

  /// Creates an empty environment.
  RuntimeEnvironment.empty() : values = const <String, String>{};

  /// The immutable environment values keyed by variable name.
  final Map<String, String> values;

  /// Returns the value for [name], or `null` when it is not set.
  String? string(String name) => values[name];

  /// Returns the non-empty value for [name].
  ///
  /// Throws a [StateError] when the value is missing or blank.
  String requiredString(String name) {
    final value = string(name);
    if (value == null || value.trim().isEmpty) {
      throw StateError('Environment value "$name" is required');
    }
    return value;
  }

  /// Parses an integer value for [name].
  int? integer(String name) {
    final value = string(name);
    return value == null ? null : int.tryParse(value.trim());
  }

  /// Returns the integer value for [name].
  ///
  /// Throws a [StateError] when the value is missing or invalid.
  int requiredInteger(String name) {
    final value = integer(name);
    if (value == null) {
      throw StateError('Environment value "$name" must be an integer');
    }
    return value;
  }

  /// Parses a common textual boolean value for [name].
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
  /// Creates a secret store from [values].
  RuntimeSecrets(Map<String, String> values)
    : values = Map<String, String>.unmodifiable(values);

  /// Creates an empty secret store.
  RuntimeSecrets.empty() : values = const <String, String>{};

  /// The immutable secret values keyed by name.
  final Map<String, String> values;

  /// Returns the secret for [name], or `null` when it is not set.
  String? string(String name) => values[name];

  /// Returns the non-empty secret for [name].
  ///
  /// Throws a [StateError] when the secret is missing or blank.
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
  /// Creates an issue for [configurationType] at [path].
  const ConfigValidationIssue({
    required this.configurationType,
    required this.path,
    required this.message,
  });

  /// The configuration type that reported the issue.
  final Type configurationType;

  /// The dotted path to the invalid value.
  final String path;

  /// The human-readable validation message.
  final String message;

  @override
  String toString() {
    final location = path.isEmpty ? configurationType.toString() : path;
    return '$location: $message';
  }
}

/// Raised when one or more typed configurations are invalid.
class ConfigValidationException implements Exception {
  /// Creates an exception containing the collected [issues].
  ConfigValidationException(Iterable<ConfigValidationIssue> issues)
    : issues = List<ConfigValidationIssue>.unmodifiable(issues);

  /// The validation issues collected during configuration assembly.
  final List<ConfigValidationIssue> issues;

  @override
  String toString() {
    final lines = issues.map((issue) => ' - $issue').join('\n');
    return 'Invalid application configuration:\n$lines';
  }
}

/// Context supplied to typed provider validation.
class ConfigValidationContext {
  /// Creates a validation context for [configurationType].
  ConfigValidationContext({
    required this.configurations,
    required this.runtime,
    required Type configurationType,
    List<ConfigValidationIssue>? issues,
  }) : _configurationType = configurationType,
       _issues = issues ?? <ConfigValidationIssue>[];

  /// The complete configuration store being validated.
  final ConfigStore configurations;

  /// The runtime values available to validation.
  final RuntimeContext runtime;
  final Type _configurationType;
  final List<ConfigValidationIssue> _issues;

  /// Adds a validation [message] at [path].
  void error(String path, String message) {
    _issues.add(
      ConfigValidationIssue(
        configurationType: _configurationType,
        path: path,
        message: message,
      ),
    );
  }

  /// Adds an issue when [condition] is false.
  void require(bool condition, String path, String message) {
    if (!condition) error(path, message);
  }

  /// The issues collected so far.
  List<ConfigValidationIssue> get issues =>
      List<ConfigValidationIssue>.unmodifiable(_issues);
}

/// Immutable typed configuration lookup store.
class ConfigStore {
  ConfigStore._(Map<Type, Object> values)
    : _values = Map<Type, Object>.unmodifiable(values);

  /// Creates an empty configuration store.
  factory ConfigStore.empty() => ConfigStore._(<Type, Object>{});

  /// Builds and validates a store from typed configuration [providers].
  ///
  /// Throws a [StateError] when a type is registered more than once and a
  /// [ConfigValidationException] when validation reports one or more issues.
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
          'Configuration type $type was registered more than once',
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

  /// Returns the registered configuration of type [T].
  ///
  /// Throws a [StateError] when no configuration of type [T] is registered.
  T get<T extends Object>() {
    final value = _values[T];
    if (value is T) return value;
    throw StateError('Configuration $T is not registered');
  }

  /// Returns the configuration registered under [type].
  ///
  /// Throws a [StateError] when [type] is not registered.
  Object getUntyped(Type type) {
    final value = _values[type];
    if (value != null) return value;
    throw StateError('Configuration $type is not registered');
  }

  /// Returns the configuration of type [T], or `null` when it is unavailable.
  T? maybe<T extends Object>() {
    final value = _values[T];
    return value is T ? value : null;
  }

  /// Whether a configuration of type [T] is registered.
  bool contains<T extends Object>() => _values.containsKey(T);

  /// The registered configuration objects.
  Iterable<Object> get values => _values.values;
}

/// Public provider contract for typed application configuration.
abstract interface class TypedConfigurationProvider {
  /// The type used as this provider's configuration key.
  Type get configurationType;

  /// The typed configuration object supplied by this provider.
  Object get configurationObject;

  /// Validates this provider's configuration against [context].
  void validateConfiguration(ConfigValidationContext context);
}
