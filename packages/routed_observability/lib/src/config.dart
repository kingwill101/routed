import 'package:routed_core/routed_core.dart';

const List<double> _defaultMetricsBuckets = [
  0.01,
  0.05,
  0.1,
  0.25,
  0.5,
  1.0,
  2.0,
  5.0,
];

/// Typed tracing settings owned by the observability provider.
class ObservabilityTracingConfig {
  ObservabilityTracingConfig({
    this.enabled = false,
    this.serviceName = 'routed-service',
    this.exporter = 'none',
    this.endpoint,
    Map<String, String>? headers,
  }) : headers = Map<String, String>.unmodifiable(headers ?? const {});

  final bool enabled;
  final String serviceName;
  final String exporter;
  final Uri? endpoint;
  final Map<String, String> headers;
}

/// Typed Prometheus metrics settings owned by the observability provider.
class ObservabilityMetricsConfig {
  ObservabilityMetricsConfig({
    this.enabled = false,
    this.path = '/metrics',
    List<double>? buckets,
  }) : buckets = List<double>.unmodifiable(buckets ?? _defaultMetricsBuckets);

  final bool enabled;
  final String path;
  final List<double> buckets;
}

/// Typed health endpoint settings owned by the observability provider.
class ObservabilityHealthConfig {
  ObservabilityHealthConfig({
    this.enabled = true,
    this.readinessPath = '/readyz',
    this.livenessPath = '/livez',
  });

  final bool enabled;
  final String readinessPath;
  final String livenessPath;
}

/// Typed error-observer settings owned by the observability provider.
class ObservabilityErrorsConfig {
  const ObservabilityErrorsConfig({this.enabled = false});

  final bool enabled;
}

/// Typed Sentry settings owned by the observability provider.
class ObservabilitySentryConfig {
  const ObservabilitySentryConfig({
    this.enabled = false,
    this.dsn,
    this.sendDefaultPii = false,
    this.tracesSampleRate = 0,
  });

  final bool enabled;
  final String? dsn;
  final bool sendDefaultPii;
  final double tracesSampleRate;
}

/// Immutable startup configuration for [ObservabilityServiceProvider].
class ObservabilityConfig implements ValidatableConfiguration {
  ObservabilityConfig({
    this.enabled = true,
    ObservabilityTracingConfig? tracing,
    ObservabilityMetricsConfig? metrics,
    ObservabilityHealthConfig? health,
    ObservabilityErrorsConfig? errors,
    ObservabilitySentryConfig? sentry,
  }) : tracing = tracing ?? ObservabilityTracingConfig(),
       metrics = metrics ?? ObservabilityMetricsConfig(),
       health = health ?? ObservabilityHealthConfig(),
       errors = errors ?? const ObservabilityErrorsConfig(),
       sentry = sentry ?? const ObservabilitySentryConfig();

  final bool enabled;
  final ObservabilityTracingConfig tracing;
  final ObservabilityMetricsConfig metrics;
  final ObservabilityHealthConfig health;
  final ObservabilityErrorsConfig errors;
  final ObservabilitySentryConfig sentry;

  @override
  void validate(ConfigValidationContext context) {
    context.require(
      tracing.serviceName.trim().isNotEmpty,
      'tracing.serviceName',
      'service name cannot be empty',
    );
    context.require(
      const {
        'none',
        'console',
        'otlp',
        'otlp_http',
        'grpc',
        'otlp_grpc',
      }.contains(tracing.exporter.toLowerCase()),
      'tracing.exporter',
      'exporter must be none, console, otlp, or grpc',
    );
    context.require(
      metrics.path.startsWith('/'),
      'metrics.path',
      'metrics path must start with /',
    );
    context.require(
      metrics.buckets.isNotEmpty &&
          metrics.buckets.every((bucket) => bucket > 0),
      'metrics.buckets',
      'metrics buckets must contain positive values',
    );
    context.require(
      health.readinessPath.startsWith('/') &&
          health.livenessPath.startsWith('/'),
      'health',
      'health paths must start with /',
    );
    context.require(
      !sentry.enabled || (sentry.dsn?.trim().isNotEmpty ?? false),
      'sentry.dsn',
      'Sentry DSN is required when Sentry is enabled',
    );
    context.require(
      sentry.tracesSampleRate >= 0 && sentry.tracesSampleRate <= 1,
      'sentry.tracesSampleRate',
      'Sentry trace sample rate must be between 0 and 1',
    );
  }
}
