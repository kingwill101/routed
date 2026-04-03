import 'dart:io';

import 'package:test/test.dart';

Directory _resolveLibDir() {
  const candidates = <String>[
    'lib',
    'packages/server_data/lib',
  ];
  for (final path in candidates) {
    final directory = Directory(path);
    if (directory.existsSync()) {
      return directory;
    }
  }
  throw StateError(
    'Unable to locate server_data lib directory from ${Directory.current.path}',
  );
}

void main() {
  test('server_data does not import routed packages', () async {
    final libDir = _resolveLibDir();
    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final content = await file.readAsString();
      expect(
        content.contains("package:routed/"),
        isFalse,
        reason: 'Forbidden routed import in ${file.path}',
      );
      expect(
        content.contains("package:routed_auth/"),
        isFalse,
        reason: 'Forbidden routed_auth import in ${file.path}',
      );
    }
  });
}
