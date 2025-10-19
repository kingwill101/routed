import 'dart:io';

import 'package:class_view/class_view.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

// Helper function to check for partial error message
Matcher containsErrorMessage(String message) {
  return predicate<ValidationError>(
    (error) => error.toString().contains(message),
    'contains error message "$message"',
  );
}

void main() {
  late Directory tempDir;
  late String testDirPath;

  setUp(() async {
    // Create a temporary directory for test files
    tempDir = await Directory.systemTemp.createTemp('file_path_field_test_');
    testDirPath = tempDir.path;

    // Create test directory structure
    await Directory('$testDirPath/c').create();
    await Directory('$testDirPath/c/f').create();
    await Directory('$testDirPath/h').create();
    await Directory('$testDirPath/j').create();

    // Create test files
    await File('$testDirPath/__init__.py').writeAsString('');
    await File('$testDirPath/a.py').writeAsString('');
    await File('$testDirPath/ab.py').writeAsString('');
    await File('$testDirPath/b.py').writeAsString('');
    await File('$testDirPath/README').writeAsString('');
    await File('$testDirPath/c/__init__.py').writeAsString('');
    await File('$testDirPath/c/d.py').writeAsString('');
    await File('$testDirPath/c/e.py').writeAsString('');
    await File('$testDirPath/c/f/__init__.py').writeAsString('');
    await File('$testDirPath/c/f/g.py').writeAsString('');
    await File('$testDirPath/h/__init__.py').writeAsString('');
    await File('$testDirPath/j/__init__.py').writeAsString('');
  });

  tearDown(() async {
    // Clean up temporary directory
    await tempDir.delete(recursive: true);
  });

  test('debug error messages', () {
    final field = FilePathField(path: testDirPath);

    try {
      field.toDart('a.py');
      fail('Expected ValidationError');
    } catch (e) {
      // ignore: unnecessary_brace_in_string_interps
      print('Debug - Error for invalid file path: ${e}');
    }
  });

  test('nonexistent path', () {
    expect(
      () => FilePathField(path: 'nonexistent'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('no options', () {
    final field = FilePathField(path: testDirPath);
    final choices = field.choices
        .map((c) => [path.relative(c[0] as String, from: testDirPath), c[1]])
        .toList();

    expect(
      choices,
      containsAll([
        ['README', 'README'],
        ['__init__.py', '__init__.py'],
        ['a.py', 'a.py'],
        ['ab.py', 'ab.py'],
        ['b.py', 'b.py'],
      ]),
    );
  });

  test('clean', () {
    final field = FilePathField(path: testDirPath);

    expect(
      () => field.toDart('a.py'),
      throwsA(containsErrorMessage('a.py is not one of the available choices')),
    );

    expect(field.toDart('$testDirPath/a.py'), equals('$testDirPath/a.py'));
  });

  test('match', () {
    final field = FilePathField(path: testDirPath, match: r'^.*?\.py$');
    final choices = field.choices
        .map((c) => [path.relative(c[0] as String, from: testDirPath), c[1]])
        .toList();

    expect(
      choices,
      containsAll([
        ['__init__.py', '__init__.py'],
        ['a.py', 'a.py'],
        ['ab.py', 'ab.py'],
        ['b.py', 'b.py'],
      ]),
    );

    expect(choices, isNot(contains(['README', 'README'])));
  });

  test('recursive', () {
    final field = FilePathField(
      path: testDirPath,
      recursive: true,
      match: r'^.*?\.py$',
    );
    final choices = field.choices
        .map((c) => [path.relative(c[0] as String, from: testDirPath), c[1]])
        .toList();

    expect(
      choices,
      containsAll([
        ['__init__.py', '__init__.py'],
        ['a.py', 'a.py'],
        ['ab.py', 'ab.py'],
        ['b.py', 'b.py'],
        ['c/__init__.py', 'c/__init__.py'],
        ['c/d.py', 'c/d.py'],
        ['c/e.py', 'c/e.py'],
        ['c/f/__init__.py', 'c/f/__init__.py'],
        ['c/f/g.py', 'c/f/g.py'],
        ['h/__init__.py', 'h/__init__.py'],
        ['j/__init__.py', 'j/__init__.py'],
      ]),
    );
  });

  test('allow folders', () {
    final field = FilePathField(
      path: testDirPath,
      allowFolders: true,
      allowFiles: false,
    );
    final choices = field.choices
        .map((c) => [path.relative(c[0] as String, from: testDirPath), c[1]])
        .toList();

    expect(
      choices,
      containsAll([
        ['c', 'c'],
        ['h', 'h'],
        ['j', 'j'],
      ]),
    );
  });

  test('recursive no folders or files', () {
    final field = FilePathField(
      path: testDirPath,
      recursive: true,
      allowFolders: false,
      allowFiles: false,
    );
    expect(field.choices, isEmpty);
  });

  test('recursive folders without files', () {
    final field = FilePathField(
      path: testDirPath,
      recursive: true,
      allowFolders: true,
      allowFiles: false,
    );
    final choices = field.choices
        .map((c) => [path.relative(c[0] as String, from: testDirPath), c[1]])
        .toList();

    expect(
      choices,
      containsAll([
        ['c', 'c'],
        ['h', 'h'],
        ['j', 'j'],
        ['c/f', 'c/f'],
      ]),
    );
  });
}
