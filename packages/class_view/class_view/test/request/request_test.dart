import 'dart:typed_data';

import 'package:class_view/class_view.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../shared/mock_adapter.dart';
import '../shared/mock_adapter.mocks.dart';

void main() {
  group('Request', () {
    test('parameter access', () async {
      final adapter = MockViewAdapter();
      when(adapter.getParam('name')).thenAnswer((_) async => 'John');
      when(adapter.getParam('age')).thenAnswer((_) async => '25');
      when(adapter.getParam('missing')).thenAnswer((_) async => null);
      when(
        adapter.getQueryParams(),
      ).thenAnswer((_) async => {'filter': 'active'});
      when(adapter.getRouteParams()).thenAnswer((_) async => {'id': '123'});

      final request = Request(adapter);

      expect(await request.get('name'), equals('John'));
      expect(await request.input('age'), equals('25'));
      expect(await request.get('missing', 'default'), equals('default'));
      expect(await request.query('filter'), equals('active'));
      expect(await request.route('id'), equals('123'));
    });

    test('data collection', () async {
      final adapter = MockViewAdapter();
      when(adapter.getParams()).thenAnswer(
        (_) async => {'name': 'John', 'age': '25', 'email': 'john@example.com'},
      );
      when(adapter.getParam('name')).thenAnswer((_) async => 'John');
      when(adapter.getParam('age')).thenAnswer((_) async => '25');
      when(
        adapter.getParam('email'),
      ).thenAnswer((_) async => 'john@example.com');

      final request = Request(adapter);

      final all = await request.all();
      expect(all['name'], equals('John'));
      expect(all['age'], equals('25'));
      expect(all['email'], equals('john@example.com'));

      final only = await request.only(['name', 'email']);
      expect(only, hasLength(2));
      expect(only['name'], equals('John'));
      expect(only['email'], equals('john@example.com'));
      expect(only.containsKey('age'), isFalse);

      final except = await request.except(['age']);
      expect(except, hasLength(2));
      expect(except['name'], equals('John'));
      expect(except['email'], equals('john@example.com'));
      expect(except.containsKey('age'), isFalse);
    });

    test('validation helpers', () async {
      final adapter = MockViewAdapter();
      when(adapter.getParam('name')).thenAnswer((_) async => 'John');
      when(adapter.getParam('empty')).thenAnswer((_) async => '');
      when(adapter.getParam('age')).thenAnswer((_) async => '25');
      when(adapter.getParam('missing')).thenAnswer((_) async => null);
      when(adapter.getParam('nothere')).thenAnswer((_) async => null);

      when(
        adapter.getParams(),
      ).thenAnswer((_) async => ({'name': 'John', 'empty': '', 'age': '25'}));

      final request = Request(adapter);

      expect(await request.filled('name'), isTrue);
      expect(await request.filled('empty'), isFalse);
      expect(await request.filled('missing'), isFalse);

      expect(await request.has('name'), isTrue);
      expect(await request.has('empty'), isTrue);
      expect(await request.has('missing'), isFalse);

      expect(await request.missing('name'), isFalse);
      expect(await request.missing('nothere'), isTrue);
    });

    test('request type checking', () async {
      final getAdapter = MockViewAdapter();
      when(getAdapter.getMethod()).thenAnswer((_) async => 'GET');

      final postAdapter = MockViewAdapter();
      when(postAdapter.getMethod()).thenAnswer((_) async => 'POST');

      final ajaxAdapter = MockViewAdapter();
      when(ajaxAdapter.getMethod()).thenAnswer((_) async => 'POST');
      when(
        ajaxAdapter.getHeader('x-requested-with'),
      ).thenAnswer((_) async => 'XMLHttpRequest');

      final getRequest = Request(getAdapter);
      final postRequest = Request(postAdapter);
      final ajaxRequest = Request(ajaxAdapter);

      // Confirm getMethod() returns 'GET'
      expect(await getRequest.getMethod(), equals('GET'));

      expect(await getRequest.isGet, isTrue);
      expect(await getRequest.isPost, isFalse);
      expect(await getRequest.isMethod('GET'), isTrue);

      expect(await postRequest.isPost, isTrue);
      expect(await postRequest.isGet, isFalse);
      expect(await postRequest.ajax(), isFalse);

      expect(await ajaxRequest.ajax(), isTrue);
    });

    test('header access', () async {
      final adapter = MockViewAdapter();
      when(
        adapter.getHeader('authorization'),
      ).thenAnswer((_) async => 'Bearer token123');
      when(
        adapter.getHeader('user-agent'),
      ).thenAnswer((_) async => 'TestAgent/1.0');
      when(
        adapter.getHeader('accept'),
      ).thenAnswer((_) async => 'application/json');

      final request = Request(adapter);

      expect(await request.header('authorization'), equals('Bearer token123'));
      expect(await request.bearerToken(), equals('token123'));
      expect(await request.userAgent(), equals('TestAgent/1.0'));
      expect(await request.expectsJson(), isTrue);
    });

    group('file operations', () {
      test('hasFile with no files', () async {
        final adapter = MockViewAdapter();
        when(adapter.hasFile('avatar')).thenAnswer((_) async => false);
        when(adapter.getUploadedFile('avatar')).thenAnswer((_) async => null);
        when(adapter.getUploadedFiles()).thenAnswer((_) async => []);

        final request = Request(adapter);

        expect(await request.hasFile('avatar'), isFalse);
        expect(await request.file('avatar'), isNull);
        expect(await request.files(), isEmpty);
      });

      test('hasFile with files', () async {
        final adapter = MockViewAdapter();
        when(adapter.hasFile('document')).thenAnswer((_) async => true);
        when(adapter.hasFile('avatar')).thenAnswer((_) async => true);
        when(adapter.hasFile('missing')).thenAnswer((_) async => false);

        final request = Request(adapter);

        expect(await request.hasFile('document'), isTrue);
        expect(await request.hasFile('avatar'), isTrue);
        expect(await request.hasFile('missing'), isFalse);
      });

      test('file retrieval', () async {
        final testFile = TestFormFile.fromText('test.txt', 'Hello World');
        final imageFile = TestFormFile.image('avatar.jpg', size: 2048);

        final adapter = MockViewAdapter();
        when(
          adapter.getUploadedFile('document'),
        ).thenAnswer((_) async => testFile);
        when(
          adapter.getUploadedFile('avatar'),
        ).thenAnswer((_) async => imageFile);
        when(adapter.getUploadedFile('missing')).thenAnswer((_) async => null);

        final request = Request(adapter);

        final document = await request.file('document');
        expect(document, isNotNull);
        expect(document!.name, equals('test.txt'));
        expect(document.size, equals(11));
        expect(document.contentType, equals('text/plain'));

        final avatar = await request.file('avatar');
        expect(avatar, isNotNull);
        expect(avatar!.name, equals('avatar.jpg'));
        expect(avatar.size, equals(2048));
        expect(avatar.contentType, equals('image/jpeg'));

        final missing = await request.file('missing');
        expect(missing, isNull);
      });

      test('files collection', () async {
        final textFile = TestFormFile.fromText('doc1.txt', 'Document 1');
        final imageFile = TestFormFile.image('image1.jpg');
        final emptyFile = TestFormFile.empty('empty.bin');

        final adapter = MockViewAdapter();
        when(
          adapter.getUploadedFiles(),
        ).thenAnswer((_) async => [textFile, imageFile, emptyFile]);

        final request = Request(adapter);

        final allFiles = await request.files();
        expect(allFiles, hasLength(3));

        final fileNames = allFiles.map((f) => f.name).toList();
        expect(fileNames, contains('doc1.txt'));
        expect(fileNames, contains('image1.jpg'));
        expect(fileNames, contains('empty.bin'));
      });

      test('file content validation', () async {
        final textFile = TestFormFile.fromText('test.txt', 'Hello World!');

        final adapter = MockViewAdapter();
        when(
          adapter.getUploadedFile('document'),
        ).thenAnswer((_) async => textFile);

        final request = Request(adapter);

        final file = await request.file('document');
        expect(file, isNotNull);
        expect(file!.content.length, equals(12)); // "Hello World!" length

        // Convert content back to string
        final content = String.fromCharCodes(file.content);
        expect(content, equals('Hello World!'));
      });

      test('empty file handling', () async {
        final emptyFile = TestFormFile.empty('empty.txt');

        final adapter = MockViewAdapter();
        when(
          adapter.getUploadedFile('empty'),
        ).thenAnswer((_) async => emptyFile);

        final request = Request(adapter);

        final file = await request.file('empty');
        expect(file, isNotNull);
        expect(file!.name, equals('empty.txt'));
        expect(file.size, equals(0));
        expect(file.content.isEmpty, isTrue);
      });

      test('form data with files', () async {
        final testFile = TestFormFile.fromText(
          'upload.txt',
          'Uploaded content',
        );

        final adapter = MockViewAdapter();
        when(
          adapter.getParam('title'),
        ).thenAnswer((_) async => 'File Upload Test');
        when(
          adapter.getParam('description'),
        ).thenAnswer((_) async => 'Testing file upload with form data');
        when(adapter.hasFile('attachment')).thenAnswer((_) async => true);
        when(
          adapter.getUploadedFile('attachment'),
        ).thenAnswer((_) async => testFile);

        final request = Request(adapter);

        // Test combined form data and file access
        expect(await request.get('title'), equals('File Upload Test'));
        expect(
          await request.get('description'),
          equals('Testing file upload with form data'),
        );
        expect(await request.hasFile('attachment'), isTrue);

        final file = await request.file('attachment');
        expect(file!.name, equals('upload.txt'));
        expect(String.fromCharCodes(file.content), equals('Uploaded content'));
      });
    });

    group('advanced scenarios', () {
      test('large file handling', () async {
        final largeFile = TestFormFile.image(
          'large_image.jpg',
          size: 1024 * 1024,
        ); // 1MB

        final adapter = MockViewAdapter();
        when(
          adapter.getUploadedFile('large_file'),
        ).thenAnswer((_) async => largeFile);

        final request = Request(adapter);

        final file = await request.file('large_file');
        expect(file, isNotNull);
        expect(file!.size, equals(1024 * 1024));
        expect(file.contentType, equals('image/jpeg'));
      });

      test('content type validation', () async {
        final pdfFile = TestFormFile(
          name: 'document.pdf',
          size: 1024,
          contentType: 'application/pdf',
          content: Uint8List.fromList(List.generate(1024, (i) => i % 256)),
        );

        final adapter = MockViewAdapter();
        when(adapter.getUploadedFile('pdf')).thenAnswer((_) async => pdfFile);

        final request = Request(adapter);

        final file = await request.file('pdf');
        expect(file!.contentType, equals('application/pdf'));
        expect(file.name.endsWith('.pdf'), isTrue);
      });
    });
  });
}
