import 'dart:typed_data';

import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

// Helper function to check for partial error message
Matcher containsErrorMessage(String message) {
  return predicate<ValidationError>(
    (error) => error.toString().contains(message),
    'contains error message "$message"',
  );
}

class UploadedFile extends FormFile {
  UploadedFile({
    required super.name,
    required super.contentType,
    required super.size,
    required super.content,
  });
}

void main() {
  group('FileField', () {
    test('basic field validation', () {
      final field = FileField<UploadedFile>();

      // Test empty string
      expect(
        () => field.toDart(''),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errors['required']![0],
            'error message',
            'This field is required.',
          ),
        ),
      );

      // Test null
      expect(
        () => field.toDart(null),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errors['required']![0],
            'error message',
            'This field is required.',
          ),
        ),
      );

      // Test empty file name
      final emptyNameFile = UploadedFile(
        name: '',
        contentType: 'application/octet-stream',
        size: 0,
        content: Uint8List(0),
      );
      expect(
        () => field.toDart(emptyNameFile),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errors['invalid']![0],
            'error message',
            'No file was submitted. Check the encoding type on the form.',
          ),
        ),
      );

      // Test empty file content
      final emptyFile = UploadedFile(
        name: 'test.txt',
        contentType: 'application/octet-stream',
        size: 0,
        content: Uint8List(0),
      );
      expect(
        () => field.toDart(emptyFile),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errors['empty']![0],
            'error message',
            'The submitted file is empty.',
          ),
        ),
      );

      // Test valid file
      final validFile = UploadedFile(
        name: 'test.txt',
        contentType: 'application/octet-stream',
        size: 5,
        content: Uint8List.fromList([1, 2, 3, 4, 5]),
      );
      expect(field.toDart(validFile), equals(validFile));

      // Test non-file content
      expect(
        () => field.toDart('some content that is not a file'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errors['invalid']![0],
            'error message',
            'No file was submitted. Check the encoding type on the form.',
          ),
        ),
      );

      // Test file with Unicode name
      final unicodeFile = UploadedFile(
        name: '我隻氣墊船裝滿晒鱔.txt',
        contentType: 'application/octet-stream',
        size: 3,
        content: Uint8List.fromList([1, 2, 3]),
      );
      expect(field.toDart(unicodeFile), equals(unicodeFile));
    });

    test('max length validation', () {
      final field = FileField<UploadedFile>(maxLength: 5);

      // Test filename too long
      final longNameFile = UploadedFile(
        name: 'test_maxlength.txt',
        contentType: 'application/octet-stream',
        size: 18,
        content: Uint8List.fromList([1, 2, 3]),
      );
      expect(
        () => field.toDart(longNameFile),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errors['max_length']![0],
            'error message',
            'Ensure this filename has at most 5 characters (it has 18).',
          ),
        ),
      );

      // Test valid filename length
      final validFile = UploadedFile(
        name: 'test',
        contentType: 'application/octet-stream',
        size: 3,
        content: Uint8List.fromList([1, 2, 3]),
      );
      expect(field.toDart(validFile), equals(validFile));
    });

    test('allow empty file', () {
      final field = FileField<UploadedFile>(allowEmptyFile: true);

      // Empty file should be allowed
      final emptyFile = UploadedFile(
        name: 'empty.txt',
        contentType: 'application/octet-stream',
        size: 0,
        content: Uint8List(0),
      );
      expect(field.toDart(emptyFile), equals(emptyFile));
    });

    test('has changed', () {
      final field = FileField<UploadedFile>();

      // No file was uploaded and no initial data
      expect(field.hasChanged('', null), isFalse);

      // A file was uploaded and no initial data
      final newFile = UploadedFile(
        name: 'resume.txt',
        contentType: 'application/octet-stream',
        size: 3,
        content: Uint8List.fromList([1, 2, 3]),
      );
      expect(field.hasChanged('', newFile), isTrue);

      // A file was not uploaded, but there is initial data
      expect(field.hasChanged('resume.txt', null), isFalse);

      // A file was uploaded and there is initial data
      expect(field.hasChanged('resume.txt', newFile), isTrue);
    });

    test('disabled field has changed', () {
      final field = FileField<UploadedFile>(disabled: true);
      expect(field.hasChanged('x', 'y'), isFalse);
    });

    test('widget type', () {
      final field = FileField<UploadedFile>();
      expect(field.widget, isA<FileInput>());
    });

    test('non-required field', () {
      final field = FileField<UploadedFile>(required: false);

      // Empty values should be allowed
      expect(field.toDart(''), isNull);
      expect(field.toDart(null), isNull);

      // Valid file should still work
      final validFile = UploadedFile(
        name: 'test.txt',
        contentType: 'application/octet-stream',
        size: 3,
        content: Uint8List.fromList([1, 2, 3]),
      );
      expect(field.toDart(validFile), equals(validFile));
    });

    test('max size validation', () {
      final field = FileField<UploadedFile>(maxSize: 5);

      // Test file too large
      final largeFile = UploadedFile(
        name: 'large.txt',
        contentType: 'application/octet-stream',
        size: 6,
        content: Uint8List.fromList([1, 2, 3, 4, 5, 6]),
      );
      expect(
        () => field.toDart(largeFile),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errors['max_size']![0],
            'error message',
            'File size exceeds maximum allowed size.',
          ),
        ),
      );

      // Test valid file size
      final validFile = UploadedFile(
        name: 'small.txt',
        contentType: 'application/octet-stream',
        size: 3,
        content: Uint8List.fromList([1, 2, 3]),
      );
      expect(field.toDart(validFile), equals(validFile));
    });

    test('content type validation', () {
      final field = FileField<UploadedFile>(
        allowedTypes: ['text/plain', 'application/pdf'],
      );

      // Test invalid content type
      final invalidFile = UploadedFile(
        name: 'test.jpg',
        contentType: 'image/jpeg',
        size: 3,
        content: Uint8List.fromList([1, 2, 3]),
      );
      expect(
        () => field.toDart(invalidFile),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errors['content_type']![0],
            'error message',
            'Files of type image/jpeg are not supported.',
          ),
        ),
      );

      // Test valid content type
      final validFile = UploadedFile(
        name: 'test.txt',
        contentType: 'text/plain',
        size: 3,
        content: Uint8List.fromList([1, 2, 3]),
      );
      expect(field.toDart(validFile), equals(validFile));

      final validPdfFile = UploadedFile(
        name: 'test.pdf',
        contentType: 'application/pdf',
        size: 3,
        content: Uint8List.fromList([1, 2, 3]),
      );
      expect(field.toDart(validPdfFile), equals(validPdfFile));
    });
  });

  group('MultipleFileField', () {
    // Debug test to help diagnose issues with error messages
    test('debug multiple file error messages', () {
      final field = MultipleFileField<UploadedFile>();
      final files = [
        UploadedFile(
          name: 'empty.txt',
          contentType: 'application/octet-stream',
          size: 0,
          content: Uint8List(0),
        ),
      ];

      try {
        field.toMultipleDart(files);
        fail('Expected ValidationError');
      } catch (e) {
        print('Debug - Error for empty file: $e');
      }
    });

    test('multiple file validation', () {
      final field = MultipleFileField<UploadedFile>();
      final files = [
        UploadedFile(
          name: 'file1.txt',
          contentType: 'application/octet-stream',
          size: 3,
          content: Uint8List.fromList([1, 2, 3]),
        ),
        UploadedFile(
          name: 'file2.txt',
          contentType: 'application/octet-stream',
          size: 3,
          content: Uint8List.fromList([4, 5, 6]),
        ),
      ];
      expect(field.toMultipleDart(files), equals(files));
    });

    test('multiple file with empty files', () {
      final field = MultipleFileField<UploadedFile>();
      final files = [
        UploadedFile(
          name: 'empty.txt',
          contentType: 'application/octet-stream',
          size: 0,
          content: Uint8List(0),
        ),
        UploadedFile(
          name: 'nonempty.txt',
          contentType: 'application/octet-stream',
          size: 3,
          content: Uint8List.fromList([1, 2, 3]),
        ),
      ];

      // Test with empty file first
      expect(
        () => field.toMultipleDart(files),
        throwsA(containsErrorMessage('The submitted file is empty')),
      );

      // Test with empty file last
      expect(
        () => field.toMultipleDart(files.reversed.toList()),
        throwsA(containsErrorMessage('The submitted file is empty')),
      );
    });

    test('multiple file with content type validation', () {
      final field = MultipleFileField<UploadedFile>(
        allowedTypes: ['image/jpeg', 'image/png', 'image/bmp'],
      );

      final validFiles = [
        UploadedFile(
          name: 'image1.jpg',
          contentType: 'image/jpeg',
          size: 3,
          content: Uint8List.fromList([1, 2, 3]),
        ),
        UploadedFile(
          name: 'image2.png',
          contentType: 'image/png',
          size: 3,
          content: Uint8List.fromList([4, 5, 6]),
        ),
        UploadedFile(
          name: 'image3.bmp',
          contentType: 'image/bmp',
          size: 3,
          content: Uint8List.fromList([7, 8, 9]),
        ),
      ];
      expect(field.toMultipleDart(validFiles), equals(validFiles));

      final invalidFiles = [
        UploadedFile(
          name: 'script.sh',
          contentType: 'text/x-shellscript',
          size: 3,
          content: Uint8List.fromList([1, 2, 3]),
        ),
        UploadedFile(
          name: 'image.png',
          contentType: 'image/png',
          size: 3,
          content: Uint8List.fromList([4, 5, 6]),
        ),
      ];
      expect(
        () => field.toMultipleDart(invalidFiles),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errors['content_type']![0],
            'error message',
            'Files of type text/x-shellscript are not supported.',
          ),
        ),
      );
    });
  });
}
