library;

import 'dart:io';

import 'package:artisanal/artisanal.dart';

/// Utility helpers for SSR CLI commands.
///
/// ```dart
/// final base = normalizeSsrBase('http://localhost:13714/render');
/// ```
///
/// Normalizes an SSR endpoint URL to the base server URL.
Uri normalizeSsrBase(String url) {
  final uri = Uri.parse(url);
  if (uri.path.endsWith('/render')) {
    final basePath = uri.path.substring(0, uri.path.length - '/render'.length);
    return uri.replace(path: basePath.isEmpty ? '/' : basePath);
  }
  return uri;
}

/// Parses environment entries in `KEY=VALUE` format.
Map<String, String> parseEnvironment(List<String> entries) {
  final env = <String, String>{};
  for (final entry in entries) {
    final index = entry.indexOf('=');
    if (index <= 0) continue;
    final key = entry.substring(0, index).trim();
    final value = entry.substring(index + 1);
    if (key.isEmpty) continue;
    env[key] = value;
  }
  return env;
}

/// Attaches signal handlers to terminate the SSR [process].
void attachSignals(Process process, Console io) {
  final signals = [
    ProcessSignal.sigint,
    ProcessSignal.sigterm,
    ProcessSignal.sigquit,
  ];

  for (final signal in signals) {
    signal.watch().listen((_) {
      io.note('Stopping SSR process (${process.pid})');
      process.kill(signal);
    });
  }
}
