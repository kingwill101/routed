import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:routed_cli/routed_cli.dart' as rc;
import 'package:routed_cli/src/util/dart_exec.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:watcher/watcher.dart';

/// Typedef for [io.Process.start].
typedef ProcessStart =
    Future<io.Process> Function(
      String executable,
      List<String> arguments, {
      bool runInShell,
      String? workingDirectory,
    });

/// Typedef for [io.Process.run].
typedef ProcessRun =
    Future<io.ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// Typedef for [DirectoryWatcher.new].
typedef DirectoryWatcherBuilder = DirectoryWatcher Function(String directory);

/// Minimal ExitCode helper mirroring common Unix exit codes.
class ExitCode {
  final int code;

  const ExitCode._(this.code);

  static const success = ExitCode._(0);
  static const usage = ExitCode._(64);
  static const data = ExitCode._(65);
  static const noInput = ExitCode._(66);
  static const software = ExitCode._(70);
  static const unavailable = ExitCode._(69);

  @override
  String toString() => 'ExitCode($code)';
}

/// Regex for detecting warnings emitted by the SDK in stderr.
final _warningRegex = RegExp(r'^.*:\d+:\d+: Warning: .*', multiLine: true);

/// Regex for detecting a VM service port already in use error.
final _vmServiceInUseRegex = RegExp(
  r'^Could not start the VM service: (?:localhost|[\w\.\-]+):.* is already in use\.',
  multiLine: true,
);

/// Regex for detecting hot reload output from the app (best-effort).
/// The routed_cli bootstrap prints "Hot-reload result:" on reload.
final _hotReloadMarkerRegex = RegExp(r'Hot-reload result:', multiLine: true);

/// A class that manages a local development server process lifecycle for Routed.
///
/// Responsibilities:
/// - Launch the Dart process with `--enable-vm-service`.
/// - Watch project files for changes.
/// - If hot-reload is expected (bootstrap mode), let `hotreloader` apply changes.
/// - Otherwise, restart the process on file changes.
/// - Handle shutdown signals and process termination gracefully.
///
/// This class is inspired by the Dart Frog DevServerRunner, but simplified to
/// fit the routed_cli needs and without code generation.
class DevServerRunner {
  DevServerRunner({
    required this.logger,
    required this.port,
    required this.address,
    required this.dartVmServicePort,
    required this.workingDirectory,
    required this.scriptPath,
    this.hotReloadExpected = true,
    List<String>? additionalWatchPaths,
    void Function()? onHotReloadEnabled,
    // Testability hooks
    DirectoryWatcherBuilder? directoryWatcher,
    bool? isWindows,
    io.ProcessSignal? sigint,
    ProcessStart? startProcess,
    ProcessRun? runProcess,
  }) : _onHotReloadEnabled = onHotReloadEnabled,
       _directoryWatcher = directoryWatcher ?? DirectoryWatcher.new,
       _isWindows = isWindows ?? io.Platform.isWindows,
       _sigint = sigint ?? io.ProcessSignal.sigint,
       _startProcess = startProcess ?? io.Process.start,
       _runProcess = runProcess ?? io.Process.run,
       extraWatchPaths = List.unmodifiable(additionalWatchPaths ?? const []) {
    if (port.isEmpty) {
      throw ArgumentError.value(port, 'port', 'cannot be empty');
    }
    if (dartVmServicePort.isEmpty) {
      throw ArgumentError.value(
        dartVmServicePort,
        'dartVmServicePort',
        'cannot be empty',
      );
    }
  }

  /// Logger used for diagnostics and output wrapping.
  final rc.CliLogger logger;

  /// The port for the HTTP server.
  final String port;

  /// The host/address for the HTTP server (defaults to localhost if null).
  final io.InternetAddress? address;

  /// The Dart VM service port to enable hot reload support.
  final String dartVmServicePort;

  /// The project working directory (root).
  final io.Directory workingDirectory;

  /// The script to run (e.g., entrypoint or a generated bootstrap).
  final String scriptPath;

  /// Whether we expect the app to manage hot reload internally (via hotreloader).
  ///
  /// - If true: file changes will NOT restart the process; they are left to
  ///   be handled by the in-app hot reloader.
  /// - If false: file changes will trigger a full process restart.
  final bool hotReloadExpected;

  /// Optional callback when hot reload is detected/enabled.
  final void Function()? _onHotReloadEnabled;

  /// Additional project files/directories to watch for changes.
  final List<String> extraWatchPaths;

  // Testability and platform hooks
  final DirectoryWatcherBuilder _directoryWatcher;
  final ProcessStart _startProcess;
  final ProcessRun _runProcess;
  final bool _isWindows;
  final io.ProcessSignal _sigint;

  io.Process? _serverProcess;
  StreamSubscription<WatchEvent>? _watcherSub;
  bool _isReloading = false;
  bool _hotReloadLogSeen = false;

  final Completer<ExitCode> _exitCodeCompleter = Completer<ExitCode>();

  /// Whether the dev server is running.
  bool get isServerRunning => _serverProcess != null;

  /// Whether a watcher is active.
  bool get isWatching => _watcherSub != null;

  /// Whether the server has completed its lifecycle (stopped).
  bool get isCompleted => _exitCodeCompleter.isCompleted;

  /// A future that completes with the exit code when the server stops.
  Future<ExitCode> get exitCode => _exitCodeCompleter.future;

  /// Start watching and serving. Optional [arguments] are forwarded to the app.
  Future<void> start([List<String> arguments = const []]) async {
    if (isCompleted) {
      throw DevServerRunnerException(
        'Cannot start after runner has been stopped.',
      );
    }
    if (isServerRunning) {
      throw DevServerRunnerException(
        'Cannot start while the server is already running.',
      );
    }

    // Validate script path exists
    final scriptFile = io.File(_abs(scriptPath));
    if (!await scriptFile.exists()) {
      throw DevServerRunnerException('Script not found: ${scriptFile.path}');
    }

    await _serve(arguments);
    _watch(arguments);
  }

  /// Stop the watcher and server and complete [exitCode].
  Future<void> stop([ExitCode code = ExitCode.success]) async {
    if (isCompleted) return;

    if (isWatching) {
      await _cancelWatcher();
    }

    if (isServerRunning) {
      await _killServer();
    }

    _exitCodeCompleter.complete(code);
  }

  /// Trigger a reload event (logs only when in hotReloadExpected mode).
  Future<void> reload() async {
    if (isCompleted || !isServerRunning || _isReloading) return;
    return _reloadInternal(verbose: true);
  }

  // ---- Internals ----

  Future<void> _serve(List<String> forwardedArgs) async {
    final enableVmSvcFlag = '--enable-vm-service=$dartVmServicePort';
    final script = _abs(scriptPath);

    final dartExecutable = resolveDartExecutable();
    logger.debug(
      '[process] $dartExecutable $enableVmSvcFlag --enable-asserts $script ${forwardedArgs.join(' ')}',
    );

    final proc = _serverProcess = await _startProcess(
      dartExecutable,
      [enableVmSvcFlag, '--enable-asserts', script, ...forwardedArgs],
      runInShell: true,
      workingDirectory: workingDirectory.path,
    );

    // On Windows, handle Ctrl-C to ensure child processes are killed.
    if (_isWindows) {
      _sigint.watch().listen((_) {
        _killServer().ignore();
        stop();
      });
    }

    proc.stderr.listen((data) async {
      if (_isReloading) return;

      final message = utf8.decode(data).trim();
      if (message.isEmpty) return;

      final isVmPortInUse = _vmServiceInUseRegex.hasMatch(message);
      final isSdkWarning = _warningRegex.hasMatch(message);

      if (isVmPortInUse) {
        logger.error(
          '$message Try specifying a different VM service port for dev.',
        );
      } else if (isSdkWarning) {
        // Print warnings but do not kill process.
        logger.warn(message);
      } else {
        logger.error(message);
      }

      if ((!_hotReloadLogSeen && !isSdkWarning) || isVmPortInUse) {
        await _killServer();
        await stop(ExitCode.software);
        return;
      }
    });

    proc.stdout.listen((data) {
      final message = utf8.decode(data).trim();
      if (message.isNotEmpty) logger.info(message);

      if (_hotReloadMarkerRegex.hasMatch(message)) {
        _hotReloadLogSeen = true;
        _onHotReloadEnabled?.call();
      }
    });

    proc.exitCode.then((code) async {
      if (isCompleted) return;
      logger
        ..info('[process] Server process terminated')
        ..debug('[process] exit($code)');
      await _killServer();
      await stop(ExitCode.unavailable);
    }).ignore();
  }

  void _watch(List<String> forwardedArgs) {
    // Set up watcher over the working directory and filter on known paths.
    final root = workingDirectory.path;

    final libDir = p.join(root, 'lib');
    final binDir = p.join(root, 'bin');
    final pubspec = p.join(root, 'pubspec.yaml');

    bool shouldReact(WatchEvent event) {
      final ep = _abs(scriptPath);
      final path = p.normalize(event.path);

      logger.debug('[watcher] $event');

      return path == pubspec ||
          path == ep ||
          p.isWithin(libDir, path) ||
          p.isWithin(binDir, path) ||
          extraWatchPaths.any((w) {
            final wp = _abs(w);
            return path == wp || p.isWithin(wp, path);
          });
    }

    final watcher = _directoryWatcher(root);
    _watcherSub = watcher.events
        .where(shouldReact)
        .debounce(const Duration(milliseconds: 100))
        .listen((_) => _reloadInternal());

    _watcherSub!
        .asFuture<void>()
        .then((_) async {
          await _cancelWatcher();
          await stop();
        })
        .catchError((_) async {
          await _cancelWatcher();
          await stop(ExitCode.software);
        })
        .ignore();

    final hostAddress = address?.address ?? 'localhost';
    logger.info('Running on http://$hostAddress:$port');
  }

  Future<void> _reloadInternal({bool verbose = false}) async {
    final void Function(Object?) log = verbose ? logger.info : logger.debug;

    if (hotReloadExpected) {
      // Let in-app hotreloader react; we only log here.
      log('[reload] change detected (in-app hot reload expected).');
      return;
    }

    // Full restart mode
    if (!isServerRunning) return;

    log('[reload] change detected, restarting process...');
    _isReloading = true;
    await _killServer();
    await _serve(const []);
    _isReloading = false;
    log('[reload] restart complete.');
  }

  Future<void> _killServer() async {
    _isReloading = false;
    final proc = _serverProcess;
    if (proc == null) return;

    logger.debug('[process] terminating server (pid=${proc.pid})...');
    if (_isWindows) {
      logger.debug('[process] taskkill /F /T /PID ${proc.pid}');
      await _runProcess('taskkill', ['/F', '/T', '/PID', '${proc.pid}']);
    } else {
      proc.kill();
    }
    _serverProcess = null;
    logger.debug('[process] termination complete.');
  }

  Future<void> _cancelWatcher() async {
    final sub = _watcherSub;
    if (sub == null) return;
    logger.debug('[watcher] cancelling subscription...');
    await sub.cancel();
    _watcherSub = null;
    logger.debug('[watcher] subscription cancelled.');
  }

  String _abs(String pathlike) {
    final pth = io.File(pathlike).absolute.path;
    return p.normalize(pth);
  }
}

/// Exception thrown when the dev server runner fails or is misused.
class DevServerRunnerException implements Exception {
  DevServerRunnerException(this.message);

  final String message;

  @override
  String toString() => message;
}
