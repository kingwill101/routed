import 'dart:io';

import 'package:test/test.dart';

Directory _resolveLibDir() {
  const candidates = <String>[
    'lib',
    'packages/server_auth/lib',
  ];
  for (final path in candidates) {
    final directory = Directory(path);
    if (directory.existsSync()) {
      return directory;
    }
  }
  throw StateError(
    'Unable to locate server_auth lib directory from ${Directory.current.path}',
  );
}

void main() {
  test('server_auth does not import routed packages', () async {
    final routedImportPattern = RegExp(
      r"^(import|export)\s+'package:routed/",
      multiLine: true,
    );
    final routedAuthImportPattern = RegExp(
      r"^(import|export)\s+'package:routed_auth/",
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
        routedImportPattern.hasMatch(content),
        isFalse,
        reason: 'Forbidden routed import in ${file.path}',
      );
      expect(
        routedAuthImportPattern.hasMatch(content),
        isFalse,
        reason: 'Forbidden routed_auth import in ${file.path}',
      );
    }
  });
}
