import 'dart:io';

import 'package:test/test.dart';

Directory _resolveLibDir() {
  const candidates = <String>[
    'lib',
    'packages/shelf_auth/lib',
  ];
  for (final path in candidates) {
    final directory = Directory(path);
    if (directory.existsSync()) {
      return directory;
    }
  }
  throw StateError(
    'Unable to locate shelf_auth lib directory from ${Directory.current.path}',
  );
}

void main() {
  test('shelf_auth does not import routed packages', () async {
    final routedImportPattern = RegExp(
      r"^(import|export)\s+'package:routed/",
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
    }
  });
}
