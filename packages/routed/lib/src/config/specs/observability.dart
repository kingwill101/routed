import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

import '../spec.dart';

const List<double> _defaultBuckets = [
  0.01,
  0.05,
  0.1,
  0.25,
  0.5,
  1.0,
  2.0,
  5.0,
];

class ObservabilityTracingConfig {
  const ObservabilityTracingConfig({
    required this.enabled,
    required this.serviceName,
    required this.exporter,
    required this.endpoint,
    required this.headers,
  });

  final bool enabled;
  final String serviceName;
  final String exporter;
  final Uri? endpoint;
  final Map<String, String> headers;
}

class ObservabilityMetricsConfig {
  const ObservabilityMetricsConfig({
    required this.enabled,
    required this.path,
    required this.buckets,
  });

  final bool enabled;
  final String path;
  final List<double> buckets;
}

class ObservabilityHealthConfig {
  const ObservabilityHealthConfig({
    required this.enabled,
    required this.readinessPath,
    required this.livenessPath,
  });

  final bool enabled;
  final String readinessPath;
  final String livenessPath;
}

class ObservabilityErrorsConfig {
  const ObservabilityErrorsConfig({required this.enabled});

  final bool enabled;
}

class ObservabilityConfig {
  const ObservabilityConfig({
    required this.enabled,
    required this.tracing,
    required this.metrics,
    required this.health,
    required this.errors,
  });

  final bool enabled;
  final ObservabilityTracingConfig tracing;
  final ObservabilityMetricsConfig metrics;
  final ObservabilityHealthConfig health;
  final ObservabilityErrorsConfig errors;
}

class ObservabilityConfigSpec extends ConfigSpec<ObservabilityConfig> {
  const ObservabilityConfigSpec();

  @override
  String get root => 'observability';

  @override
  Map<String, dynamic> defaults({ConfigSpecContext? context}) {
    return {
      'enabled': true,
      'tracing': {
        'enabled': false,
        'service_name': 'routed-service',
        'exporter': 'none',
        'endpoint': null,
        'headers': const <String, String>{},
      },
      'metrics': {
        'enabled': false,
        'path': '/metrics',
        'buckets': _defaultBuckets,
      },
      'health': {
        'enabled': true,
        'readiness_path': '/readyz',
        'liveness_path': '/livez',
      },
      'errors': {
        'enabled': false,
      },
    };
  }

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    final base = pathBase ?? root;
    String path(String segment) => base.isEmpty ? segment : '$base.$segment';

    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: path('enabled'),
        type: 'bool',
        description:
            'Master toggle that enables or disables all observability features.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: path('tracing.enabled'),
        type: 'bool',
        description: 'Enable OpenTelemetry tracing middleware.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: path('tracing.service_name'),
        type: 'string',
        description: 'Logical service.name attribute reported with every span.',
        defaultValue: 'routed-service',
        metadata: {
          configDocMetaInheritFromEnv: 'OBSERVABILITY_TRACING_SERVICE_NAME',
        },
      ),
      ConfigDocEntry(
        path: path('tracing.exporter'),
        type: 'string',
        description: 'Tracing exporter (none, console, otlp).',
        options: ['none', 'console', 'otlp'],
        defaultValue: 'none',
      ),
      ConfigDocEntry(
        path: path('tracing.endpoint'),
        type: 'string',
        description:
            'Collector endpoint used when exporter=otlp (e.g. https://otel/v1/traces).',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: path('tracing.headers'),
        type: 'map',
        description:
            'Optional headers forwarded to the OTLP collector (authorization, etc.).',
        defaultValue: const <String, String>{},
      ),
      ConfigDocEntry(
        path: path('metrics.enabled'),
        type: 'bool',
        description: 'Enable Prometheus-style metrics endpoint.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: path('metrics.path'),
        type: 'string',
        description: 'Path for metrics exposition.',
        defaultValue: '/metrics',
      ),
      ConfigDocEntry(
        path: path('metrics.buckets'),
        type: 'list<double>',
        description:
            'Latency histogram bucket upper bounds (seconds) for routed_request_duration_seconds.',
        defaultValue: _defaultBuckets,
      ),
      ConfigDocEntry(
        path: path('health.enabled'),
        type: 'bool',
        description: 'Enable health and readiness endpoints.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: path('health.readiness_path'),
        type: 'string',
        description: 'HTTP path exposed for readiness checks.',
        defaultValue: '/readyz',
      ),
      ConfigDocEntry(
        path: path('health.liveness_path'),
        type: 'string',
        description: 'HTTP path exposed for liveness checks.',
        defaultValue: '/livez',
      ),
      ConfigDocEntry(
        path: path('errors.enabled'),
        type: 'bool',
        description:
            'Enable error observer notifications (reserve for external error trackers).',
        defaultValue: false,
      ),
    ];
  }

  @override
  ObservabilityConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final enabled =
        parseBoolLike(
          map['enabled'],
          context: 'observability.enabled',
          throwOnInvalid: true,
        ) ??
        true;

    final tracingMap = map['tracing'] == null
        ? const <String, dynamic>{}
        : stringKeyedMap(
          map['tracing'] as Object,
          'observability.tracing',
        );
    final tracingEnabled =
        parseBoolLike(
          tracingMap['enabled'],
          context: 'observability.tracing.enabled',
          throwOnInvalid: true,
        ) ??
        false;
    final serviceNameRaw = tracingMap['service_name'];
    final serviceName =
        parseStringLike(
          serviceNameRaw,
          context: 'observability.tracing.service_name',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        'routed-service';
    final exporterRaw = tracingMap['exporter'];
    final exporter =
        (parseStringLike(
              exporterRaw,
              context: 'observability.tracing.exporter',
              allowEmpty: true,
              throwOnInvalid: true,
            ) ??
            'none')
            .toLowerCase();

    Uri? endpoint;
    final endpointRaw = tracingMap['endpoint'];
    if (endpointRaw != null) {
      final endpointValue = parseStringLike(
        endpointRaw,
        context: 'observability.tracing.endpoint',
        allowEmpty: true,
        throwOnInvalid: true,
      );
      if (endpointValue != null && endpointValue.isNotEmpty) {
        endpoint = Uri.tryParse(endpointValue);
      }
    }

    final headers =
        tracingMap['headers'] == null
            ? const <String, String>{}
            : parseStringMap(
              tracingMap['headers'] as Object,
              context: 'observability.tracing.headers',
              allowEmptyValues: true,
              coerceValues: true,
            );

    final metricsMap = map['metrics'] == null
        ? const <String, dynamic>{}
        : stringKeyedMap(
          map['metrics'] as Object,
          'observability.metrics',
        );
    final metricsEnabled =
        parseBoolLike(
          metricsMap['enabled'],
          context: 'observability.metrics.enabled',
          throwOnInvalid: true,
        ) ??
        false;
    final metricsPathRaw = metricsMap['path'];
    final metricsPath =
        parseStringLike(
          metricsPathRaw,
          context: 'observability.metrics.path',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        '/metrics';

    final bucketsRaw = metricsMap['buckets'];
    final parsedBuckets =
        parseDoubleList(
          bucketsRaw,
          context: 'observability.metrics.buckets',
          allowEmptyResult: true,
          allowInvalidStringEntries: false,
          throwOnInvalid: true,
        ) ??
        const <double>[];
    final buckets =
        parsedBuckets.isEmpty ? List<double>.from(_defaultBuckets) : parsedBuckets;
    for (var i = 0; i < buckets.length; i += 1) {
      if (buckets[i] <= 0) {
        throw ProviderConfigException(
          'observability.metrics.buckets[$i] must be a positive number',
        );
      }
    }

    final healthMap = map['health'] == null
        ? const <String, dynamic>{}
        : stringKeyedMap(
          map['health'] as Object,
          'observability.health',
        );
    final healthEnabled =
        parseBoolLike(
          healthMap['enabled'],
          context: 'observability.health.enabled',
          throwOnInvalid: true,
        ) ??
        true;
    final readinessRaw = healthMap['readiness_path'];
    final readinessPath =
        parseStringLike(
          readinessRaw,
          context: 'observability.health.readiness_path',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        '/readyz';
    final livenessRaw = healthMap['liveness_path'];
    final livenessPath =
        parseStringLike(
          livenessRaw,
          context: 'observability.health.liveness_path',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        '/livez';

    final errorsMap = map['errors'] == null
        ? const <String, dynamic>{}
        : stringKeyedMap(
          map['errors'] as Object,
          'observability.errors',
        );
    final errorsEnabled =
        parseBoolLike(
          errorsMap['enabled'],
          context: 'observability.errors.enabled',
          throwOnInvalid: true,
        ) ??
        false;

    return ObservabilityConfig(
      enabled: enabled,
      tracing: ObservabilityTracingConfig(
        enabled: tracingEnabled,
        serviceName: serviceName,
        exporter: exporter,
        endpoint: endpoint,
        headers: headers,
      ),
      metrics: ObservabilityMetricsConfig(
        enabled: metricsEnabled,
        path: metricsPath,
        buckets: buckets,
      ),
      health: ObservabilityHealthConfig(
        enabled: healthEnabled,
        readinessPath: readinessPath,
        livenessPath: livenessPath,
      ),
      errors: ObservabilityErrorsConfig(enabled: errorsEnabled),
    );
  }

  @override
  Map<String, dynamic> toMap(ObservabilityConfig value) {
    return {
      'enabled': value.enabled,
      'tracing': {
        'enabled': value.tracing.enabled,
        'service_name': value.tracing.serviceName,
        'exporter': value.tracing.exporter,
        'endpoint': value.tracing.endpoint?.toString(),
        'headers': value.tracing.headers,
      },
      'metrics': {
        'enabled': value.metrics.enabled,
        'path': value.metrics.path,
        'buckets': value.metrics.buckets,
      },
      'health': {
        'enabled': value.health.enabled,
        'readiness_path': value.health.readinessPath,
        'liveness_path': value.health.livenessPath,
      },
      'errors': {
        'enabled': value.errors.enabled,
      },
    };
  }
}
