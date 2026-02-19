import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:contextual/contextual.dart' as contextual;
import 'package:routed/routed.dart';
import 'package:server_native/server_native.dart';
import 'package:server_native/src/native/server_native_transport.dart';
import 'package:routed_io/routed_io.dart';

final class _BenchmarkOptions {
  _BenchmarkOptions({
    required this.requests,
    required this.concurrency,
    required this.warmup,
    required this.host,
    required this.iterations,
    required this.routedLogs,
    required this.prettyOutput,
    required this.includeNativeDirectShape,
    required this.includeDirectNativeCallback,
    required this.includeRoutedNativeCallback,
    required this.minReqPerSecRatio,
    required this.maxP95Ratio,
    required this.jsonOutput,
  });

  final int requests;
  final int concurrency;
  final int warmup;
  final String host;
  final int iterations;
  final bool routedLogs;
  final bool prettyOutput;
  final bool includeNativeDirectShape;
  final bool includeDirectNativeCallback;
  final bool includeRoutedNativeCallback;
  final double? minReqPerSecRatio;
  final double? maxP95Ratio;
  final bool jsonOutput;

  static _BenchmarkOptions parse(List<String> args) {
    var requests = 5000;
    var concurrency = 64;
    var warmup = 300;
    var host = '127.0.0.1';
    var iterations = 1;
    var routedLogs = false;
    var prettyOutput = false;
    var includeNativeDirectShape = false;
    var includeDirectNativeCallback = false;
    var includeRoutedNativeCallback = false;
    double? minReqPerSecRatio;
    double? maxP95Ratio;
    var jsonOutput = false;

    for (final arg in args) {
      if (arg == '--help' || arg == '-h') {
        _printUsage();
        exit(0);
      }
      if (arg.startsWith('--requests=')) {
        requests = int.parse(arg.substring('--requests='.length));
        continue;
      }
      if (arg.startsWith('--concurrency=')) {
        concurrency = int.parse(arg.substring('--concurrency='.length));
        continue;
      }
      if (arg.startsWith('--warmup=')) {
        warmup = int.parse(arg.substring('--warmup='.length));
        continue;
      }
      if (arg.startsWith('--host=')) {
        host = arg.substring('--host='.length);
        continue;
      }
      if (arg.startsWith('--iterations=')) {
        iterations = int.parse(arg.substring('--iterations='.length));
        continue;
      }
      if (arg == '--routed-logs') {
        routedLogs = true;
        continue;
      }
      if (arg == '--pretty') {
        prettyOutput = true;
        continue;
      }
      if (arg == '--include-native-direct-shape') {
        includeNativeDirectShape = true;
        continue;
      }
      if (arg == '--include-direct-native-callback') {
        includeDirectNativeCallback = true;
        continue;
      }
      if (arg == '--include-routed-native-callback') {
        includeRoutedNativeCallback = true;
        continue;
      }
      if (arg.startsWith('--min-req-per-sec-ratio=')) {
        minReqPerSecRatio = double.parse(
          arg.substring('--min-req-per-sec-ratio='.length),
        );
        continue;
      }
      if (arg.startsWith('--max-p95-ratio=')) {
        maxP95Ratio = double.parse(arg.substring('--max-p95-ratio='.length));
        continue;
      }
      if (arg == '--json') {
        jsonOutput = true;
        continue;
      }
      stderr.writeln('Unknown argument: $arg');
      _printUsage();
      exitCode = 64;
      exit(exitCode);
    }

    if (requests <= 0 || concurrency <= 0 || warmup < 0 || iterations <= 0) {
      stderr.writeln(
        'Invalid options. requests>0, concurrency>0, warmup>=0, iterations>0 are required.',
      );
      exitCode = 64;
      exit(exitCode);
    }
    if (minReqPerSecRatio != null && minReqPerSecRatio <= 0) {
      stderr.writeln('Invalid --min-req-per-sec-ratio. Must be > 0.');
      exitCode = 64;
      exit(exitCode);
    }
    if (maxP95Ratio != null && maxP95Ratio <= 0) {
      stderr.writeln('Invalid --max-p95-ratio. Must be > 0.');
      exitCode = 64;
      exit(exitCode);
    }

    return _BenchmarkOptions(
      requests: requests,
      concurrency: concurrency,
      warmup: warmup,
      host: host,
      iterations: iterations,
      routedLogs: routedLogs,
      prettyOutput: prettyOutput,
      includeNativeDirectShape: includeNativeDirectShape,
      includeDirectNativeCallback: includeDirectNativeCallback,
      includeRoutedNativeCallback: includeRoutedNativeCallback,
      minReqPerSecRatio: minReqPerSecRatio,
      maxP95Ratio: maxP95Ratio,
      jsonOutput: jsonOutput,
    );
  }

  static void _printUsage() {
    stdout.writeln('Usage: dart run tool/benchmark_transport.dart [options]');
    stdout.writeln('Options:');
    stdout.writeln(
      '  --requests=N      Number of measured requests (default: 5000)',
    );
    stdout.writeln(
      '  --concurrency=N   Number of concurrent workers (default: 64)',
    );
    stdout.writeln(
      '  --warmup=N        Warmup requests before timing (default: 300)',
    );
    stdout.writeln(
      '  --host=ADDR       Host to bind benchmark servers (default: 127.0.0.1)',
    );
    stdout.writeln(
      '  --iterations=N    Number of benchmark iterations (default: 1)',
    );
    stdout.writeln(
      '  --routed-logs     Keep Routed startup/system logs enabled during benchmark',
    );
    stdout.writeln(
      '  --pretty          Pretty-print JSON output (use with --json)',
    );
    stdout.writeln(
      '  --include-native-direct-shape  Add rust-only direct-shape benchmark mode',
    );
    stdout.writeln(
      '  --include-direct-native-callback  Add serveNativeDirect(nativeDirect:true) mode',
    );
    stdout.writeln(
      '  --include-routed-native-callback  Add serveNative(nativeCallback:true) mode',
    );
    stdout.writeln(
      '  --min-req-per-sec-ratio=R  Require ffi req/s >= io req/s * R',
    );
    stdout.writeln(
      '  --max-p95-ratio=R          Require ffi p95 <= io p95 * R',
    );
    stdout.writeln('  --json            Emit machine-readable JSON summary');
  }
}

final class _BenchmarkResult {
  const _BenchmarkResult({
    required this.label,
    required this.requests,
    required this.totalMicros,
    required this.latenciesMicros,
  });

  final String label;
  final int requests;
  final int totalMicros;
  final List<int> latenciesMicros;

  double get requestsPerSecond => requests * 1000000 / totalMicros;

  int percentile(double p) {
    if (latenciesMicros.isEmpty) {
      return 0;
    }
    final sorted = List<int>.of(latenciesMicros)..sort();
    final rank = ((sorted.length - 1) * p).round();
    return sorted[rank];
  }
}

final class _RunningServer {
  _RunningServer({
    required this.engine,
    required this.baseUri,
    required this.shutdown,
    required this.done,
  });

  final Engine engine;
  final Uri baseUri;
  final Completer<void> shutdown;
  final Future<void> done;
}

Future<void> main(List<String> args) async {
  final options = _BenchmarkOptions.parse(args);
  if (!options.routedLogs) {
    _silenceRoutedBenchmarkLogs();
  }
  final dartIoDirectRuns = <_BenchmarkResult>[];
  final ioRuns = <_BenchmarkResult>[];
  final ffiDirectRuns = <_BenchmarkResult>[];
  final ffiDirectNativeCallbackRuns = <_BenchmarkResult>[];
  final ffiRuns = <_BenchmarkResult>[];
  final ffiNativeCallbackRuns = <_BenchmarkResult>[];
  final ffiNativeDirectRuns = <_BenchmarkResult>[];
  final ffiNativeDirectShapeRuns = <_BenchmarkResult>[];

  if (!options.jsonOutput) {
    stdout.writeln(
      'Benchmark options: requests=${options.requests}, '
      'concurrency=${options.concurrency}, warmup=${options.warmup}, '
      'host=${options.host}, iterations=${options.iterations}',
    );
  }

  for (var i = 0; i < options.iterations; i++) {
    if (!options.jsonOutput && options.iterations > 1) {
      stdout.writeln('\nIteration ${i + 1}/${options.iterations}');
    }
    dartIoDirectRuns.add(
      await _runTransportBenchmark(
        label: 'dart_io_direct',
        options: options,
        startServer: _startDartIoDirectServer,
      ),
    );
    ioRuns.add(
      await _runTransportBenchmark(
        label: 'routed_io',
        options: options,
        startServer: _startIoServer,
      ),
    );
    ffiDirectRuns.add(
      await _runTransportBenchmark(
        label: 'server_native_direct',
        options: options,
        startServer: _startFfiDirectServer,
      ),
    );
    if (options.includeDirectNativeCallback) {
      ffiDirectNativeCallbackRuns.add(
        await _runTransportBenchmark(
          label: 'server_native_direct_native_callback',
          options: options,
          startServer: _startFfiDirectNativeCallbackServer,
        ),
      );
    }
    ffiRuns.add(
      await _runTransportBenchmark(
        label: 'server_native',
        options: options,
        startServer: _startFfiServer,
      ),
    );
    if (options.includeRoutedNativeCallback) {
      ffiNativeCallbackRuns.add(
        await _runTransportBenchmark(
          label: 'server_native_callback',
          options: options,
          startServer: _startFfiNativeCallbackServer,
        ),
      );
    }
    ffiNativeDirectRuns.add(
      await _runTransportBenchmark(
        label: 'server_native_direct',
        options: options,
        startServer: _startFfiNativeDirectServer,
      ),
    );
    if (options.includeNativeDirectShape) {
      ffiNativeDirectShapeRuns.add(
        await _runTransportBenchmark(
          label: 'server_native_direct_shape',
          options: options,
          startServer: _startFfiNativeDirectShapeServer,
        ),
      );
    }
  }

  final dartIoDirectResult = _aggregateResults(
    'dart_io_direct',
    dartIoDirectRuns,
  );
  final ioResult = _aggregateResults('routed_io', ioRuns);
  final ffiDirectResult = _aggregateResults(
    'server_native_direct',
    ffiDirectRuns,
  );
  final ffiDirectNativeCallbackResult = options.includeDirectNativeCallback
      ? _aggregateResults(
          'server_native_direct_native_callback',
          ffiDirectNativeCallbackRuns,
        )
      : null;
  final ffiResult = _aggregateResults('server_native', ffiRuns);
  final ffiNativeCallbackResult = options.includeRoutedNativeCallback
      ? _aggregateResults('server_native_callback', ffiNativeCallbackRuns)
      : null;
  final ffiNativeDirectResult = _aggregateResults(
    'server_native_direct',
    ffiNativeDirectRuns,
  );
  final summaryResults = <_BenchmarkResult>[
    dartIoDirectResult,
    ioResult,
    ffiDirectResult,
    if (ffiDirectNativeCallbackResult != null) ffiDirectNativeCallbackResult,
    ffiResult,
    if (ffiNativeCallbackResult != null) ffiNativeCallbackResult,
    ffiNativeDirectResult,
  ];
  if (options.includeNativeDirectShape) {
    summaryResults.add(
      _aggregateResults('server_native_direct_shape', ffiNativeDirectShapeRuns),
    );
  }
  final gate = _evaluateGate(ioResult, ffiResult, options);

  if (options.jsonOutput) {
    final payload = <String, Object?>{
      'options': <String, Object?>{
        'requests': options.requests,
        'concurrency': options.concurrency,
        'warmup': options.warmup,
        'host': options.host,
        'iterations': options.iterations,
        'routedLogs': options.routedLogs,
        'prettyOutput': options.prettyOutput,
        'includeNativeDirectShape': options.includeNativeDirectShape,
        'includeDirectNativeCallback': options.includeDirectNativeCallback,
        'includeRoutedNativeCallback': options.includeRoutedNativeCallback,
        'minReqPerSecRatio': options.minReqPerSecRatio,
        'maxP95Ratio': options.maxP95Ratio,
      },
      'results': summaryResults.map(_resultToJson).toList(growable: false),
      'gate': <String, Object?>{
        'passed': gate.passed,
        'messages': gate.messages,
      },
    };
    final encoder = options.prettyOutput
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    stdout.writeln(encoder.convert(payload));
    if (options.prettyOutput) {
      stderr.writeln(_buildPrettyInterpretation(summaryResults));
    }
  } else {
    _printSummary(summaryResults);
    if (options.prettyOutput) {
      stdout.writeln('\n${_buildPrettyInterpretation(summaryResults)}');
    }
    if (gate.messages.isNotEmpty) {
      for (final message in gate.messages) {
        stdout.writeln(message);
      }
    }
  }

  exit(gate.passed ? 0 : 1);
}

String _buildPrettyInterpretation(List<_BenchmarkResult> results) {
  final ranked = List<_BenchmarkResult>.of(results)
    ..sort((a, b) => b.requestsPerSecond.compareTo(a.requestsPerSecond));
  final nativeOnly = ranked
      .where((result) => result.label.startsWith('server_native_direct'))
      .toList(growable: false);
  final dartInvolvedRanked = ranked
      .where((result) => !result.label.startsWith('server_native_direct'))
      .toList(growable: false);
  final fastest = ranked.first;
  final dartInvolved = dartInvolvedRanked.first;

  String renderStats(_BenchmarkResult result) {
    return '${result.requestsPerSecond.toStringAsFixed(0)} req/s, '
        'p95=${(result.percentile(0.95) / 1000).toStringAsFixed(2)} ms.';
  }

  final lines = <String>[
    '  - ${fastest.label} is fastest: ${renderStats(fastest)}',
    '  - Best Dart-involved path is ${dartInvolved.label}: ${renderStats(dartInvolved)}',
  ];

  if (nativeOnly.length > 1) {
    for (final native in nativeOnly) {
      if (native.label == fastest.label) {
        continue;
      }
      lines.add(
        '  - Additional rust-only baseline ${native.label}: ${renderStats(native)}',
      );
    }
  }

  final used = <String>{fastest.label, dartInvolved.label};
  final remaining = dartInvolvedRanked
      .where((result) => !used.contains(result.label))
      .toList(growable: false);
  for (var i = 0; i < remaining.length; i++) {
    final result = remaining[i];
    final prefix = i == remaining.length - 1 ? '  - ' : '  - Then ';
    lines.add('$prefix${result.label}: ${renderStats(result)}');
  }

  return lines.join('\n');
}

void _silenceRoutedBenchmarkLogs() {
  RoutedLogger.configureFactory((context) {
    final initialContext = <String, dynamic>{};
    for (final entry in context.entries) {
      initialContext[entry.key] = entry.value;
    }
    return contextual.Logger(formatter: contextual.PlainTextLogFormatter())
      ..addChannel('null', NullLogDriver())
      ..withContext(initialContext);
  });
}

Map<String, Object?> _resultToJson(_BenchmarkResult result) {
  return <String, Object?>{
    'label': result.label,
    'requests': result.requests,
    'totalMicros': result.totalMicros,
    'requestsPerSecond': result.requestsPerSecond,
    'p50Micros': result.percentile(0.50),
    'p95Micros': result.percentile(0.95),
  };
}

_BenchmarkResult _aggregateResults(String label, List<_BenchmarkResult> runs) {
  if (runs.isEmpty) {
    throw StateError('No benchmark runs available for $label');
  }

  if (runs.length == 1) {
    return runs.single;
  }

  final reqPerSecValues = runs.map((run) => run.requestsPerSecond).toList()
    ..sort();
  final p50Values = runs.map((run) => run.percentile(0.50)).toList()..sort();
  final p95Values = runs.map((run) => run.percentile(0.95)).toList()..sort();

  final medianReqPerSec = _medianDouble(reqPerSecValues);
  final medianP50 = _medianInt(p50Values);
  final medianP95 = _medianInt(p95Values);
  final requests = runs.first.requests;
  final totalMicros = (requests * 1000000 / medianReqPerSec).round();

  return _BenchmarkResult(
    label: label,
    requests: requests,
    totalMicros: totalMicros,
    latenciesMicros: _syntheticLatenciesFromPercentiles(
      p50Micros: medianP50,
      p95Micros: medianP95,
      count: requests,
    ),
  );
}

double _medianDouble(List<double> values) {
  final mid = values.length ~/ 2;
  if (values.length.isOdd) {
    return values[mid];
  }
  return (values[mid - 1] + values[mid]) / 2;
}

int _medianInt(List<int> values) {
  final mid = values.length ~/ 2;
  if (values.length.isOdd) {
    return values[mid];
  }
  return ((values[mid - 1] + values[mid]) / 2).round();
}

List<int> _syntheticLatenciesFromPercentiles({
  required int p50Micros,
  required int p95Micros,
  required int count,
}) {
  if (count <= 0) return const <int>[];
  if (count == 1) return <int>[p50Micros];
  final safeP95 = p95Micros < p50Micros ? p50Micros : p95Micros;
  final halfCount = math.max(1, count ~/ 2);
  final remaining = count - halfCount;
  return <int>[
    ...List<int>.filled(halfCount, p50Micros),
    ...List<int>.filled(remaining, safeP95),
  ];
}

final class _GateResult {
  const _GateResult({required this.passed, required this.messages});

  final bool passed;
  final List<String> messages;
}

_GateResult _evaluateGate(
  _BenchmarkResult ioResult,
  _BenchmarkResult ffiResult,
  _BenchmarkOptions options,
) {
  final messages = <String>[];
  var passed = true;

  if (options.minReqPerSecRatio != null) {
    final ratio = ffiResult.requestsPerSecond / ioResult.requestsPerSecond;
    final minRatio = options.minReqPerSecRatio!;
    if (ratio < minRatio) {
      passed = false;
      messages.add(
        'FAIL: req/s ratio too low. ffi/io=${ratio.toStringAsFixed(3)} < ${minRatio.toStringAsFixed(3)}',
      );
    } else {
      messages.add(
        'PASS: req/s ratio ffi/io=${ratio.toStringAsFixed(3)} >= ${minRatio.toStringAsFixed(3)}',
      );
    }
  }

  if (options.maxP95Ratio != null) {
    final ioP95 = ioResult.percentile(0.95);
    final ffiP95 = ffiResult.percentile(0.95);
    final ratio = ioP95 == 0 ? 0 : ffiP95 / ioP95;
    final maxRatio = options.maxP95Ratio!;
    if (ioP95 == 0) {
      messages.add('WARN: io p95 is zero; p95 gate skipped.');
    } else if (ratio > maxRatio) {
      passed = false;
      messages.add(
        'FAIL: p95 ratio too high. ffi/io=${ratio.toStringAsFixed(3)} > ${maxRatio.toStringAsFixed(3)}',
      );
    } else {
      messages.add(
        'PASS: p95 ratio ffi/io=${ratio.toStringAsFixed(3)} <= ${maxRatio.toStringAsFixed(3)}',
      );
    }
  }

  return _GateResult(passed: passed, messages: messages);
}

Future<_BenchmarkResult> _runTransportBenchmark({
  required String label,
  required _BenchmarkOptions options,
  required Future<_RunningServer> Function(
    Engine engine,
    String host,
    int port,
    Completer<void> shutdown,
  )
  startServer,
}) async {
  final engine = Engine()
    ..get('/bench', (ctx) async {
      return ctx.json(<String, Object?>{'ok': true, 'label': label});
    });

  final shutdown = Completer<void>();
  final port = await _reservePort(options.host);
  final running = await startServer(engine, options.host, port, shutdown);

  try {
    final uri = running.baseUri.replace(path: '/bench');
    if (options.warmup > 0) {
      await _runLoad(uri, options.warmup, options.concurrency, collect: false);
    }

    final sw = Stopwatch()..start();
    final latencies = await _runLoad(
      uri,
      options.requests,
      options.concurrency,
      collect: true,
    );
    sw.stop();

    return _BenchmarkResult(
      label: label,
      requests: options.requests,
      totalMicros: sw.elapsedMicroseconds,
      latenciesMicros: latencies,
    );
  } finally {
    if (!running.shutdown.isCompleted) {
      running.shutdown.complete();
    }
    await running.engine.close();
    try {
      await running.done.timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}

Future<List<int>> _runLoad(
  Uri uri,
  int requests,
  int concurrency, {
  required bool collect,
}) async {
  final workers = concurrency > requests ? requests : concurrency;
  final perWorker = requests ~/ workers;
  final remainder = requests % workers;
  final allLatencies = <int>[];
  final futures = <Future<void>>[];

  for (var i = 0; i < workers; i++) {
    final count = perWorker + (i < remainder ? 1 : 0);
    futures.add(() async {
      final client = HttpClient();
      try {
        final local = <int>[];
        for (var r = 0; r < count; r++) {
          final sw = Stopwatch()..start();
          final req = await client.getUrl(uri);
          final res = await req.close();
          if (res.statusCode != HttpStatus.ok) {
            throw StateError(
              'Unexpected status code ${res.statusCode} for ${uri.toString()}',
            );
          }
          final body = await utf8.decodeStream(res);
          if (collect) {
            final decoded = jsonDecode(body) as Map<String, dynamic>;
            if (decoded['ok'] != true) {
              throw StateError('Unexpected response payload: $decoded');
            }
          }
          sw.stop();
          if (collect) {
            local.add(sw.elapsedMicroseconds);
          }
        }
        if (collect && local.isNotEmpty) {
          allLatencies.addAll(local);
        }
      } finally {
        client.close(force: true);
      }
    }());
  }

  await Future.wait(futures);
  return allLatencies;
}

Future<int> _reservePort(String host) async {
  final socket = await ServerSocket.bind(host, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _waitUntilUp(Uri uri) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  final client = HttpClient();
  try {
    while (DateTime.now().isBefore(deadline)) {
      try {
        final req = await client.getUrl(uri);
        final res = await req.close();
        await res.drain<void>();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
  } finally {
    client.close(force: true);
  }
  throw StateError('Timed out waiting for server at $uri');
}

Future<_RunningServer> _startIoServer(
  Engine engine,
  String host,
  int port,
  Completer<void> shutdown,
) async {
  final done = serveIo(engine, host: host, port: port, echo: false);
  final baseUri = Uri.parse('http://$host:$port');
  await _waitUntilUp(baseUri.replace(path: '/bench'));
  return _RunningServer(
    engine: engine,
    baseUri: baseUri,
    shutdown: shutdown,
    done: done,
  );
}

Future<_RunningServer> _startDartIoDirectServer(
  Engine engine,
  String host,
  int port,
  Completer<void> shutdown,
) async {
  const bodyString = '{"ok":true,"label":"dart_io_direct"}';
  final bodyBytes = utf8.encode(bodyString);
  final server = await HttpServer.bind(host, port);

  final done = Completer<void>();
  // ignore: discarded_futures
  server
      .listen((request) async {
        if (request.uri.path != '/bench') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        await request.drain<void>();
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.add(bodyBytes);
        await request.response.close();
      })
      .asFuture<void>()
      .whenComplete(() {
        if (!done.isCompleted) {
          done.complete();
        }
      });

  // ignore: discarded_futures
  shutdown.future.whenComplete(() async {
    await server.close(force: true);
    if (!done.isCompleted) {
      done.complete();
    }
  });

  final baseUri = Uri.parse('http://$host:${server.port}');
  await _waitUntilUp(baseUri.replace(path: '/bench'));
  return _RunningServer(
    engine: engine,
    baseUri: baseUri,
    shutdown: shutdown,
    done: done.future,
  );
}

Future<_RunningServer> _startFfiServer(
  Engine engine,
  String host,
  int port,
  Completer<void> shutdown,
) async {
  final done = serveNative(
    engine.handleRequest,
    host: host,
    port: port,
    echo: false,
    http3: false,
    shutdownSignal: shutdown.future,
  );
  final baseUri = Uri.parse('http://$host:$port');
  await _waitUntilUp(baseUri.replace(path: '/bench'));
  return _RunningServer(
    engine: engine,
    baseUri: baseUri,
    shutdown: shutdown,
    done: done,
  );
}

Future<_RunningServer> _startFfiNativeCallbackServer(
  Engine engine,
  String host,
  int port,
  Completer<void> shutdown,
) async {
  final done = serveNative(
    engine.handleRequest,
    host: host,
    port: port,
    echo: false,
    http3: false,
    nativeCallback: true,
    shutdownSignal: shutdown.future,
  );
  final baseUri = Uri.parse('http://$host:$port');
  await _waitUntilUp(baseUri.replace(path: '/bench'));
  return _RunningServer(
    engine: engine,
    baseUri: baseUri,
    shutdown: shutdown,
    done: done,
  );
}

Future<_RunningServer> _startFfiDirectServer(
  Engine engine,
  String host,
  int port,
  Completer<void> shutdown,
) async {
  final bodyBytes = Uint8List.fromList(
    utf8.encode('{"ok":true,"label":"server_native_direct"}'),
  );
  final staticResponse = NativeDirectResponse.preEncodedBytes(
    headers: const <MapEntry<String, String>>[
      MapEntry(HttpHeaders.contentTypeHeader, 'application/json'),
    ],
    bodyBytes: bodyBytes,
  );
  final done = serveNativeDirect(
    (_) async => staticResponse,
    host: host,
    port: port,
    echo: false,
    http3: false,
    shutdownSignal: shutdown.future,
  );
  final baseUri = Uri.parse('http://$host:$port');
  await _waitUntilUp(baseUri.replace(path: '/bench'));
  return _RunningServer(
    engine: engine,
    baseUri: baseUri,
    shutdown: shutdown,
    done: done,
  );
}

Future<_RunningServer> _startFfiDirectNativeCallbackServer(
  Engine engine,
  String host,
  int port,
  Completer<void> shutdown,
) async {
  final bodyBytes = Uint8List.fromList(
    utf8.encode('{"ok":true,"label":"server_native_direct"}'),
  );
  final staticResponse = NativeDirectResponse.preEncodedBytes(
    headers: const <MapEntry<String, String>>[
      MapEntry(HttpHeaders.contentTypeHeader, 'application/json'),
    ],
    bodyBytes: bodyBytes,
  );
  final done = serveNativeDirect(
    (_) async => staticResponse,
    host: host,
    port: port,
    echo: false,
    http3: false,
    nativeDirect: true,
    shutdownSignal: shutdown.future,
  );
  final baseUri = Uri.parse('http://$host:$port');
  await _waitUntilUp(baseUri.replace(path: '/bench'));
  return _RunningServer(
    engine: engine,
    baseUri: baseUri,
    shutdown: shutdown,
    done: done,
  );
}

Future<_RunningServer> _startFfiNativeDirectServer(
  Engine engine,
  String host,
  int port,
  Completer<void> shutdown,
) async {
  final proxy = NativeProxyServer.start(
    host: host,
    port: port,
    backendHost: InternetAddress.loopbackIPv4.address,
    backendPort: 9,
    benchmarkMode: benchmarkModeStaticNativeDirect,
  );
  final done = Completer<void>();
  // ignore: discarded_futures
  shutdown.future.whenComplete(() {
    proxy.close();
    if (!done.isCompleted) {
      done.complete();
    }
  });

  final baseUri = Uri.parse('http://$host:${proxy.port}');
  await _waitUntilUp(baseUri.replace(path: '/bench'));
  return _RunningServer(
    engine: engine,
    baseUri: baseUri,
    shutdown: shutdown,
    done: done.future,
  );
}

Future<_RunningServer> _startFfiNativeDirectShapeServer(
  Engine engine,
  String host,
  int port,
  Completer<void> shutdown,
) async {
  final proxy = NativeProxyServer.start(
    host: host,
    port: port,
    backendHost: InternetAddress.loopbackIPv4.address,
    backendPort: 9,
    benchmarkMode: benchmarkModeStaticServerNativeDirectShape,
  );
  final done = Completer<void>();
  // ignore: discarded_futures
  shutdown.future.whenComplete(() {
    proxy.close();
    if (!done.isCompleted) {
      done.complete();
    }
  });

  final baseUri = Uri.parse('http://$host:${proxy.port}');
  await _waitUntilUp(baseUri.replace(path: '/bench'));
  return _RunningServer(
    engine: engine,
    baseUri: baseUri,
    shutdown: shutdown,
    done: done.future,
  );
}

void _printSummary(List<_BenchmarkResult> results) {
  stdout.writeln('\nResults');
  stdout.writeln(
    'transport                  req/s      p50(us)   p95(us)   total(ms)   requests',
  );
  for (final result in results) {
    final row =
        '${result.label.padRight(25)} '
        '${result.requestsPerSecond.toStringAsFixed(0).padLeft(9)} '
        '${result.percentile(0.50).toString().padLeft(9)} '
        '${result.percentile(0.95).toString().padLeft(9)} '
        '${(result.totalMicros / 1000).toStringAsFixed(2).padLeft(10)} '
        '${result.requests.toString().padLeft(10)}';
    stdout.writeln(row);
  }
}
