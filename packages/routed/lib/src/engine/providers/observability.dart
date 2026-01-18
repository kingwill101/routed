import 'dart:async';
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as dotel;
import 'package:routed/src/config/specs/observability.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/engine/events/request.dart';
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
import 'package:sentry/sentry.dart';

class ObservabilityServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  ObservabilityServiceProvider();

  static const _metricsRouteName = 'observability.metrics';
  static const _readinessRouteName = 'observability.readiness';
  static const _livenessRouteName = 'observability.liveness';
  static const _spanKey = 'routed.observability.span';
  static const _sentrySpanKey = 'routed.observability.sentry_span';
  static const _sentryOp = 'http.server';
  static const ObservabilityConfigSpec spec = ObservabilityConfigSpec();

  bool _tracingEnabled = false;
  bool _metricsEnabled = false;
  bool _healthEnabled = true;
  bool _sentryEnabled = false;
  bool _sentryConfigured = false;
  ObservabilitySentryConfig? _sentryConfig;

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
      schemas: spec.schemaWithRoot(),
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
    await _ensureSentryReady();
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    _configure(container);
    await _ensureSentryReady();
  }

  @override
  Future<void> cleanup(Container container) async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (_sentryConfigured) {
      await Sentry.close();
      _sentryConfigured = false;
    }
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

    _sentryConfig = resolved.sentry;
    _sentryEnabled = false;
    _configureSentry(_sentryConfig!, enabled: enabled);

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
      if (!_tracingEnabled || !_tracing.hasTracer) {
        return;
      }
      final span = _spanForEvent(event);
      if (span == null || span.isEnded) {
        return;
      }
      _recordSpanEvent(span, event);
    });
  }

  FutureOr<Response> _tracingMiddleware(EngineContext ctx, Next next) async {
    final sentrySpan = _startSentryTransaction(ctx);
    if (sentrySpan != null) {
      ctx.set(_sentrySpanKey, sentrySpan);
    }
    if (!_tracingEnabled || !_tracing.hasTracer) {
      try {
        return await next();
      } catch (error, stackTrace) {
        await _captureSentryException(ctx, error, stackTrace, sentrySpan);
        rethrow;
      } finally {
        await _finishSentryTransaction(ctx, sentrySpan);
      }
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
    ctx.set(_spanKey, span);
    span.addEventNow('routed.request.start');

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
          await _captureSentryException(ctx, error, stackTrace, sentrySpan);
          rethrow;
        }
      });
    } finally {
      span.end();
      ctx.set(_spanKey, null);
      await _finishSentryTransaction(ctx, sentrySpan);
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

  void _configureSentry(
    ObservabilitySentryConfig config, {
    required bool enabled,
  }) {
    final effectiveEnabled = enabled && config.enabled;
    if (!effectiveEnabled) {
      _sentryEnabled = false;
      if (_sentryConfigured) {
        unawaited(Sentry.close());
        _sentryConfigured = false;
      }
      return;
    }

    _sentryEnabled = true;
  }

  Future<void> _initSentry(ObservabilitySentryConfig config) async {
    if (_sentryConfigured) {
      await Sentry.close();
      _sentryConfigured = false;
    }

    final dsn = config.dsn;
    if (dsn == null || dsn.isEmpty) {
      _sentryEnabled = false;
      return;
    }

    await Sentry.init((options) {
      options.dsn = dsn;
      options.sendDefaultPii = config.sendDefaultPii;
      if (config.tracesSampleRate > 0) {
        options.tracesSampleRate = config.tracesSampleRate;
      }
    });

    _sentryEnabled = true;
    _sentryConfigured = true;
    _sentryConfig = config;
  }

  Future<void> _ensureSentryReady() async {
    if (!_sentryEnabled || _sentryConfig == null) {
      return;
    }
    if (_sentryConfigured && _sentryConfigEquals(_sentryConfig!)) {
      return;
    }
    await _initSentry(_sentryConfig!);
  }

  bool _sentryConfigEquals(ObservabilitySentryConfig config) {
    final current = _sentryConfig;
    if (current == null) {
      return false;
    }
    return current.enabled == config.enabled &&
        current.dsn == config.dsn &&
        current.sendDefaultPii == config.sendDefaultPii &&
        current.tracesSampleRate == config.tracesSampleRate;
  }

  ISentrySpan? _startSentryTransaction(EngineContext ctx) {
    if (!_sentryEnabled || !_sentryConfigured) {
      return null;
    }

    final request = ctx.request;
    final routeLabel = _routeLabel(ctx);
    final name = '${request.method} $routeLabel';

    final traceHeader = _parseSentryTraceHeader(request.headers);
    final baggage = _parseSentryBaggage(request.headers);
    final transactionContext = traceHeader == null
        ? SentryTransactionContext(
            name,
            _sentryOp,
            transactionNameSource: SentryTransactionNameSource.route,
          )
        : SentryTransactionContext.fromSentryTrace(
            name,
            _sentryOp,
            traceHeader,
            transactionNameSource: SentryTransactionNameSource.route,
            baggage: baggage,
          );

    final transaction = Sentry.startTransactionWithContext(
      transactionContext,
      bindToScope: false,
      startTimestamp: DateTime.now(),
    );

    transaction.setTag('http.method', request.method);
    transaction.setTag('http.route', routeLabel);
    transaction.setData('http.target', request.uri.path);
    return transaction;
  }

  Future<void> _finishSentryTransaction(
    EngineContext ctx,
    ISentrySpan? span,
  ) async {
    if (span == null || span.finished) {
      return;
    }
    span.setTag('http.route', _routeLabel(ctx));
    span.setData('http.status_code', ctx.response.statusCode);
    span.status = SpanStatus.fromHttpStatusCode(ctx.response.statusCode);
    await span.finish();
    ctx.set(_sentrySpanKey, null);
  }

  Future<void> _captureSentryException(
    EngineContext ctx,
    Object error,
    StackTrace stackTrace,
    ISentrySpan? span,
  ) async {
    if (!_sentryEnabled || !_sentryConfigured) {
      return;
    }
    final requestContext = _buildSentryRequest(ctx);
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        if (span != null) {
          scope.span = span;
          scope.transaction = _routeLabel(ctx);
        }
        scope.setContexts('request', requestContext.toJson());
        scope.setTag('http.method', ctx.request.method);
        scope.setTag('http.route', _routeLabel(ctx));
      },
    );
  }

  SentryRequest _buildSentryRequest(EngineContext ctx) {
    final headers = <String, String>{};
    if (_sentryConfig?.sendDefaultPii ?? false) {
      ctx.request.headers.forEach((name, values) {
        if (values.isNotEmpty) {
          headers[name] = values.join(',');
        }
      });
    }

    return SentryRequest.fromUri(
      uri: ctx.request.uri,
      method: ctx.request.method,
      headers: headers.isEmpty ? null : headers,
    );
  }

  SentryTraceHeader? _parseSentryTraceHeader(HttpHeaders headers) {
    try {
      final value = headers.value('sentry-trace');
      if (value == null || value.trim().isEmpty) {
        return null;
      }
      return SentryTraceHeader.fromTraceHeader(value.trim());
    } catch (_) {
      return null;
    }
  }

  SentryBaggage? _parseSentryBaggage(HttpHeaders headers) {
    final values = headers['baggage'];
    if (values == null || values.isEmpty) {
      return null;
    }
    try {
      return SentryBaggage.fromHeaderList(values);
    } catch (_) {
      return null;
    }
  }

  dotel.Span? _spanForEvent(Event event) {
    EngineContext? context;
    if (event is BeforeRoutingEvent) {
      context = event.context;
    } else if (event is RequestStartedEvent) {
      context = event.context;
    } else if (event is RouteMatchedEvent) {
      context = event.context;
    } else if (event is RouteNotFoundEvent) {
      context = event.context;
    } else if (event is AfterRoutingEvent) {
      context = event.context;
    } else if (event is RoutingErrorEvent) {
      context = event.context;
    } else if (event is RequestFinishedEvent) {
      context = event.context;
    }
    if (context == null) {
      return null;
    }
    final span = context.get<Object>(_spanKey);
    return span is dotel.Span ? span : null;
  }

  void _recordSpanEvent(dotel.Span span, Event event) {
    if (event is BeforeRoutingEvent) {
      _addSpanEvent(
        span,
        'routed.routing.start',
        _requestAttributes(event.context),
      );
      return;
    }
    if (event is RequestStartedEvent) {
      _addSpanEvent(
        span,
        'routed.request.started',
        _requestAttributes(event.context),
      );
      return;
    }
    if (event is RouteMatchedEvent) {
      _addSpanEvent(
        span,
        'routed.route.matched',
        _routeAttributes(event.context, event.route),
      );
      return;
    }
    if (event is RouteNotFoundEvent) {
      _addSpanEvent(
        span,
        'routed.route.not_found',
        _requestAttributes(event.context),
      );
      return;
    }
    if (event is AfterRoutingEvent) {
      _addSpanEvent(
        span,
        'routed.routing.complete',
        _afterRoutingAttributes(event),
      );
      return;
    }
    if (event is RoutingErrorEvent) {
      _addSpanEvent(
        span,
        'routed.routing.error',
        _routingErrorAttributes(event),
      );
      return;
    }
    if (event is RequestFinishedEvent) {
      _addSpanEvent(
        span,
        'routed.request.finished',
        _requestAttributes(event.context),
      );
    }
  }

  void _addSpanEvent(
    dotel.Span span,
    String name,
    Map<String, Object?> attributes,
  ) {
    final cleaned = <String, Object>{};
    attributes.forEach((key, value) {
      if (value == null) {
        return;
      }
      if (value is String || value is int || value is double || value is bool) {
        cleaned[key] = value;
      } else {
        cleaned[key] = value.toString();
      }
    });
    if (cleaned.isEmpty) {
      span.addEventNow(name);
      return;
    }
    span.addEventNow(name, dotel.OTel.attributesFromMap(cleaned));
  }

  Map<String, Object?> _requestAttributes(EngineContext context) {
    return {
      'http.method': context.request.method,
      'http.target': context.request.uri.path,
      'http.route': _routeLabel(context),
      'http.status_code': context.response.statusCode,
      'routed.request_id': context.id,
    };
  }

  Map<String, Object?> _routeAttributes(
    EngineContext context,
    EngineRoute route,
  ) {
    return {
      'http.method': context.request.method,
      'http.target': context.request.uri.path,
      'http.route': route.path,
      'route.name': route.name,
      'route.method': route.method,
      'route.fallback': route.isFallback,
      'http.status_code': context.response.statusCode,
      'routed.request_id': context.id,
    };
  }

  Map<String, Object?> _afterRoutingAttributes(AfterRoutingEvent event) {
    final route = event.route;
    return {
      'http.method': event.context.request.method,
      'http.target': event.context.request.uri.path,
      'http.route': route?.path ?? _routeLabel(event.context),
      'route.name': route?.name,
      'route.method': route?.method,
      'route.fallback': route?.isFallback,
      'http.status_code': event.context.response.statusCode,
      'routed.request_id': event.context.id,
      'routed.error': event.error?.toString(),
    };
  }

  Map<String, Object?> _routingErrorAttributes(RoutingErrorEvent event) {
    final route = event.route;
    return {
      'http.method': event.context.request.method,
      'http.target': event.context.request.uri.path,
      'http.route': route?.path ?? _routeLabel(event.context),
      'route.name': route?.name,
      'route.method': route?.method,
      'route.fallback': route?.isFallback,
      'http.status_code': event.context.response.statusCode,
      'routed.request_id': event.context.id,
      'error.type': event.error.runtimeType.toString(),
      'error.message': event.error.toString(),
    };
  }
}
