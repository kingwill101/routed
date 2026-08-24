import 'dart:async';
import 'dart:convert';

import 'package:routed_core/routed_core.dart';

/// A synchronous or asynchronous health check callback.
typedef HealthCheck = FutureOr<HealthCheckResult> Function();

/// Describes the result of one health check.
class HealthCheckResult {
  /// Creates a successful result with optional [details].
  HealthCheckResult.ok([this.details = const <String, Object?>{}]) : ok = true;

  /// Creates a failed result with optional [details].
  HealthCheckResult.failure([this.details = const <String, Object?>{}])
    : ok = false;

  /// Whether the check passed.
  final bool ok;

  /// Additional structured information about the check.
  final Map<String, Object?> details;

  /// Converts the result to a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'ok': ok,
    if (details.isNotEmpty) ...details,
  };
}

/// Runs liveness and readiness checks for an [Engine].
class HealthService {
  /// Creates a health service backed by [engine].
  HealthService({required this.engine});

  /// The engine whose readiness state is included by default.
  final Engine engine;

  final Map<String, HealthCheck> _readinessChecks = {};
  final Map<String, HealthCheck> _livenessChecks = {};

  /// Registers or replaces a named readiness [check].
  void registerReadinessCheck(String name, HealthCheck check) {
    _readinessChecks[name] = check;
  }

  /// Registers or replaces a named liveness [check].
  void registerLivenessCheck(String name, HealthCheck check) {
    _livenessChecks[name] = check;
  }

  /// Runs readiness checks and returns their combined result.
  Future<HealthResponse> readiness() async {
    final checks = Map<String, HealthCheck>.from(_readinessChecks);
    if (!checks.containsKey('engine.ready')) {
      checks['engine.ready'] = () {
        final ready = engine.isReady;
        return ready
            ? HealthCheckResult.ok({'ready': true})
            : HealthCheckResult.failure({'ready': false});
      };
    }
    return _runChecks(checks);
  }

  /// Runs liveness checks and returns their combined result.
  Future<HealthResponse> liveness() async {
    final checks = Map<String, HealthCheck>.from(_livenessChecks);
    if (!checks.containsKey('engine.alive')) {
      checks['engine.alive'] = HealthCheckResult.ok;
    }
    return _runChecks(checks);
  }

  /// Encodes [response] as indented JSON.
  String toJson(HealthResponse response) {
    final payload = <String, Object?>{
      'ok': response.ok,
      'checks': response.checks.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<HealthResponse> _runChecks(Map<String, HealthCheck> checks) async {
    final results = <String, HealthCheckResult>{};
    var ok = true;
    for (final entry in checks.entries) {
      try {
        final result = await entry.value();
        results[entry.key] = result;
        ok = ok && result.ok;
      } on Object catch (error) {
        ok = false;
        results[entry.key] = HealthCheckResult.failure({
          'error': error.toString(),
        });
      }
    }
    return HealthResponse(ok: ok, checks: results);
  }
}

/// The combined result of a health endpoint request.
class HealthResponse {
  /// Creates a response from the overall status and individual [checks].
  const HealthResponse({required this.ok, required this.checks});

  /// Whether every check passed.
  final bool ok;

  /// Results keyed by the registered check name.
  final Map<String, HealthCheckResult> checks;
}

/// Tracks paths exposed by the health service.
class HealthEndpointRegistry extends NamedRegistry<bool> {
  /// Replaces the registered health [paths].
  void setPaths(Iterable<String> paths) {
    clearEntries();
    for (final path in paths) {
      registerEntry(path, true);
    }
  }

  /// Whether [path] is registered as a health endpoint.
  bool allows(String path) => containsEntry(path);

  @override
  String normalizeName(String name) => name;
}
