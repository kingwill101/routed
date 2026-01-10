import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:routed/console.dart';
import 'package:routed/src/console/dev/dev_server_runner.dart';
import 'package:routed/src/console/util/dart_exec.dart';
import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

void main() {
  group('DevServerRunner', () {
    late io.Directory tempDir;

    setUp(() async {
      tempDir = await io.Directory.systemTemp.createTemp('dev_runner_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('throws when script does not exist', () async {
      final logger = _TestLogger(verbose: true);
      final runner = DevServerRunner(
        logger: logger,
        port: '8080',
        address: io.InternetAddress.loopbackIPv4,
        dartVmServicePort: '8181',
        workingDirectory: tempDir,
        scriptPath: p.join(tempDir.path, 'bin/missing.dart'),
        directoryWatcher: (_) => _FakeDirectoryWatcher(tempDir.path),
        runProcess: (executable, arguments, {String? workingDirectory}) async =>
            io.ProcessResult(0, 0, '', ''),
      );

      await expectLater(
        runner.start(),
        throwsA(
          isA<DevServerRunnerException>().having(
            (e) => e.message,
            'message',
            contains('Script not found'),
          ),
        ),
      );
    });

    test('starts process with vm-service flag and logs output', () async {
      final logger = _TestLogger(verbose: true);
      final scriptFile = await _writeScript(tempDir);
      final startedExecutables = <String>[];
      final startedArguments = <List<String>>[];
      final runInShellValues = <bool>[];
      final workingDirectories = <String?>[];
      final processes = <_FakeProcess>[];
      final watcher = _FakeDirectoryWatcher(tempDir.path);

      Future<io.Process> startProcess(
        String executable,
        List<String> arguments, {
        bool runInShell = false,
        String? workingDirectory,
      }) async {
        startedExecutables.add(executable);
        startedArguments.add(List<String>.from(arguments));
        runInShellValues.add(runInShell);
        workingDirectories.add(workingDirectory);
        final process = _FakeProcess();
        processes.add(process);
        return process;
      }

      final runner = DevServerRunner(
        logger: logger,
        port: '4242',
        address: io.InternetAddress.loopbackIPv4,
        dartVmServicePort: '8282',
        workingDirectory: tempDir,
        scriptPath: scriptFile.path,
        hotReloadExpected: true,
        directoryWatcher: (_) => watcher,
        startProcess: startProcess,
      );

      await runner.start(['--host', '127.0.0.1']);

      expect(startedExecutables, equals([resolveDartExecutable()]));
      expect(
        startedArguments.single,
        equals([
          '--enable-vm-service=8282',
          '--enable-asserts',
          scriptFile.path,
          '--host',
          '127.0.0.1',
        ]),
      );
      expect(runInShellValues.single, isTrue);
      expect(workingDirectories.single, equals(tempDir.path));
      expect(logger.infos, contains('Running on http://127.0.0.1:4242'));

      final process = processes.single;
      process.stdoutSink.add(utf8.encode('Hello from dev\n'));
      process.stderrSink.add(
        utf8.encode('lib/app.dart:1:1: Warning: be careful\n'),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        logger.infos.any((message) => message.contains('Hello from dev')),
        isTrue,
      );
      expect(logger.warns.last, contains('Warning'));

      await runner.stop();
      expect(await runner.exitCode, ExitCode.success);

      await watcher.dispose();
      for (final proc in processes) {
        proc.dispose();
      }
    });

    test('restarts process when hot reload disabled', () async {
      final logger = _TestLogger(verbose: true);
      final scriptFile = await _writeScript(tempDir);
      final callArguments = <List<String>>[];
      final processes = <_FakeProcess>[];
      final watcher = _FakeDirectoryWatcher(tempDir.path);

      Future<io.Process> startProcess(
        String executable,
        List<String> arguments, {
        bool runInShell = false,
        String? workingDirectory,
      }) async {
        callArguments.add(List<String>.from(arguments));
        final process = _FakeProcess(pid: 9000 + processes.length);
        processes.add(process);
        return process;
      }

      final runner = DevServerRunner(
        logger: logger,
        port: '4242',
        address: io.InternetAddress.loopbackIPv4,
        dartVmServicePort: '8181',
        workingDirectory: tempDir,
        scriptPath: scriptFile.path,
        hotReloadExpected: false,
        directoryWatcher: (_) => watcher,
        startProcess: startProcess,
        runProcess: (executable, arguments, {String? workingDirectory}) async =>
            io.ProcessResult(0, 0, '', ''),
      );

      await runner.start(['--foo', 'bar']);
      expect(callArguments.length, 1);

      final firstProcess = processes.first;

      watcher.add(WatchEvent(ChangeType.MODIFY, scriptFile.path));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(callArguments.length, 2);
      expect(
        callArguments.first,
        equals([
          '--enable-vm-service=8181',
          '--enable-asserts',
          scriptFile.path,
          '--foo',
          'bar',
        ]),
      );
      expect(
        callArguments.last,
        equals([
          '--enable-vm-service=8181',
          '--enable-asserts',
          scriptFile.path,
        ]),
      );
      expect(firstProcess.killCalled, isTrue);
      expect(processes.length, 2);

      await runner.stop();
      await watcher.dispose();
      for (final proc in processes) {
        proc.dispose();
      }
    });

    test('logs change when hot reload is handled in app', () async {
      final logger = _TestLogger(verbose: true);
      final scriptFile = await _writeScript(tempDir);
      final callArguments = <List<String>>[];
      final processes = <_FakeProcess>[];
      final watcher = _FakeDirectoryWatcher(tempDir.path);

      Future<io.Process> startProcess(
        String executable,
        List<String> arguments, {
        bool runInShell = false,
        String? workingDirectory,
      }) async {
        callArguments.add(List<String>.from(arguments));
        final process = _FakeProcess();
        processes.add(process);
        return process;
      }

      final runner = DevServerRunner(
        logger: logger,
        port: '4242',
        address: io.InternetAddress.loopbackIPv4,
        dartVmServicePort: '8181',
        workingDirectory: tempDir,
        scriptPath: scriptFile.path,
        hotReloadExpected: true,
        isWindows: false,
        directoryWatcher: (_) => watcher,
        startProcess: startProcess,
        runProcess: (executable, arguments, {String? workingDirectory}) async =>
            io.ProcessResult(0, 0, '', ''),
      );

      await runner.start();
      watcher.add(WatchEvent(ChangeType.MODIFY, scriptFile.path));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(callArguments.length, 1);
      expect(
        logger.debugs.any(
          (message) => message.contains('in-app hot reload expected'),
        ),
        isTrue,
      );

      await runner.stop();
      await watcher.dispose();
      for (final proc in processes) {
        proc.dispose();
      }
    });

    test('stops with software exit code on fatal stderr', () async {
      final logger = _TestLogger(verbose: true);
      final scriptFile = await _writeScript(tempDir);
      final processes = <_FakeProcess>[];
      final watcher = _FakeDirectoryWatcher(tempDir.path);

      Future<io.Process> startProcess(
        String executable,
        List<String> arguments, {
        bool runInShell = false,
        String? workingDirectory,
      }) async {
        final process = _FakeProcess();
        processes.add(process);
        return process;
      }

      final runner = DevServerRunner(
        logger: logger,
        port: '4242',
        address: io.InternetAddress.loopbackIPv4,
        dartVmServicePort: '8181',
        workingDirectory: tempDir,
        scriptPath: scriptFile.path,
        hotReloadExpected: false,
        isWindows: false,
        directoryWatcher: (_) => watcher,
        startProcess: startProcess,
        runProcess: (executable, arguments, {String? workingDirectory}) async =>
            io.ProcessResult(0, 0, '', ''),
      );

      await runner.start();

      final process = processes.single;
      process.stderrSink.add(utf8.encode('Unhandled exception\n'));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final exit = await runner.exitCode;
      expect(exit, ExitCode.software);
      expect(process.killCalled, isTrue);
      expect(
        logger.errors.any((message) => message.contains('Unhandled exception')),
        isTrue,
      );

      await watcher.dispose();
      for (final proc in processes) {
        proc.dispose();
      }
    });
  });
}

Future<io.File> _writeScript(io.Directory root) async {
  final file = io.File(p.join(root.path, 'bin', 'server.dart'));
  await file.create(recursive: true);
  await file.writeAsString('''
import 'dart:async';

Future<void> main(List<String> args) async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
}
''');
  return file;
}

class _TestLogger extends CliLogger {
  _TestLogger({super.verbose});

  final List<String> infos = [];
  final List<String> warns = [];
  final List<String> errors = [];
  final List<String> debugs = [];

  @override
  void info(Object? message) {
    infos.add(message.toString());
  }

  @override
  void warn(Object? message) {
    warns.add(message.toString());
  }

  @override
  void error(Object? message) {
    errors.add(message.toString());
  }

  @override
  void debug(Object? message) {
    debugs.add(message.toString());
  }
}

class _FakeProcess implements io.Process {
  _FakeProcess({this.pid = 4242});

  @override
  final int pid;

  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>.broadcast();
  final Completer<int> _exitCodeCompleter = Completer<int>();
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();
  late final io.IOSink _stdin = io.IOSink(_stdinController.sink);

  bool killCalled = false;
  io.ProcessSignal? killedWith;

  StreamSink<List<int>> get stdoutSink => _stdoutController.sink;

  StreamSink<List<int>> get stderrSink => _stderrController.sink;

  void dispose() {
    _stdoutController.close();
    _stderrController.close();
    _stdinController.close();
    _stdin.close();
  }

  void completeExit(int code) {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(code);
    }
  }

  @override
  bool kill([io.ProcessSignal signal = io.ProcessSignal.sigterm]) {
    killCalled = true;
    killedWith = signal;
    completeExit(-1);
    return true;
  }

  @override
  io.IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;
}

class _FakeDirectoryWatcher implements DirectoryWatcher {
  _FakeDirectoryWatcher(this.path);

  @override
  final String path;

  final StreamController<WatchEvent> _controller =
      StreamController<WatchEvent>.broadcast();

  @override
  String get directory => path;

  @override
  Stream<WatchEvent> get events => _controller.stream;

  @override
  bool get isReady => true;

  @override
  Future<void> get ready => Future.value();

  void add(WatchEvent event) {
    _controller.add(event);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
