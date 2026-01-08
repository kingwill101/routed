import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
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
  Schema? get schema =>
      ConfigSchema.object(
        title: 'Observability Configuration',
        description: 'Tracing, metrics, and health check settings.',
        properties: {
          'enabled': ConfigSchema.boolean(
        description:
            'Master toggle that enables or disables all observability features.',
        defaultValue: true,
      ),
          'tracing': ConfigSchema.object(
            description: 'OpenTelemetry tracing settings.',
            properties: {
              'enabled': ConfigSchema.boolean(
                description: 'Enable OpenTelemetry tracing middleware.',
                defaultValue: false,
              ),
              'service_name': ConfigSchema.string(
                description:
                'Logical service.name attribute reported with every span.',
                defaultValue: 'routed-service',
              ).withMetadata({
                configDocMetaInheritFromEnv: 'OBSERVABILITY_TRACING_SERVICE_NAME',
              }),
              'exporter': ConfigSchema.string(
                description: 'Tracing exporter (none, console, otlp).',
                options: ['none', 'console', 'otlp'],
                defaultValue: 'none',
              ),
              'endpoint': ConfigSchema.string(
                description:
                'Collector endpoint used when exporter=otlp (e.g. https://otel/v1/traces).',
              ),
              'headers': ConfigSchema.object(
                description:
                'Optional headers forwarded to the OTLP collector (authorization, etc.).',
                additionalProperties: true,
              ).withDefault(const {}),
            },
      ),
          'metrics': ConfigSchema.object(
            description: 'Prometheus metrics settings.',
            properties: {
              'enabled': ConfigSchema.boolean(
                description: 'Enable Prometheus-style metrics endpoint.',
                defaultValue: false,
              ),
              'path': ConfigSchema.string(
                description: 'Path for metrics exposition.',
                defaultValue: '/metrics',
              ),
              'buckets': ConfigSchema.list(
                description:
                'Latency histogram bucket upper bounds (seconds) for routed_request_duration_seconds.',
                items: ConfigSchema.number(),
                defaultValue: _defaultBuckets,
              ),
            },
          ),
          'health': ConfigSchema.object(
            description: 'Health and readiness check settings.',
            properties: {
              'enabled': ConfigSchema.boolean(
                description: 'Enable health and readiness endpoints.',
                defaultValue: true,
              ),
              'readiness_path': ConfigSchema.string(
                description: 'HTTP path exposed for readiness checks.',
                defaultValue: '/readyz',
              ),
              'liveness_path': ConfigSchema.string(
                description: 'HTTP path exposed for liveness checks.',
                defaultValue: '/livez',
              ),
            },
          ),
          'errors': ConfigSchema.object(
            properties: {
              'enabled': ConfigSchema.boolean(
                description:
                'Enable error observer notifications (reserve for external error trackers).',
                defaultValue: false,
              ),
            },
          ),
        },
      );

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
