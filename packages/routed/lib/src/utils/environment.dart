import 'package:dotenv/dotenv.dart';

final env = Environment.fromSystem();
var _dotenv = DotEnv(includePlatformEnvironment: true, quiet: true);

/// A wrapper around environment variables that allows for safe access and
/// in-memory modification.  Note that changes made through this wrapper
/// do NOT affect the actual system environment variables; they are only
/// reflected within this class's internal state.
class Environment {
  /// Internal storage for the environment variables.
  final Map<String, String> _variables = {};

  /// Private constructor to enforce singleton or factory pattern, if desired.
  Environment._();

  /// Initializes the Environment with the current system environment variables.
  factory Environment.fromSystem() {
    final instance = Environment._();
    _dotenv.load();
    return instance;
  }

  /// Initializes an Environment instance with pre-defined variables.  Useful
  /// for testing and isolated configurations.
  factory Environment.fromMap(Map<String, String> initialVariables) {
    final instance = Environment._();
    instance._variables.addAll(initialVariables);
    return instance;
  }

  operator []=(String name, String value) {
    _variables[name] = value;
  }

  operator [](String name) {
    return get(name);
  }

  /// Retrieves the value of the environment variable with the given [name].
  ///
  /// Returns `null` if the variable is not found.
  String? get(String name) {
    return _variables[name] ?? _dotenv[name];
  }

  /// Sets the environment variable [name] to the given [value].
  ///
  /// Note: This only modifies the in-memory copy of the environment variables.
  /// It does *not* affect the system environment.
  void set(String name, String value) {
    _variables[name] = value;
  }

  /// Removes the environment variable with the given [name].
  ///
  /// Note: This only modifies the in-memory copy of the environment variables.
  /// It does *not* affect the system environment.
  void remove(String name) {
    _variables.remove(name);
  }

  /// Checks if the environment variable with the given [name] exists.
  bool containsKey(String name) {
    return _variables.containsKey(name);
  }

  /// Returns a copy of the internal map of environment variables.  Modifying
  /// the returned map does *not* affect the internal state of the Environment.
  Map<String, String> toMap() {
    return Map<String, String>.from(_variables); // Return a copy
  }

  /// Returns a string representation of the environment variables.
  @override
  String toString() {
    return 'Environment: $_variables';
  }
}
