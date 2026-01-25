library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ssr_server_config.dart';

/// Starts, monitors, and stops a local SSR server process.
///
/// ```dart
/// final process = await startSsrServer(config);
/// final healthy = await checkSsrServer(endpoint: endpoint);
/// await stopSsrServer(endpoint: endpoint);
/// ```
///
/// Starts an SSR process using [config].
///
/// #### Throws
/// - [StateError] if the SSR bundle cannot be resolved.
Future<Process> startSsrServer(
  SsrServerConfig config, {
  bool inheritStdio = false,
}) async {
  final bundlePath = config.resolveBundle();
  if (bundlePath == null) {
    throw StateError('SSR bundle not found.');
  }
  final args = [...config.runtimeArgs, bundlePath];
  return Process.start(
    config.runtime,
    args,
    workingDirectory: config.workingDirectory?.path,
    environment: config.environment.isEmpty ? null : config.environment,
    runInShell: true,
    mode: inheritStdio
        ? ProcessStartMode.inheritStdio
        : ProcessStartMode.normal,
  );
}

/// Pipes an SSR process stdout/stderr to [stdoutSink] and [stderrSink].
///
/// Returns the process exit code once the process terminates.
Future<int> pipeSsrProcess(
  Process process, {
  StringSink? stdoutSink,
  StringSink? stderrSink,
}) async {
  final out = stdoutSink ?? stdout;
  final err = stderrSink ?? stderr;
  final stdoutLines = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final stderrLines = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  final stdoutSub = stdoutLines.listen((line) {
    if (line.trim().isEmpty) return;
    out.writeln(line);
  });
  final stderrSub = stderrLines.listen((line) {
    if (line.trim().isEmpty) return;
    err.writeln(line);
  });

  final exitCode = await process.exitCode;
  await stdoutSub.cancel();
  await stderrSub.cancel();
  return exitCode;
}

/// Checks the SSR server health endpoint and returns `true` on success.
Future<bool> checkSsrServer({
  required Uri endpoint,
  Uri? healthEndpoint,
  http.Client? client,
}) async {
  final uri = healthEndpoint ?? endpoint.resolve('/health');
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient.get(uri);
    return response.statusCode >= 200 && response.statusCode < 300;
  } finally {
    if (client == null) {
      httpClient.close();
    }
  }
}

/// Sends a shutdown request to the SSR server and returns `true` on success.
Future<bool> stopSsrServer({
  required Uri endpoint,
  Uri? shutdownEndpoint,
  http.Client? client,
}) async {
  final uri = shutdownEndpoint ?? endpoint.resolve('/shutdown');
  final httpClient = client ?? http.Client();
  try {
    await httpClient.get(uri);
    return true;
  } catch (_) {
    return false;
  } finally {
    if (client == null) {
      httpClient.close();
    }
  }
}
