import 'dart:async';

import 'package:routed_core/src/support/named_registry.dart';

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
