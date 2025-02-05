import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;

class BrowserProcess {
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  Process? _process;
  final _outputController = StreamController<String>.broadcast();

  BrowserProcess({
    required this.executable,
    this.arguments = const [],
    this.workingDirectory,
  });

  Stream<String> get output => _outputController.stream;

  Future<void> start() async {
    _process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );

    // Handle stdout
    _process!.stdout.transform(const SystemEncoding().decoder)
        .listen(_outputController.add);

    // Handle stderr
    _process!.stderr.transform(const SystemEncoding().decoder)
        .listen(_outputController.add);
  }

  Future<void> stop() async {
    if (_process != null) {
      _process!.kill();
      await _process!.exitCode;
      _process = null;
    }
    await _outputController.close();
  }

  bool get isRunning => _process != null;
}