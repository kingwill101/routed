import 'dart:async';
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as dotel;
import 'package:routed/src/config/specs/observability.dart';
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
  static const ObservabilityConfigSpec spec = ObservabilityConfigSpec();

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
  ConfigDefaults get defaultConfig {
    final values = spec.defaultsWithRoot();
    values['http'] = {
      'middleware_sources': {
        'routed.observability': {
          'global': [
            'routed.observability.health',
            'routed.observability.tracing',
            'routed.observability.metrics',
          ],
        },
      },
    };

    return ConfigDefaults(
      docs: <ConfigDocEntry>[
        const ConfigDocEntry(
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
        ...spec.docs(),
      ],
      values: values,
    );
  }

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

    final resolved = spec.resolve(config);
    final enabled = resolved.enabled;

    final tracingConfig = TracingConfig(
      enabled: resolved.tracing.enabled,
      serviceName: resolved.tracing.serviceName,
      exporter: resolved.tracing.exporter,
      endpoint: resolved.tracing.endpoint,
      headers: resolved.tracing.headers,
    );
    _tracing = enabled
        ? buildTracingService(tracingConfig)
        : TracingService.disabled();
    _tracingEnabled = enabled && _tracing.enabled;

    final metricsConfig = resolved.metrics;
    _metricsEnabled = enabled && metricsConfig.enabled;
    _metrics = MetricsService(buckets: metricsConfig.buckets);
    _metricsPath = metricsConfig.path;

    final healthConfig = resolved.health;
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
