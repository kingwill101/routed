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
  InstallationLock(this.lockDir)
      : lockFile = path.join(lockDir, 'install.lock');

      /// Acquires the installation lock, waiting if necessary.
      ///
      /// Attempts to create the [lockFile] with exclusive access. If creation fails,
      /// it checks if the existing lock is stale (i.e., the owning process is gone)
      /// using [_isStale]. If stale, it deletes the old lock and retries. If not
      /// stale, it waits and retries periodically.
      ///
      /// Throws an exception if the lock cannot be acquired after multiple attempts.
  Future<void> acquire() async {
    final dir = Directory(lockDir);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    int attempts = 0;
    const maxAttempts = 60; // 1 minute with 1-second intervals

    while (attempts < maxAttempts) {
      try {
        _lock = File(lockFile)..createSync(exclusive: true);
        await _lock!.writeAsString(pid.toString());
        return;
      } catch (e) {
        if (await _isStale()) {
          await File(lockFile).delete();
          continue;
        }
        attempts++;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }

    throw Exception('Could not acquire lock after $maxAttempts attempts');
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
  /// Reads the PID from the lock file and uses `kill -0 <pid>` (on non-Windows)
  /// to check if the process exists. Returns `true` if the lock file doesn't exist,
  /// cannot be read, contains an invalid PID, or the process is gone. Returns
  /// `false` if the process appears to be running.
  ///
  /// Note: Process check is platform-dependent and currently only implemented
  /// for Unix-like systems. On Windows, it might always return true if reading fails.
  Future<bool> _isStale() async {
    try {
      final lockPid = int.parse(await File(lockFile).readAsString());
      final result = await Process.run('kill', ['-0', '$lockPid']);
      return result.exitCode != 0;
    } catch (_) {
      return true;
    }
  }
}
