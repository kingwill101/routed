import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('server_data does not import routed packages', () async {
    final libDir = Directory('lib');
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
