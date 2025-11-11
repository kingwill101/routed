import 'dart:async';
import 'dart:convert';

import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/support/named_registry.dart';

typedef HealthCheck = FutureOr<HealthCheckResult> Function();

class HealthCheckResult {
  HealthCheckResult.ok([this.details = const <String, Object?>{}]) : ok = true;

  HealthCheckResult.failure([this.details = const <String, Object?>{}])
    : ok = false;

  final bool ok;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => {
    'ok': ok,
    if (details.isNotEmpty) ...details,
  };
}

class HealthService {
  HealthService({required this.engine});

  final Engine engine;

  final Map<String, HealthCheck> _readinessChecks = {};
  final Map<String, HealthCheck> _livenessChecks = {};

  void registerReadinessCheck(String name, HealthCheck check) {
    _readinessChecks[name] = check;
  }

  void registerLivenessCheck(String name, HealthCheck check) {
    _livenessChecks[name] = check;
  }

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

  Future<HealthResponse> liveness() async {
    final checks = Map<String, HealthCheck>.from(_livenessChecks);
    if (!checks.containsKey('engine.alive')) {
      checks['engine.alive'] = () => HealthCheckResult.ok();
    }
    return _runChecks(checks);
  }

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
      } catch (error) {
        ok = false;
        results[entry.key] = HealthCheckResult.failure({
          'error': error.toString(),
        });
      }
    }
    return HealthResponse(ok: ok, checks: results);
  }
}

class HealthResponse {
  const HealthResponse({required this.ok, required this.checks});

  final bool ok;
  final Map<String, HealthCheckResult> checks;
}

class HealthEndpointRegistry extends NamedRegistry<bool> {
  void setPaths(Iterable<String> paths) {
    clearEntries();
    for (final path in paths) {
      registerEntry(path, true);
    }
  }

  bool allows(String path) => containsEntry(path);

  @override
  String normalizeName(String name) => name;
}
