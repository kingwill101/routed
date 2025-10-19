import 'dart:typed_data';

import 'package:class_view/class_view.dart';
import 'package:mockito/annotations.dart';

@GenerateNiceMocks([MockSpec<ViewAdapter>()])
void main() {}

/// Test implementation of FormFile for testing
class TestFormFile extends FormFile {
  TestFormFile({
    required super.name,
    required super.size,
    required super.contentType,
    required super.content,
  });

  /// Create a test file with text content
  factory TestFormFile.fromText(
    String name,
    String text, {
    String? contentType,
  }) {
    final content = Uint8List.fromList(text.codeUnits);
    return TestFormFile(
      name: name,
      size: content.length,
      contentType: contentType ?? 'text/plain',
      content: content,
    );
  }

  /// Create a test image file
  factory TestFormFile.image(String name, {int size = 1024}) {
    final content = Uint8List(size);
    // Fill with some dummy image data
    for (int i = 0; i < size; i++) {
      content[i] = i % 256;
    }
    return TestFormFile(
      name: name,
      size: size,
      contentType: 'image/jpeg',
      content: content,
    );
  }

  /// Create an empty file
  factory TestFormFile.empty(String name) {
    return TestFormFile(
      name: name,
      size: 0,
      contentType: 'application/octet-stream',
      content: Uint8List(0),
    );
  }
}
