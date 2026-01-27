import 'dart:io';

import 'package:inertia_dart/inertia_dart.dart';

Future<void> main(List<String> args) async {
  final runtime = Platform.environment['INERTIA_SSR_RUNTIME'] ?? 'node';
  final bundle =
      Platform.environment['INERTIA_SSR_BUNDLE'] ?? 'client/dist/ssr.js';
  final host = Platform.environment['INERTIA_SSR_HOST'] ?? '127.0.0.1';
  final port =
      int.tryParse(Platform.environment['INERTIA_SSR_PORT'] ?? '13714') ??
      13714;

  final environment = Map<String, String>.from(Platform.environment)
    ..['INERTIA_SSR_HOST'] = host
    ..['INERTIA_SSR_PORT'] = port.toString()
    ..['HOST'] = host
    ..['PORT'] = port.toString();

  final config = SsrServerConfig(
    runtime: runtime,
    bundle: bundle,
    workingDirectory: Directory.current,
    environment: environment,
  );

  stdout.writeln('Starting Inertia SSR server');
  stdout.writeln('  Runtime: $runtime');
  stdout.writeln('  Bundle: $bundle');
  stdout.writeln('  Host: $host');
  stdout.writeln('  Port: $port');

  if (!await _portAvailable(host, port)) {
    stderr.writeln(
      'Port $port is already in use. Stop the existing SSR server or set '
      'INERTIA_SSR_PORT to a free port.',
    );
    exit(1);
  }

  final process = await startSsrServer(config, inheritStdio: false);
  _attachSignals(process);
  final code = await pipeSsrProcess(process);
  exit(code);
}

Future<bool> _portAvailable(String host, int port) async {
  try {
    final socket = await ServerSocket.bind(host, port);
    await socket.close();
    return true;
  } catch (_) {
    return false;
  }
}

void _attachSignals(Process process) {
  final signals = [
    ProcessSignal.sigint,
    ProcessSignal.sigterm,
    ProcessSignal.sigquit,
  ];

  for (final signal in signals) {
    try {
      signal.watch().listen((_) {
        process.kill(signal);
      });
    } on UnsupportedError {
      // Ignore unsupported signals on this platform.
    } on SignalException {
      // Ignore unsupported signals in this runtime.
    }
  }
}
