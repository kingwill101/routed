import 'dart:math';

class MetricsService {
  MetricsService({required List<double> buckets}) : _buckets = buckets..sort();

  final List<double> _buckets;
  final Map<_CounterKey, _Counter> _counters = {};
  final Map<_HistogramKey, _Histogram> _histograms = {};

  int _activeRequests = 0;

  int get activeRequests => _activeRequests;

  void onRequestStart() {
    _activeRequests += 1;
  }

  void onRequestEnd({
    required String method,
    required String route,
    required int status,
    required Duration duration,
  }) {
    _activeRequests = max(0, _activeRequests - 1);

    final counterKey = _CounterKey(
      method: method,
      route: route,
      status: status.toString(),
    );
    final histogramKey = _HistogramKey(
      method: method,
      route: route,
      status: status.toString(),
    );

    _counters.putIfAbsent(counterKey, _Counter.new).increment();
    _histograms
        .putIfAbsent(histogramKey, () => _Histogram(_buckets))
        .observe(duration.inMicroseconds / 1000000);
  }

  String renderPrometheus() {
    final buffer = StringBuffer()
      ..writeln('# HELP routed_requests_total Total number of HTTP requests.')
      ..writeln('# TYPE routed_requests_total counter');
    for (final entry in _counters.entries) {
      buffer
        ..write('routed_requests_total')
        ..write(entry.key.toLabelString())
        ..write(' ')
        ..writeln(entry.value.value);
    }

    buffer
      ..writeln(
        '# HELP routed_request_duration_seconds Request duration histogram (seconds).',
      )
      ..writeln('# TYPE routed_request_duration_seconds histogram');
    for (final entry in _histograms.entries) {
      final histogram = entry.value;
      final labels = entry.key;
      final buckets = histogram.buckets;
      for (final bucket in buckets.entries) {
        buffer
          ..write('routed_request_duration_seconds_bucket')
          ..write(labels.toLabelString({'le': bucket.key}))
          ..write(' ')
          ..writeln(bucket.value);
      }
      buffer
        ..write('routed_request_duration_seconds_bucket')
        ..write(labels.toLabelString({'le': '+Inf'}))
        ..write(' ')
        ..writeln(histogram.count);
      buffer
        ..write('routed_request_duration_seconds_sum')
        ..write(labels.toLabelString())
        ..write(' ')
        ..writeln(histogram.sum);
      buffer
        ..write('routed_request_duration_seconds_count')
        ..write(labels.toLabelString())
        ..write(' ')
        ..writeln(histogram.count);
    }

    buffer
      ..writeln('# HELP routed_active_requests Number of in-flight requests.')
      ..writeln('# TYPE routed_active_requests gauge')
      ..writeln('routed_active_requests $_activeRequests');

    return buffer.toString();
  }
}

class _Counter {
  int value = 0;

  void increment() {
    value += 1;
  }
}

class _Histogram {
  _Histogram(List<double> buckets)
    : _buckets = List<double>.from(buckets),
      _counts = List<int>.filled(buckets.length, 0),
      _count = 0,
      _sum = 0.0;

  final List<double> _buckets;
  final List<int> _counts;
  int _count;
  double _sum;

  void observe(double seconds) {
    _count += 1;
    _sum += seconds;
    for (var i = 0; i < _buckets.length; i++) {
      if (seconds <= _buckets[i]) {
        _counts[i] += 1;
      }
    }
  }

  Map<String, int> get buckets {
    final cumulative = <String, int>{};
    for (var i = 0; i < _buckets.length; i++) {
      final label = _formatDouble(_buckets[i]);
      cumulative[label] = _counts[i];
    }
    return cumulative;
  }

  int get count => _count;

  double get sum => _sum;
}

class _CounterKey {
  const _CounterKey({
    required this.method,
    required this.route,
    required this.status,
  });

  final String method;
  final String route;
  final String status;

  @override
  bool operator ==(Object other) {
    return other is _CounterKey &&
        other.method == method &&
        other.route == route &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(method, route, status);

  String toLabelString([Map<String, String>? extra]) {
    final labels = <String, String>{
      'method': method,
      'route': route,
      'status': status,
      if (extra != null) ...extra,
    };
    final entries = labels.entries
        .map((entry) => '${entry.key}="${_escape(entry.value)}"')
        .join(',');
    return '{$entries}';
  }
}

class _HistogramKey extends _CounterKey {
  const _HistogramKey({
    required super.method,
    required super.route,
    required super.status,
  });
}

String _escape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

String _formatDouble(double value) {
  if (value.isInfinite) return '+Inf';
  if (value.isNaN) return 'NaN';
  final asString = value.toStringAsFixed(6);
  return asString.contains('.')
      ? asString
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '')
      : asString;
}
