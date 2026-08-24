import 'dart:io';

import 'package:test/test.dart';

Directory _resolveLibDir() {
  const candidates = <String>['lib', 'packages/server_sessions/lib'];
  for (final path in candidates) {
    final directory = Directory(path);
    if (directory.existsSync()) {
      return directory;
    }
  }
  throw StateError(
    'Unable to locate server_sessions lib directory from '
    '${Directory.current.path}',
  );
}

void main() {
  test('server_sessions lib does not import package:routed', () async {
    final pattern = RegExp(
      r"^(import|export)\s+'package:routed",
      multiLine: true,
    );
    final libDir = _resolveLibDir();
    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final content = await file.readAsString();
      expect(
        pattern.hasMatch(content),
        isFalse,
        reason: 'Forbidden routed import in ${file.path}',
      );
    }
  });
}
