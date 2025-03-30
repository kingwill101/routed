import 'dart:io';

import 'package:path/path.dart' as path;

class InstallationLock {
  final String lockDir;
  final String lockFile;
  File? _lock;

  InstallationLock(this.lockDir)
      : lockFile = path.join(lockDir, 'install.lock');

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

  Future<void> release() async {
    if (_lock != null && await _lock!.exists()) {
      await _lock!.delete();
    }
  }

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
