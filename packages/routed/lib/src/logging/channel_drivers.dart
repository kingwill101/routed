import 'dart:async';
import 'dart:io';

import 'package:contextual/contextual.dart';

/// Writes log output to stderr instead of stdout.
class StderrLogDriver extends LogDriver {
  StderrLogDriver() : super('stderr');

  @override
  Future<void> log(LogEntry entry) async {
    stderr.writeln(entry.message);
  }
}

/// Drops all log messages. Useful for null/blackhole channels.
class NullLogDriver extends LogDriver {
  NullLogDriver() : super('null');

  @override
  Future<void> log(LogEntry entry) async {}
}

/// Persists logs to a single file without rotation.
///
/// Uses [PlainTextLogFormatter] by default to avoid ANSI color codes in file output.
class SingleFileLogDriver extends LogDriver {
  SingleFileLogDriver(String path, {LogMessageFormatter? formatter})
    : _file = File(path),
      _formatter = formatter ?? PlainTextLogFormatter(),
      super('single') {
    _file.parent.createSync(recursive: true);
    _sink = _file.openWrite(mode: FileMode.append);
  }

  final File _file;
  final LogMessageFormatter _formatter;
  IOSink? _sink;

  @override
  Future<void> log(LogEntry entry) async {
    // Re-format using plain text formatter to avoid ANSI codes in file output
    final message = _formatter.format(entry.record);
    _sink?.writeln(message);
  }

  @override
  Future<void> performShutdown() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}
