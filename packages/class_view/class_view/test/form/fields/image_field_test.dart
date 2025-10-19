import 'dart:typed_data';

import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

void main() {
  tearDown(resetImageFieldBuilder);

  group('ImageField registration', () {
    test('throws helpful guidance when extension is missing', () {
      expect(
        () => ImageField(),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('class_view_image_field'),
          ),
        ),
      );
    });

    test('custom builder enables construction', () async {
      var invoked = false;

      registerImageFieldBuilder(({
        String? name,
        int? maxLength,
        int? maxSize,
        List<String>? allowedExtensions,
        Widget? widget,
        Widget? hiddenWidget,
        List<Validator<ImageFormFile>>? validators,
        bool required = true,
        String? label,
        ImageFormFile? initial,
        String? helpText,
        Map<String, String>? errorMessages,
        bool showHiddenInitial = false,
        bool localize = false,
        bool disabled = false,
        String? labelSuffix,
        String? templateName,
      }) {
        invoked = true;
        return _FakeImageField(
          name: name,
          maxLength: maxLength,
          maxSize: maxSize,
          allowedExtensions: allowedExtensions,
          widget: widget,
          hiddenWidget: hiddenWidget,
          validators: validators,
          required: required,
          label: label,
          initial: initial,
          helpText: helpText,
          errorMessages: errorMessages,
          showHiddenInitial: showHiddenInitial,
          localize: localize,
          disabled: disabled,
          labelSuffix: labelSuffix,
          templateName: templateName,
        );
      });

      final field = ImageField();
      expect(invoked, isTrue);

      final cleaned = await field.clean(
        ImageFormFile(
          name: 'noop.png',
          contentType: 'image/png',
          size: 4,
          content: Uint8List(0),
        ),
      );

      expect(cleaned, isNotNull);
      expect(cleaned?.image, equals('decoded'));
    });
  });
}

class _FakeImageField extends ImageField {
  _FakeImageField({
    super.name,
    super.maxLength,
    super.maxSize,
    super.allowedExtensions,
    super.widget,
    super.hiddenWidget,
    super.validators,
    super.required,
    super.label,
    super.initial,
    super.helpText,
    super.errorMessages,
    super.showHiddenInitial,
    super.localize,
    super.disabled,
    super.labelSuffix,
    super.templateName,
  }) : super.protected();

  @override
  Future<ImageFormFile?> clean(dynamic value) async {
    if (value is ImageFormFile) {
      return ImageFormFile(
        name: value.name,
        contentType: value.contentType,
        size: value.size,
        content: value.content,
        image: 'decoded',
      );
    }
    return null;
  }
}
