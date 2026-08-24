import 'dart:async';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as dotel;
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart'
    as dotel_api;

/// Provides optional OpenTelemetry context propagation and tracing.
class TracingService {
  TracingService._({
    required this.enabled,
    required dotel.W3CTraceContextPropagator propagator,
    dotel.Tracer? tracer,
    dotel.TracerProvider? provider,
    dotel.SpanExporter? exporter,
  }) : _tracer = tracer,
       _propagator = propagator,
       _provider = provider,
       _exporter = exporter;

  /// Creates a disabled tracing service.
  factory TracingService.disabled() => TracingService._(
    enabled: false,
    propagator: dotel.W3CTraceContextPropagator(),
  );

  /// Whether tracing was enabled when this service was created.
  final bool enabled;
  final dotel.Tracer? _tracer;
  final dotel.W3CTraceContextPropagator _propagator;
  final dotel.TracerProvider? _provider;
  final dotel.SpanExporter? _exporter;

  /// Whether a tracer is available for creating spans.
  bool get hasTracer => _tracer != null;

  /// The configured tracer, or `null` when tracing is disabled.
  dotel.Tracer? get tracer => _tracer;

  /// Extracts a parent context from incoming [headers].
  dotel.Context extractContext(Map<String, String> headers) {
    if (!hasTracer) {
      return dotel.Context.current;
    }

    final normalized = <String, String>{};
    headers.forEach((key, value) {
      normalized[key.toLowerCase()] = value;
    });

    return _propagator.extract(
      dotel.Context.current,
      normalized,
      _HeaderGetter(normalized),
    );
  }

  /// Injects the current trace context into [headers].
  void injectContext(Map<String, String> headers) {
    if (!hasTracer) {
      return;
    }
    _propagator.inject(dotel.Context.current, headers, _HeaderSetter(headers));
  }

  /// Builds standard HTTP attributes for a request.
  List<dotel_api.Attribute> attributesFor({
    required String method,
    required String route,
    required Uri uri,
  }) {
    final resolvedRoute = route.isEmpty ? uri.path : route;
    final target = uri.path.isEmpty ? '/' : uri.path;

    final attrs = <dotel_api.Attribute>[
      dotel.OTel.attributeString('http.method', method),
      dotel.OTel.attributeString('http.route', resolvedRoute),
      dotel.OTel.attributeString('http.target', target),
      dotel.OTel.attributeString(
        'http.scheme',
        uri.scheme.isEmpty ? 'http' : uri.scheme,
      ),
      dotel.OTel.attributeString('http.url', uri.toString()),
    ];

    if (uri.host.isNotEmpty) {
      attrs.add(dotel.OTel.attributeString('net.host.name', uri.host));
    }

    if (uri.hasPort && uri.port > 0) {
      attrs.add(dotel.OTel.attributeInt('net.host.port', uri.port));
    }

    if (uri.query.isNotEmpty) {
      attrs.add(dotel.OTel.attributeString('http.query', uri.query));
    }

    return attrs;
  }

  /// Shuts down the configured tracing provider and exporter.
  void shutdown() {
    final provider = _provider;
    if (provider != null) {
      unawaited(provider.shutdown());
    }
    final exporter = _exporter;
    if (exporter != null) {
      unawaited(exporter.shutdown());
    }
  }
}

/// Immutable configuration used to build a [TracingService].
class TracingConfig {
  /// Creates tracing configuration from an exporter and endpoint.
  const TracingConfig({
    required this.enabled,
    required this.serviceName,
    required this.exporter,
    required this.endpoint,
    required this.headers,
  });

  /// Whether tracing should be initialized.
  final bool enabled;

  /// The service name sent to OpenTelemetry.
  final String serviceName;

  /// The exporter identifier, such as `console` or `otlp`.
  final String exporter;

  /// The exporter endpoint, when one is required.
  final Uri? endpoint;

  /// Headers sent to the exporter.
  final Map<String, String> headers;
}

/// Builds a tracing service from [config].
TracingService buildTracingService(TracingConfig config) {
  if (!config.enabled) {
    return TracingService.disabled();
  }

  final initResult = _TracingSdk.ensureInitialized(config);
  if (initResult == null) {
    return TracingService.disabled();
  }

  final tracer = initResult.provider.getTracer('routed', version: '1.0.0');

  return TracingService._(
    enabled: true,
    tracer: tracer,
    propagator: dotel.W3CTraceContextPropagator(),
    provider: initResult.provider,
    exporter: initResult.exporter,
  );
}

class _TracingSdk {
  static bool _configured = false;
  static dotel.TracerProvider? _provider;
  static dotel.SpanExporter? _exporter;

  static _TracingInitResult? ensureInitialized(TracingConfig config) {
    if (!_configured) {
      final factoryEndpoint = _factoryEndpoint(config.endpoint);
      final factory = dotel.OTelSDKFactory(
        apiEndpoint: factoryEndpoint,
        apiServiceName: config.serviceName,
        apiServiceVersion: '1.0.0',
      );

      if (dotel_api.OTelFactory.otelFactory == null) {
        dotel_api.OTelFactory.otelFactory = factory;
      } else if (dotel_api.OTelFactory.otelFactory is dotel.OTelSDKFactory) {
        (dotel_api.OTelFactory.otelFactory! as dotel.OTelSDKFactory)
          ..apiEndpoint = factoryEndpoint
          ..apiServiceName = config.serviceName
          ..apiServiceVersion = '1.0.0';
      }

      final provider = dotel.OTel.tracerProvider();
      final resource = provider.resource ??= dotel.OTel.resource(
        dotel.OTel.attributesFromMap({
          'service.name': config.serviceName,
          'telemetry.sdk.language': 'dart',
          'telemetry.sdk.name': 'dartastic',
        }),
      );
      dotel.OTel.defaultResource ??= resource;

      final exporter = _createExporter(config);
      if (exporter != null) {
        provider.addSpanProcessor(dotel.BatchSpanProcessor(exporter));
      }

      _provider = provider;
      _exporter = exporter;
      _configured = true;
    }

    if (_provider == null) {
      return null;
    }

    return _TracingInitResult(_provider!, _exporter);
  }
}

class _TracingInitResult {
  const _TracingInitResult(this.provider, this.exporter);

  final dotel.TracerProvider provider;
  final dotel.SpanExporter? exporter;
}

dotel.SpanExporter? _createExporter(TracingConfig config) {
  final exporter = config.exporter.toLowerCase();
  switch (exporter) {
    case 'console':
      return dotel.ConsoleExporter();
    case 'collector':
    case 'otlp':
    case 'otlp_http':
      final endpoint = _httpEndpoint(config.endpoint);
      return dotel.OtlpHttpSpanExporter(
        dotel.OtlpHttpExporterConfig(
          endpoint: endpoint,
          headers: config.headers,
        ),
      );
    case 'grpc':
    case 'otlp_grpc':
      final endpoint = _grpcEndpoint(config.endpoint);
      final insecure =
          config.endpoint == null ||
          config.endpoint!.scheme.toLowerCase() != 'https';
      return dotel.OtlpGrpcSpanExporter(
        dotel.OtlpGrpcExporterConfig(
          endpoint: endpoint,
          insecure: insecure,
          headers: config.headers,
        ),
      );
    default:
      return null;
  }
}

String _factoryEndpoint(Uri? uri) {
  if (uri == null) {
    return 'http://localhost:4317';
  }
  if (!uri.hasScheme) {
    return uri.toString();
  }
  return uri.replace(query: '', fragment: '').toString();
}

String _httpEndpoint(Uri? uri) {
  if (uri == null) {
    return 'http://localhost:4318';
  }
  if (!uri.hasScheme) {
    final value = uri.toString();
    return value.contains('://') ? value : 'http://$value';
  }
  final sanitized = uri.replace(query: '', fragment: '');
  if (sanitized.path.isEmpty) {
    return sanitized.origin;
  }
  return sanitized.toString();
}

String _grpcEndpoint(Uri? uri) {
  if (uri == null) {
    return 'localhost:4317';
  }
  if (!uri.hasScheme) {
    final value = uri.toString();
    return value.contains(':') ? value : '$value:4317';
  }
  final host = uri.host.isEmpty ? uri.toString() : uri.host;
  final port = uri.hasPort
      ? uri.port
      : uri.scheme.toLowerCase() == 'https'
      ? 443
      : 4317;
  return '$host:$port';
}

class _HeaderGetter implements dotel_api.TextMapGetter<String> {
  _HeaderGetter(this._headers);

  final Map<String, String> _headers;

  @override
  String? get(String key) => _headers[key] ?? _headers[key.toLowerCase()];

  @override
  Iterable<String> keys() => _headers.keys;
}

class _HeaderSetter implements dotel_api.TextMapSetter<String> {
  _HeaderSetter(this._headers);

  final Map<String, String> _headers;

  @override
  void set(String key, String value) {
    _headers[key] = value;
  }
}
