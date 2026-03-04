import 'dart:io' as io;

/// Environment variables that can override the Dart executable used by the CLI.
const List<String> _dartExecutableEnvVars = <String>[
  'ROUTED_CLI_DART',
  'DART_BIN',
  'DART_PATH',
];

/// Resolves the Dart executable that should be used for outgoing CLI processes.
///
/// Preference order:
/// 1. Environment overrides (`ROUTED_CLI_DART`, `DART_BIN`, `DART_PATH`)
/// 2. `io.Platform.resolvedExecutable`
/// 3. Fallback to the bare `dart` command
String resolveDartExecutable({Map<String, String>? environment}) {
  final env = environment ?? io.Platform.environment;

  for (final key in _dartExecutableEnvVars) {
    final override = env[key];
    if (override != null && override.trim().isNotEmpty) {
      final candidate = override.trim();
      if (io.File(candidate).existsSync()) {
        return io.File(candidate).absolute.path;
      }
      // Allow overriding with command shims (e.g., just "dart") even if the
      // file does not exist locally. Rely on the caller to handle failures.
      return candidate;
    }
  }

  final resolved = io.Platform.resolvedExecutable;
  if (resolved.isNotEmpty) {
    return resolved;
  }

  return 'dart';
}

typedef DartProcessStart =
    Future<io.Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment,
      bool runInShell,
      io.ProcessStartMode mode,
    });

/// Starts a Dart process using the resolved executable.
Future<io.Process> startDartProcess(
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  bool runInShell = false,
  io.ProcessStartMode mode = io.ProcessStartMode.normal,
  DartProcessStart? start,
}) {
  final executable = resolveDartExecutable();
  final starter = start ?? io.Process.start;
  return starter(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell: runInShell,
    mode: mode,
  );
}

/// Runs a Dart command and returns the exit code.
Future<int> runDartProcess(
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  bool runInShell = false,
  io.ProcessStartMode mode = io.ProcessStartMode.normal,
  DartProcessStart? start,
}) async {
  final process = await startDartProcess(
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell: runInShell,
    mode: mode,
    start: start,
  );
  return process.exitCode;
}
