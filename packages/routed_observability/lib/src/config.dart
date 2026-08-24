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
  /// Creates tracing settings with sensible defaults for a disabled exporter.
  ObservabilityTracingConfig({
    this.enabled = false,
    this.serviceName = 'routed-service',
    this.exporter = 'none',
    this.endpoint,
    Map<String, String>? headers,
  }) : headers = Map<String, String>.unmodifiable(headers ?? const {});

  /// Whether request tracing is enabled.
  final bool enabled;

  /// The service name reported to the tracing backend.
  final String serviceName;

  /// The exporter name, such as `none`, `console`, or `otlp`.
  final String exporter;

  /// The exporter endpoint, when the selected exporter needs one.
  final Uri? endpoint;

  /// Headers sent with exporter requests.
  final Map<String, String> headers;
}

/// Typed Prometheus metrics settings owned by the observability provider.
class ObservabilityMetricsConfig {
  /// Creates metrics settings with the `/metrics` endpoint and default buckets.
  ObservabilityMetricsConfig({
    this.enabled = false,
    this.path = '/metrics',
    List<double>? buckets,
  }) : buckets = List<double>.unmodifiable(buckets ?? _defaultMetricsBuckets);

  /// Whether request metrics and the metrics endpoint are enabled.
  final bool enabled;

  /// The path at which Prometheus metrics are served.
  final String path;

  /// Upper bounds, in seconds, used for request-duration histogram buckets.
  final List<double> buckets;
}

/// Typed health endpoint settings owned by the observability provider.
class ObservabilityHealthConfig {
  /// Creates health endpoint settings using `/readyz` and `/livez`.
  ObservabilityHealthConfig({
    this.enabled = true,
    this.readinessPath = '/readyz',
    this.livenessPath = '/livez',
  });

  /// Whether readiness and liveness endpoints are enabled.
  final bool enabled;

  /// The path used for readiness checks.
  final String readinessPath;

  /// The path used for liveness checks.
  final String livenessPath;
}

/// Typed error-observer settings owned by the observability provider.
class ObservabilityErrorsConfig {
  /// Creates error-observer settings.
  const ObservabilityErrorsConfig({this.enabled = false});

  /// Whether error observers are enabled.
  final bool enabled;
}

/// Typed Sentry settings owned by the observability provider.
class ObservabilitySentryConfig {
  /// Creates Sentry settings.
  const ObservabilitySentryConfig({
    this.enabled = false,
    this.dsn,
    this.sendDefaultPii = false,
    this.tracesSampleRate = 0,
  });

  /// Whether Sentry error and transaction reporting is enabled.
  final bool enabled;

  /// The Sentry DSN used to identify the destination project.
  final String? dsn;

  /// Whether request headers and other default personal data may be sent.
  final bool sendDefaultPii;

  /// The fraction of transactions to sample, between `0` and `1`.
  final double tracesSampleRate;
}

/// Immutable startup configuration for the observability provider.
class ObservabilityConfig implements ValidatableConfiguration {
  /// Creates observability settings and fills omitted sections with defaults.
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

  /// Whether all observability services are enabled.
  final bool enabled;

  /// Tracing settings.
  final ObservabilityTracingConfig tracing;

  /// Metrics settings.
  final ObservabilityMetricsConfig metrics;

  /// Health endpoint settings.
  final ObservabilityHealthConfig health;

  /// Error-observer settings.
  final ObservabilityErrorsConfig errors;

  /// Sentry settings.
  final ObservabilitySentryConfig sentry;

  @override
  void validate(ConfigValidationContext context) {
    context
      ..require(
        tracing.serviceName.trim().isNotEmpty,
        'tracing.serviceName',
        'service name cannot be empty',
      )
      ..require(
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
      )
      ..require(
        metrics.path.startsWith('/'),
        'metrics.path',
        'metrics path must start with /',
      )
      ..require(
        metrics.buckets.isNotEmpty &&
            metrics.buckets.every((bucket) => bucket > 0),
        'metrics.buckets',
        'metrics buckets must contain positive values',
      )
      ..require(
        health.readinessPath.startsWith('/') &&
            health.livenessPath.startsWith('/'),
        'health',
        'health paths must start with /',
      )
      ..require(
        !sentry.enabled || (sentry.dsn?.trim().isNotEmpty ?? false),
        'sentry.dsn',
        'Sentry DSN is required when Sentry is enabled',
      )
      ..require(
        sentry.tracesSampleRate >= 0 && sentry.tracesSampleRate <= 1,
        'sentry.tracesSampleRate',
        'Sentry trace sample rate must be between 0 and 1',
      );
  }
}
