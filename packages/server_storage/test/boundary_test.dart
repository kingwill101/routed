import 'dart:io';

import 'package:test/test.dart';

Directory _resolveLibDir() {
  const candidates = <String>['lib', 'packages/server_storage/lib'];
  for (final path in candidates) {
    final directory = Directory(path);
    if (directory.existsSync()) {
      return directory;
    }
  }
  throw StateError(
    'Unable to locate server_storage lib directory from '
    '${Directory.current.path}',
  );
}

void main() {
  test('server_storage does not import routed packages', () async {
    final routedImportPattern = RegExp(
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
        routedImportPattern.hasMatch(content),
        isFalse,
        reason: 'Forbidden routed import in ${file.path}',
      );
    }
  });

  test('storage-backed static handler does not import dart:io', () async {
    final libDir = _resolveLibDir();
    final handler = File('${libDir.path}/src/storage_file_handler.dart');
    final content = await handler.readAsString();

    expect(
      RegExp(r"^import\s+'dart:io';", multiLine: true).hasMatch(content),
      isFalse,
      reason: 'StorageFileHandler must remain portable to Worker hosts.',
    );
  });
}
