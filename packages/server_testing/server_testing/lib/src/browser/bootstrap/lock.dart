import 'dart:io';

import 'package:path/path.dart' as path;

/// Provides a simple file-based locking mechanism to prevent concurrent
/// modification or installation processes within the browser registry directory.
///
/// Uses an exclusive file creation strategy and handles potentially stale locks
/// left by crashed processes.
class InstallationLock {
  /// The directory where the lock file will be created. This should typically
  /// be the root browser registry directory.
  final String lockDir;

  /// The full path to the lock file (e.g., `<registryDir>/install.lock`).
  final String lockFile;

  /// The [File] handle representing the acquired lock. Null if the lock is
  /// not currently held by this instance.
  File? _lock;

  /// Creates an installation lock manager targeting the specified [lockDir].
  ///
  /// [name] allows for more granular locking (e.g., per-browser).
  InstallationLock(this.lockDir, {String name = 'install'})
    : lockFile = path.join(lockDir, '$name.lock');

  /// Acquires the installation lock, waiting if necessary.
  ///
  /// Attempts to create the [lockFile] with exclusive access. If creation fails,
  /// it checks if the existing lock is stale (i.e., the owning process is gone)
  /// using [_isStale]. If stale, it deletes the old lock and retries. If not
  /// stale, it waits and retries periodically.
  ///
  /// Throws an exception if the lock cannot be acquired after multiple attempts.
  Future<void> acquire({Duration timeout = const Duration(minutes: 10)}) async {
    final dir = Directory(lockDir);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    final stopWatch = Stopwatch()..start();
    final interval = const Duration(seconds: 1);

    while (stopWatch.elapsed < timeout) {
      try {
        _lock = File(lockFile)..createSync(exclusive: true);
        await _lock!.writeAsString(pid.toString());
        return;
      } catch (e) {
        if (await _isStale()) {
          try {
            final file = File(lockFile);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {
            // Ignore deletion errors, might be a race condition
          }
          continue;
        }
        await Future<void>.delayed(interval);
      }
    }

    throw Exception(
      'Could not acquire lock "$lockFile" after ${timeout.inSeconds} seconds. '
      'If you are sure no other process is installing browsers, delete this file manually.',
    );
  }

  /// Releases the acquired installation lock.
  ///
  /// Deletes the [lockFile] if it exists and was acquired by this instance.
  Future<void> release() async {
    if (_lock != null && await _lock!.exists()) {
      await _lock!.delete();
    }
  }

  /// Checks if the existing lock file points to a process that is no longer running.
  ///
  /// Reads the PID from the lock file and checks if the process exists.
  /// Returns `true` if the lock file doesn't exist, cannot be read, contains
  /// an invalid PID, or the process is gone. Returns `false` if the process
  /// appears to be running.
  Future<bool> _isStale() async {
    try {
      final file = File(lockFile);
      if (!await file.exists()) return true;

      final content = await file.readAsString();
      final lockPid = int.tryParse(content.trim());
      if (lockPid == null) return true;

      if (Platform.isWindows) {
        final result = await Process.run('tasklist', [
          '/FI',
          'PID eq $lockPid',
          '/NH',
        ]);
        return !result.stdout.toString().contains('$lockPid');
      } else {
        final result = await Process.run('kill', ['-0', '$lockPid']);
        return result.exitCode != 0;
      }
    } catch (_) {
      return true;
    }
  }
}
