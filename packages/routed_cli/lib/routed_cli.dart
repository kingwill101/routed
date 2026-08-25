/// Command-line tooling for creating, inspecting, and deploying Routed apps.
///
/// The public barrel exposes the command runner, provider-command registries,
/// scaffold template APIs, project-command discovery, and local development
/// server lifecycle helpers. The executable itself uses the same APIs, so a
/// custom entrypoint can compose the runner without depending on internal
/// command implementation details.
///
/// A custom runner can register commands and retain the standard global
/// `--help` and `--version` behavior:
///
/// ```dart
/// import 'package:args/command_runner.dart';
/// import 'package:routed_cli/routed_cli.dart';
///
/// Future<void> main(List<String> args) async {
///   final runner = RoutedCommandRunner()
///     ..register(<Command<void>>[]);
///   await runner.run(args);
/// }
/// ```
///
/// For a new application, start with `routed create`. The generated
/// `lib/config.dart` is the source of truth for typed provider composition;
/// use `routed dev` locally and `routed deploy --target cloudflare` when the
/// app is ready for a Worker deployment.
library;

import 'dart:async';
import 'dart:io';

import 'package:routed_cli/src/console/util/dart_exec.dart';

export 'src/console/args/provider_commands.dart'
    show
        ProviderArtisanalCommandRegistration,
        ProviderArtisanalCommandRegistry,
        ProviderCommandRegistration,
        ProviderCommandRegistry,
        registerProviderArtisanalCommands,
        registerProviderCommands;
export 'src/console/args/runner.dart' show RoutedCommandRunner;
export 'src/console/create/templates.dart'
    show FileBuilder, ScaffoldTemplate, TemplateContext, Templates;
export 'src/console/create/templates_embedded.dart' show scaffoldTemplateBytes;
export 'src/console/dev/dev_server_runner.dart'
    show DevServerRunner, DevServerRunnerException, ExitCode;
export 'src/console/project/commands_loader.dart'
    show
        ProjectCommandInfo,
        ProjectCommandOption,
        ProjectCommandsLoader,
        shouldLoadProjectCommands;

/// Resolves the version string displayed by the CLI.
///
/// Priority:
/// 1) Compile-time env var "ROUTED_CLI_VERSION"
/// 2) pubspec.yaml found by walking up from [Directory.current]
/// 3) Fallback to [defaultVersion]
///
/// Use [resolve] when embedding the version in a custom command or diagnostic
/// output:
///
/// ```dart
/// final version = await CliVersion.resolve();
/// print('routed $version');
/// ```
class CliVersion {
  /// The environment key used for embedding the version at build time.
  static const String envKey = 'ROUTED_CLI_VERSION';

  /// The default fallback version when no other source is available.
  static const String defaultVersion = '0.0.0-dev';

  /// Compile-time injected version when provided by build tooling.
  static const String _embedded = String.fromEnvironment(
    envKey,
  );

  /// Resolves the CLI version string.
  ///
  /// Attempts multiple strategies in order of priority.
  static Future<String> resolve({Directory? start}) async {
    if (_embedded.isNotEmpty) return _embedded;

    final detected = await _readPubspecVersion(
      start: start ?? Directory.current,
    );
    return detected ?? defaultVersion;
  }

  /// Walks up to 5 directories looking for a pubspec.yaml and extracting
  /// its top-level `version:` field via a regex to avoid extra dependencies.
  static Future<String?> _readPubspecVersion({required Directory start}) async {
    var dir = start;

    for (var i = 0; i < 5; i++) {
      final pubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
      if (pubspec.existsSync()) {
        try {
          final content = pubspec.readAsStringSync();
          final match = RegExp(
            r'^\s*version\s*:\s*(.+)\s*$',
            multiLine: true,
            caseSensitive: false,
          ).firstMatch(content);
          if (match != null) {
            return match.group(1)?.trim();
          }
        } on Exception {
          // Ignore and continue walking up.
        }
        break;
      }

      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }
}

/// Minimal logger for CLI output.
class CliLogger {
  /// Creates a logger that emits verbose diagnostics when [verbose] is true.
  CliLogger({this.verbose = false});

  /// Whether debug messages are emitted by [debug].
  bool verbose;

  /// Writes an informational [message] to standard output.
  void info(Object? message) => stdout.writeln(message);

  /// Writes a warning [message] to standard output.
  void warn(Object? message) => stdout.writeln('WARN: $message');

  /// Writes an error [message] to standard error.
  void error(Object? message) => stderr.writeln('ERROR: $message');

  /// Writes [message] when [verbose] logging is enabled.
  void debug(Object? message) {
    if (verbose) stdout.writeln('DEBUG: $message');
  }
}

/// Options used by the `dev` command to run a development server.
class DevOptions {
  /// Creates development-server options with local-server defaults.
  const DevOptions({
    this.host = '127.0.0.1',
    this.port = 8080,
    this.entry = 'bin/server.dart',
    this.watch = const [],
    this.verbose = false,
  });

  /// Host interface on which the development server listens.
  final String host;

  /// Port on which the development server listens.
  final int port;

  /// Application entrypoint to execute.
  final String entry;

  /// Paths reserved for callers that implement additional watch behavior.
  final List<String> watch;

  /// Whether the development server should emit diagnostic logging.
  final bool verbose;

  /// Returns a copy with the supplied option values replaced.
  DevOptions copyWith({
    String? host,
    int? port,
    String? entry,
    List<String>? watch,
    bool? verbose,
  }) {
    return DevOptions(
      host: host ?? this.host,
      port: port ?? this.port,
      entry: entry ?? this.entry,
      watch: watch ?? this.watch,
      verbose: verbose ?? this.verbose,
    );
  }

  @override
  String toString() =>
      'DevOptions(\n'
      '  host: $host,\n'
      '  port: $port,\n'
      '  entry: $entry,\n'
      '  watch: $watch,\n'
      '  verbose: $verbose,\n'
      ')';
}

/// Spawns a Dart process using the current Dart executable.
///
/// By default, standard input, output, and error are inherited so the child
/// process remains attached to the invoking terminal. Set [inheritStdio] to
/// `false` when the caller needs to consume the process streams itself.
///
/// ```dart
/// final process = await spawnDartProcess(
///   ['run', 'bin/server.dart'],
///   workingDirectory: projectDirectory,
/// );
/// final exitCode = await process.exitCode;
/// ```
Future<Process> spawnDartProcess(
  List<String> args, {
  Map<String, String>? environment,
  String? workingDirectory,
  bool inheritStdio = true,
}) async {
  final process = await startDartProcess(
    args,
    workingDirectory: workingDirectory,
    environment: environment,
    mode: inheritStdio
        ? ProcessStartMode.inheritStdio
        : ProcessStartMode.normal,
  );
  return process;
}

/// Runs a development server for a Routed app.
///
/// This helper starts [DevOptions.entry] with the Dart VM service enabled and
/// forwards the host and application port as entrypoint arguments. It does
/// not watch files or restart the process; use `DevServerRunner` or the
/// `routed dev` command for the full development lifecycle.
///
/// The returned [Process] remains under the caller's control:
///
/// ```dart
/// final process = await runDevServer(const DevOptions());
/// await process.exitCode;
/// ```
Future<Process> runDevServer(DevOptions options, {CliLogger? logger}) async {
  final log = logger ?? CliLogger(verbose: options.verbose);

  // Arguments to enable the Dart VM service (hot reload capability).
  final args = <String>[
    '--enable-vm-service',
    options.entry,
    '--host',
    options.host,
    '--port',
    '${options.port}',
  ];

  log.debug('Spawning: dart ${args.join(' ')}');

  final env = <String, String>{
    // Expose a version string to the child process (useful for diagnostics).
    CliVersion.envKey: await CliVersion.resolve(),
  };

  final process = await spawnDartProcess(args, environment: env);

  log.info('Development server started (pid=${process.pid})');
  return process;
}

/// Returns the standard Routed CLI usage header.
String usageHeader() => 'A fast, minimalistic backend framework for Dart.';

/// Formats route strings as one line per route.
///
/// The function does not sort, label, or otherwise transform [routes]. An
/// empty iterable produces an empty string.
///
/// ```dart
/// final output = formatRoutesTable(['/ GET /', 'GET /health']);
/// ```
String formatRoutesTable(Iterable<String> routes) {
  final buf = StringBuffer();
  routes.forEach(buf.writeln);
  return buf.toString();
}
