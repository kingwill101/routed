import 'dart:typed_data';

import 'package:class_view/class_view.dart';
import 'package:class_view_image_field/class_view_image_field.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

class _TestFormFile extends FormFile {
  _TestFormFile({
    required super.name,
    required super.size,
    required super.contentType,
    required super.content,
  });
}

void main() {
  setUp(() {
    ensureImageFieldSupport();
  });

  test('ImageField decodes valid image', () async {
    final field = ImageField();
    final image = img.Image(width: 1, height: 1);
    final data = Uint8List.fromList(img.encodePng(image));

    final file = _TestFormFile(
      name: 'tiny.png',
      size: data.length,
      contentType: 'image/png',
      content: data,
    );

    final cleaned = await field.clean(file);
    expect(cleaned, isNotNull);
    expect(cleaned!.image, isA<img.Image>());
  });

  test('ImageField enforces extension list', () async {
    final field = ImageField();
    final image = img.Image(width: 1, height: 1);
    final data = Uint8List.fromList(img.encodePng(image));

    final file = _TestFormFile(
      name: 'tiny.txt',
      size: data.length,
      contentType: 'text/plain',
      content: data,
    );

    await expectLater(
      () => field.clean(file),
      throwsA(
        isA<ValidationError>().having(
          (error) => error.errors['invalid_extension']?.join(' '),
          'invalid_extension',
          contains('txt'),
        ),
      ),
    );
  });
}
