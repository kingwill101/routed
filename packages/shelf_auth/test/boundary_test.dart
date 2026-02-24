import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('shelf_auth does not import routed packages', () async {
    final routedImportPattern = RegExp(
      r"^(import|export)\\s+'package:routed/",
      multiLine: true,
    );

    final libDir = Directory('lib');
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
