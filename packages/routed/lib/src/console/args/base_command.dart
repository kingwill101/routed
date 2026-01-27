import 'dart:async';
import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:file/file.dart' as fs;
import 'package:file/local.dart' as local;
import 'package:routed/console.dart' show CliLogger;

/// Base class for all Routed CLI commands.
///
/// Provides:
/// - A shared `--verbose/-v` flag.
/// - A simple logger ([CliLogger]) that respects `--verbose`.
/// - Common filesystem helpers (project root discovery, ensureDir, path join).
/// - A `guarded` runner to standardize error handling and stack trace printing.
///
/// Subcommands should extend this class and override:
/// - [name]
/// - [description]
/// - optionally [aliases], [category]
/// - [run] to implement their behavior
abstract class BaseCommand extends Command<void> {
  BaseCommand({CliLogger? logger, fs.FileSystem? fileSystem})
    : logger = logger ?? CliLogger(),
      fileSystem = fileSystem ?? const local.LocalFileSystem() {
    // Common flag: verbose
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Enable verbose logging.',
      negatable: true,
      defaultsTo: false,
    );
  }

  /// Human-friendly category label printed in help/usage.
  @override
  String get category => 'General';

  /// Logger honoring the `--verbose` flag.
  final CliLogger logger;

  /// File system used for IO operations.
  final fs.FileSystem fileSystem;

  /// Returns true if `--verbose` is enabled.
  bool get verbose => (argResults?['verbose'] as bool?) ?? false;

  /// Convenience getter for parsed arguments.
  ArgResults? get results => argResults;

  /// The current working directory of the process.
  fs.Directory get cwd => fileSystem.currentDirectory;

  /// Runs [action] with standardized error handling.
  ///
  /// - Prints errors to stderr.
  /// - Emits stack traces when `--verbose` is enabled.
  ///
  /// Subclasses can call this from [run], for example:
  ///   return guarded(() async { ... });
  Future<void> guarded(FutureOr<void> Function() action) async {
    // Keep logger in sync with the parsed flag per-invocation.
    logger.verbose = verbose;

    try {
      await action();
    } on UsageException catch (e) {
      // Let the CommandRunner handle exit codes; we just emit the message.
      stderr.writeln(e);
      rethrow;
    } catch (e, st) {
      logger.error('Unhandled error: $e');
      if (verbose) {
        stderr.writeln(st);
      }
      rethrow;
    }
  }

  /// Print just this command's usage/help text.
  @override
  void printUsage() {
    // The `usage` getter is provided by the base `Command` class.
    stdout.writeln(usage);
  }

  /// Attempts to locate the nearest pubspec.yaml walking up from [start].
  ///
  /// Returns the directory containing the pubspec or `null` if not found
  /// within [maxLevels] parent traversals.
  Future<fs.Directory?> findProjectRoot({
    fs.Directory? start,
    int maxLevels = 10,
  }) async {
    var current = (start ?? cwd).absolute;
    for (int i = 0; i < maxLevels; i++) {
      final file = fileSystem.file(joinPath([current.path, 'pubspec.yaml']));
      if (await file.exists()) return current;

      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }
    return null;
  }

  /// Ensures [dir] exists, creating it recursively if needed.
  Future<void> ensureDir(fs.Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Writes [content] to [file], creating parent directories as needed.
  Future<void> writeTextFile(fs.File file, String content) async {
    await ensureDir(file.parent);
    await file.writeAsString(content);
  }

  /// Joins [parts] into a platform-appropriate path and normalizes repeated separators.
  String joinPath(List<String> parts) {
    final joined = fileSystem.path.joinAll(parts);
    return fileSystem.path.normalize(joined);
  }
}
