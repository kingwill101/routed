import 'dart:async';
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as dotel;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/events/event.dart';
import 'package:routed/src/events/event_manager.dart';
import 'package:routed/src/observability/errors.dart';
import 'package:routed/src/observability/health.dart';
import 'package:routed/src/observability/metrics.dart';
import 'package:routed/src/observability/tracing.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/middleware_reference.dart';
import 'package:routed/src/router/types.dart';

class ObservabilityServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  ObservabilityServiceProvider();

  static const _metricsRouteName = 'observability.metrics';
  static const _readinessRouteName = 'observability.readiness';
  static const _livenessRouteName = 'observability.liveness';

  bool _tracingEnabled = false;
  bool _metricsEnabled = false;
  bool _healthEnabled = true;

  late MetricsService _metrics;
  late HealthService _health;
  late TracingService _tracing;
  late ErrorObserverRegistry _errorObservers;
  late HealthEndpointRegistry _healthRegistry;

  late final Middleware _tracingMiddlewareRef = _tracingMiddleware;
  late final Middleware _metricsMiddlewareRef = _metricsMiddleware;

  String _metricsPath = '/metrics';
  String _readinessPath = '/readyz';
  String _livenessPath = '/livez';

  StreamSubscription<Event>? _eventSubscription;

  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    docs: <ConfigDocEntry>[
      ConfigDocEntry(
        path: 'observability.enabled',
        type: 'bool',
        description:
            'Master toggle that enables or disables all observability features.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: 'observability.tracing.enabled',
        type: 'bool',
        description: 'Enable OpenTelemetry tracing middleware.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'observability.tracing.service_name',
        type: 'string',
        description: 'Logical service.name attribute reported with every span.',
        defaultValue:
            "{{ env.OBSERVABILITY_TRACING_SERVICE_NAME | default: 'routed-service' }}",
        metadata: {
          configDocMetaInheritFromEnv: 'OBSERVABILITY_TRACING_SERVICE_NAME',
        },
      ),
      ConfigDocEntry(
        path: 'observability.tracing.exporter',
        type: 'string',
        description: 'Tracing exporter (none, console, otlp).',
        options: ['none', 'console', 'otlp'],
        defaultValue: 'none',
      ),
      ConfigDocEntry(
        path: 'observability.tracing.endpoint',
        type: 'string',
        description:
            'Collector endpoint used when exporter=otlp (e.g. https://otel/v1/traces).',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: 'observability.tracing.headers',
        type: 'map',
        description:
            'Optional headers forwarded to the OTLP collector (authorization, etc.).',
        defaultValue: <String, String>{},
      ),
      ConfigDocEntry(
        path: 'observability.metrics.enabled',
        type: 'bool',
        description: 'Enable Prometheus-style metrics endpoint.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'observability.metrics.path',
        type: 'string',
        description: 'Path for metrics exposition.',
        defaultValue: '/metrics',
      ),
      ConfigDocEntry(
        path: 'observability.metrics.buckets',
        type: 'list<double>',
        description:
            'Latency histogram bucket upper bounds (seconds) for routed_request_duration_seconds.',
        defaultValue: <double>[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0],
      ),
      ConfigDocEntry(
        path: 'observability.health.enabled',
        type: 'bool',
        description: 'Enable health and readiness endpoints.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: 'observability.health.readiness_path',
        type: 'string',
        description: 'HTTP path exposed for readiness checks.',
        defaultValue: '/readyz',
      ),
      ConfigDocEntry(
        path: 'observability.health.liveness_path',
        type: 'string',
        description: 'HTTP path exposed for liveness checks.',
        defaultValue: '/livez',
      ),
      ConfigDocEntry(
        path: 'observability.errors.enabled',
        type: 'bool',
        description:
            'Enable error observer notifications (reserve for external error trackers).',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'http.middleware_sources',
        type: 'map',
        description: 'Observability middleware automatically registered.',
        defaultValue: <String, Object?>{
          'routed.observability': <String, Object?>{
            'global': <String>[
              'routed.observability.health',
              'routed.observability.tracing',
              'routed.observability.metrics',
            ],
          },
        },
      ),
    ],
  );

  @override
  void register(Container container) {
    final registry = container.get<MiddlewareRegistry>();
    registry.register(
      'routed.observability.tracing',
      (_) => _tracingMiddlewareRef,
    );
    registry.register(
      'routed.observability.metrics',
      (_) => _metricsMiddlewareRef,
    );
    _configure(container);
  }

  @override
  Future<void> boot(Container container) async {
    _configure(container);
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    _configure(container);
  }

  @override
  Future<void> cleanup(Container container) async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  void _configure(Container container) {
    final config = container.has<Config>() ? container.get<Config>() : null;
    final engine = container.has<Engine>() ? container.get<Engine>() : null;

    if (config == null || engine == null) {
      return;
    }

    final enabled = config.getBool('observability.enabled', defaultValue: true);

    final tracingConfig = _resolveTracingConfig(config);
    _tracing = enabled
        ? buildTracingService(tracingConfig)
        : TracingService.disabled();
    _tracingEnabled = enabled && _tracing.enabled;

    final metricsConfig = _resolveMetricsConfig(config);
    _metricsEnabled = enabled && metricsConfig.enabled;
    _metrics = MetricsService(buckets: metricsConfig.buckets);
    _metricsPath = metricsConfig.path;

    final healthConfig = _resolveHealthConfig(config);
    _healthEnabled = enabled && healthConfig.enabled;
    _health = HealthService(engine: engine);
    _readinessPath = healthConfig.readinessPath;
    _livenessPath = healthConfig.livenessPath;
    _healthRegistry = container.has<HealthEndpointRegistry>()
        ? container.get<HealthEndpointRegistry>()
        : HealthEndpointRegistry();
    _healthRegistry.setPaths({_readinessPath, _livenessPath});

    _errorObservers = container.has<ErrorObserverRegistry>()
        ? container.get<ErrorObserverRegistry>()
        : ErrorObserverRegistry();

    container.instance<MetricsService>(_metrics);
    container.instance<HealthService>(_health);
    container.instance<TracingService>(_tracing);
    container.instance<ErrorObserverRegistry>(_errorObservers);
    container.instance<HealthEndpointRegistry>(_healthRegistry);

    final appConfig = container.get<Config>();
    final existingGlobal = appConfig.get<Object?>(
      'http.middleware_sources.routed.observability.global',
    );
    final merged = <String>{
      if (existingGlobal is Iterable)
        ...existingGlobal.map((entry) => entry.toString()),
      'routed.observability.tracing',
      'routed.observability.metrics',
    }.toList();
    appConfig.set(
      'http.middleware_sources.routed.observability.global',
      merged,
    );

    _attachGlobalMiddleware(engine);
    _registerRoutes(engine);
    _subscribeToEvents(container);
  }

  void _subscribeToEvents(Container container) {
    final manager = container.has<EventManager>()
        ? container.get<EventManager>()
        : null;
    if (manager == null) {
      return;
    }
    _eventSubscription?.cancel();
    _eventSubscription = manager.on<Event>().listen((event) async {
      if (event is RoutingErrorEvent && _errorObservers.hasObservers) {
        await _errorObservers.notify(
          event.context,
          event.error,
          event.stackTrace,
        );
      }
    });
  }

  FutureOr<Response> _tracingMiddleware(EngineContext ctx, Next next) async {
    if (!_tracingEnabled || !_tracing.hasTracer) {
      return await next();
    }

    final request = ctx.request;
    final headers = <String, String>{};
    request.headers.forEach((name, values) {
      if (values.isNotEmpty) {
        headers[name] = values.first;
      }
    });

    final parentContext = _tracing.extractContext(headers);
    final routeLabel = _routeLabel(ctx);
    final spanAttributes = _tracing.attributesFor(
      method: request.method,
      route: routeLabel,
      uri: request.uri,
    );
    final tracer = _tracing.tracer!;

    final span = tracer.startSpan(
      '${request.method} $routeLabel',
      context: parentContext,
      kind: dotel.SpanKind.server,
      attributes: dotel.OTel.attributesFromList(spanAttributes),
    );

    try {
      return await tracer.withSpanAsync(span, () async {
        try {
          final response = await next();
          final statusCode = ctx.response.statusCode;
          span.addAttributes(
            dotel.OTel.attributes([
              dotel.OTel.attributeInt('http.status_code', statusCode),
            ]),
          );
          span.setStatus(
            statusCode >= 500
                ? dotel.SpanStatusCode.Error
                : dotel.SpanStatusCode.Ok,
          );
          return response;
        } catch (error, stackTrace) {
          final statusCode = ctx.response.statusCode >= 400
              ? ctx.response.statusCode
              : 500;
          span.addAttributes(
            dotel.OTel.attributes([
              dotel.OTel.attributeInt('http.status_code', statusCode),
            ]),
          );
          span.recordException(error, stackTrace: stackTrace);
          span.setStatus(dotel.SpanStatusCode.Error, error.toString());
          rethrow;
        }
      });
    } finally {
      span.end();
    }
  }

  FutureOr<Response> _metricsMiddleware(EngineContext ctx, Next next) async {
    if (_metricsEnabled) {
      final start = DateTime.now();
      _metrics.onRequestStart();
      final routeLabel = _routeLabel(ctx);
      try {
        final response = await next();
        final duration = DateTime.now().difference(start);
        _metrics.onRequestEnd(
          method: ctx.request.method,
          route: routeLabel,
          status: ctx.response.statusCode,
          duration: duration,
        );
        return response;
      } catch (error) {
        final duration = DateTime.now().difference(start);
        _metrics.onRequestEnd(
          method: ctx.request.method,
          route: routeLabel,
          status: ctx.response.statusCode,
          duration: duration,
        );
        rethrow;
      }
    }
    return next();
  }

  TracingConfig _resolveTracingConfig(Config config) {
    final Object? tracingNode = config.get('observability.tracing');
    final node = stringKeyedMap(
      tracingNode ?? const <String, Object?>{},
      'observability.tracing',
    );
    final enabled = node.getBool('enabled');
    final exporter = node.getString('exporter')?.toLowerCase() ?? 'none';
    final serviceName = node.getString('service_name') ?? 'routed-service';
    final endpointValue = node.getString('endpoint');
    final headersNode = node['headers'];
    final headers = <String, String>{};
    if (headersNode is Map) {
      for (final entry in headersNode.entries) {
        if (entry.value == null) continue;
        headers[entry.key.toString()] = entry.value.toString();
      }
    }
    return TracingConfig(
      enabled: enabled,
      serviceName: serviceName,
      exporter: exporter,
      endpoint: endpointValue != null && endpointValue.isNotEmpty
          ? Uri.tryParse(endpointValue)
          : null,
      headers: headers,
    );
  }

  _MetricsConfig _resolveMetricsConfig(Config config) {
    final Object? metricsNode = config.get('observability.metrics');
    final node = stringKeyedMap(
      metricsNode ?? const <String, Object?>{},
      'observability.metrics',
    );
    final enabled = node.getBool('enabled');
    final path = node.getString('path') ?? '/metrics';
    final bucketsNode = node['buckets'];
    final buckets = <double>[0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5];
    if (bucketsNode is Iterable) {
      final parsed = <double>[];
      for (final entry in bucketsNode) {
        final number = entry is num
            ? entry.toDouble()
            : double.tryParse('$entry');
        if (number != null && number > 0) {
          parsed.add(number);
        }
      }
      if (parsed.isNotEmpty) {
        buckets
          ..clear()
          ..addAll(parsed);
      }
    }
    return _MetricsConfig(enabled: enabled, path: path, buckets: buckets);
  }

  _HealthConfig _resolveHealthConfig(Config config) {
    final Object? healthNode = config.get('observability.health');
    final node = stringKeyedMap(
      healthNode ?? const <String, Object?>{},
      'observability.health',
    );
    final enabled = node.getBool('enabled', defaultValue: true);
    final readiness = node.getString('readiness_path') ?? '/readyz';
    final liveness = node.getString('liveness_path') ?? '/livez';
    return _HealthConfig(
      enabled: enabled,
      readinessPath: readiness,
      livenessPath: liveness,
    );
  }

  String _routeLabel(EngineContext ctx) {
    final name = ctx.get<String>('routed.route_name');
    final path = ctx.get<String>('routed.route_path');
    return name ?? path ?? ctx.request.uri.path;
  }

  void _attachGlobalMiddleware(Engine engine) {
    engine.middlewares.removeWhere((middleware) {
      final name = MiddlewareReference.lookup(middleware);
      return name == 'routed.observability.tracing' ||
          name == 'routed.observability.metrics';
    });
    engine.middlewares.remove(_metricsMiddlewareRef);
    engine.middlewares.remove(_tracingMiddlewareRef);
    engine.middlewares.insert(0, _metricsMiddlewareRef);
    engine.middlewares.insert(0, _tracingMiddlewareRef);
  }

  void _registerRoutes(Engine engine) {
    final router = engine.defaultRouter;

    router.routes.removeWhere((route) {
      return route.name == _metricsRouteName ||
          route.name == _readinessRouteName ||
          route.name == _livenessRouteName;
    });

    if (_metricsEnabled) {
      router
          .get(_metricsPath, (ctx) {
            final body = _metrics.renderPrometheus();
            ctx.response.statusCode = HttpStatus.ok;
            ctx.response.headers.set(
              'Content-Type',
              'text/plain; version=0.0.4',
            );
            ctx.response.write(body);
            return ctx.response;
          })
          .name(_metricsRouteName);
    }

    if (_healthEnabled) {
      router
          .get(_readinessPath, (ctx) async {
            final result = await _health.readiness();
            final body = _health.toJson(result);
            ctx.response.statusCode = result.ok
                ? HttpStatus.ok
                : HttpStatus.serviceUnavailable;
            ctx.response.headers.set('Content-Type', 'application/json');
            ctx.response.write(body);
            return ctx.response;
          })
          .name(_readinessRouteName);

      router
          .get(_livenessPath, (ctx) async {
            final result = await _health.liveness();
            final body = _health.toJson(result);
            ctx.response.statusCode = result.ok
                ? HttpStatus.ok
                : HttpStatus.serviceUnavailable;
            ctx.response.headers.set('Content-Type', 'application/json');
            ctx.response.write(body);
            return ctx.response;
          })
          .name(_livenessRouteName);
    }
  }
}

class _MetricsConfig {
  const _MetricsConfig({
    required this.enabled,
    required this.path,
    required this.buckets,
  });

  final bool enabled;
  final String path;
  final List<double> buckets;
}

class _HealthConfig {
  const _HealthConfig({
    required this.enabled,
    required this.readinessPath,
    required this.livenessPath,
  });

  final bool enabled;
  final String readinessPath;
  final String livenessPath;
}
