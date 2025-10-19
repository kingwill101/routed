import 'package:opentelemetry/api.dart' as otel;
import 'package:opentelemetry/sdk.dart' as otel_sdk;

class TracingService {
  TracingService({
    required this.enabled,
    otel.Tracer? tracer,
    otel.TextMapPropagator<dynamic>? propagator,
  }) : _tracer = tracer,
       _propagator = propagator ?? otel.W3CTraceContextPropagator();

  final bool enabled;
  final otel.Tracer? _tracer;
  final otel.TextMapPropagator<dynamic> _propagator;

  bool get hasTracer => enabled && _tracer != null;

  otel.Tracer? get tracer => _tracer;

  otel.Context extractContext(Map<String, String> headers) {
    if (!hasTracer) {
      return otel.Context.current;
    }
    return _propagator.extract(otel.Context.current, headers, _HeaderGetter());
  }

  List<otel.Attribute> attributesFor({
    required String method,
    required String route,
    required Uri uri,
  }) {
    return [
      otel.Attribute.fromString('http.method', method),
      otel.Attribute.fromString('http.route', route),
      otel.Attribute.fromString('http.target', uri.path),
    ];
  }
}

class TracingConfig {
  const TracingConfig({
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

TracingService buildTracingService(TracingConfig config) {
  if (!config.enabled) {
    return TracingService(enabled: false);
  }

  final resource = otel_sdk.Resource([
    otel.Attribute.fromString(
      otel.ResourceAttributes.serviceName,
      config.serviceName,
    ),
  ]);

  otel_sdk.SpanExporter? exporter;
  switch (config.exporter) {
    case 'console':
      exporter = otel_sdk.ConsoleExporter();
      break;
    case 'otlp':
      if (config.endpoint != null) {
        exporter = otel_sdk.CollectorExporter(
          config.endpoint!,
          headers: config.headers,
        );
      }
      break;
    case 'none':
    default:
      exporter = null;
  }

  final processors = <otel_sdk.SpanProcessor>[];
  if (exporter != null) {
    processors.add(otel_sdk.BatchSpanProcessor(exporter));
  }

  final provider = otel_sdk.TracerProviderBase(
    processors: processors,
    resource: resource,
  );

  final tracer = processors.isNotEmpty
      ? provider.getTracer('routed', version: '0.1.0')
      : null;

  return TracingService(enabled: processors.isNotEmpty, tracer: tracer);
}

class _HeaderGetter implements otel.TextMapGetter<Map<String, String>> {
  @override
  String? get(Map<String, String> carrier, String key) {
    return carrier[key];
  }

  @override
  Iterable<String> keys(Map<String, String> carrier) => carrier.keys;
}
