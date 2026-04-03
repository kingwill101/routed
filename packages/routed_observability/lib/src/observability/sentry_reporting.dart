import 'package:sentry/sentry.dart';

import '../config/specs/observability.dart';

class SentrySpanHandle {
  SentrySpanHandle(this._span);

  final ISentrySpan _span;

  bool get finished => _span.finished;

  void setTag(String key, String value) {
    _span.setTag(key, value);
  }

  void setData(String key, Object value) {
    _span.setData(key, value);
  }

  Future<void> finish({required String route, required int statusCode}) async {
    if (_span.finished) {
      return;
    }
    _span.setTag('http.route', route);
    _span.setData('http.status_code', statusCode);
    _span.status = SpanStatus.fromHttpStatusCode(statusCode);
    await _span.finish();
  }
}

class SentryReporter {
  SentryReporter({this.operation = 'http.server'});

  final String operation;

  bool _enabled = false;
  bool _configured = false;
  ObservabilitySentryConfig? _config;

  bool get enabled => _enabled;

  Future<void> close() async {
    if (_configured) {
      await Sentry.close();
      _configured = false;
    }
    _enabled = false;
  }

  void configure(ObservabilitySentryConfig config, {required bool enabled}) {
    final effectiveEnabled = enabled && config.enabled;
    _config = config;
    _enabled = effectiveEnabled;

    if (!effectiveEnabled && _configured) {
      // Fire-and-forget shutdown to keep configure synchronous.
      // ignore: discarded_futures
      Sentry.close();
      _configured = false;
    }
  }

  Future<void> ensureReady() async {
    if (!_enabled || _config == null) {
      return;
    }

    if (_configured && _configEquals(_config!)) {
      return;
    }

    await _init(_config!);
  }

  SentrySpanHandle? startTransaction({
    required String method,
    required String route,
    required Uri uri,
    required Map<String, List<String>> headers,
  }) {
    if (!_enabled || !_configured) {
      return null;
    }

    final name = '$method $route';
    final traceHeader = _parseSentryTraceHeader(headers);
    final baggage = _parseSentryBaggage(headers);

    final transactionContext = traceHeader == null
        ? SentryTransactionContext(
            name,
            operation,
            transactionNameSource: SentryTransactionNameSource.route,
          )
        : SentryTransactionContext.fromSentryTrace(
            name,
            operation,
            traceHeader,
            transactionNameSource: SentryTransactionNameSource.route,
            baggage: baggage,
          );

    final transaction = Sentry.startTransactionWithContext(
      transactionContext,
      bindToScope: false,
      startTimestamp: DateTime.now(),
    );

    final handle = SentrySpanHandle(transaction);
    handle.setTag('http.method', method);
    handle.setTag('http.route', route);
    handle.setData('http.target', uri.path);
    return handle;
  }

  Future<void> finishTransaction(
    SentrySpanHandle? handle, {
    required String route,
    required int statusCode,
  }) async {
    if (handle == null || handle.finished) {
      return;
    }
    await handle.finish(route: route, statusCode: statusCode);
  }

  Future<void> captureException({
    required Object error,
    required StackTrace stackTrace,
    required String method,
    required String route,
    required Uri uri,
    required Map<String, List<String>> headers,
    SentrySpanHandle? span,
  }) async {
    if (!_enabled || !_configured) {
      return;
    }

    final requestContext = _buildSentryRequest(uri: uri, method: method, headers: headers);

    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        if (span != null) {
          scope.span = span._span;
          scope.transaction = route;
        }
        scope.setContexts('request', requestContext.toJson());
        scope.setTag('http.method', method);
        scope.setTag('http.route', route);
      },
    );
  }

  Future<void> _init(ObservabilitySentryConfig config) async {
    if (_configured) {
      await Sentry.close();
      _configured = false;
    }

    final dsn = config.dsn;
    if (dsn == null || dsn.isEmpty) {
      _enabled = false;
      return;
    }

    await Sentry.init((options) {
      options.dsn = dsn;
      options.sendDefaultPii = config.sendDefaultPii;
      if (config.tracesSampleRate > 0) {
        options.tracesSampleRate = config.tracesSampleRate;
      }
    });

    _configured = true;
    _enabled = true;
    _config = config;
  }

  bool _configEquals(ObservabilitySentryConfig config) {
    final current = _config;
    if (current == null) {
      return false;
    }
    return current.enabled == config.enabled &&
        current.dsn == config.dsn &&
        current.sendDefaultPii == config.sendDefaultPii &&
        current.tracesSampleRate == config.tracesSampleRate;
  }

  SentryRequest _buildSentryRequest({
    required Uri uri,
    required String method,
    required Map<String, List<String>> headers,
  }) {
    final includeHeaders = _config?.sendDefaultPii ?? false;
    final requestHeaders = <String, String>{};

    if (includeHeaders) {
      headers.forEach((name, values) {
        if (values.isNotEmpty) {
          requestHeaders[name] = values.join(',');
        }
      });
    }

    return SentryRequest.fromUri(
      uri: uri,
      method: method,
      headers: requestHeaders.isEmpty ? null : requestHeaders,
    );
  }

  SentryTraceHeader? _parseSentryTraceHeader(Map<String, List<String>> headers) {
    try {
      final value = _firstHeader(headers, 'sentry-trace');
      if (value == null || value.trim().isEmpty) {
        return null;
      }
      return SentryTraceHeader.fromTraceHeader(value.trim());
    } catch (_) {
      return null;
    }
  }

  SentryBaggage? _parseSentryBaggage(Map<String, List<String>> headers) {
    final values = _headerValues(headers, 'baggage');
    if (values.isEmpty) {
      return null;
    }
    try {
      return SentryBaggage.fromHeaderList(values);
    } catch (_) {
      return null;
    }
  }

  String? _firstHeader(Map<String, List<String>> headers, String name) {
    final values = _headerValues(headers, name);
    return values.isEmpty ? null : values.first;
  }

  List<String> _headerValues(Map<String, List<String>> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value;
      }
    }
    return const <String>[];
  }
}
