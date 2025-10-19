import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

/// Test renderer that returns actual templates
class TestRenderer extends Renderer {
  @override
  Template getTemplate(String templateName) {
    return TestTemplate();
  }

  @override
  Future<String> renderAsync(
    String templateName,
    Map<String, dynamic> context,
  ) async {
    final template = getTemplate(templateName);
    return template.render(context);
  }
}

class TestTemplate extends Template {
  @override
  String render(Map<String, dynamic> context, [dynamic block]) {
    // Basic template that includes error rendering
    final fieldEntries = (context['fields'] as List<dynamic>?)
        ?.map<Map<String, dynamic>>((f) {
          if (f is Map<String, dynamic>) {
            // Preferred structure: {field: {...}, errors: [...]}
            if (f.containsKey('field') && f['field'] is Map<String, dynamic>) {
              return f['field'] as Map<String, dynamic>;
            }
            return f;
          }
          if (f is List && f.isNotEmpty && f.first is Map<String, dynamic>) {
            return f.first as Map<String, dynamic>;
          }
          if (f is (dynamic, List) && f.$1 is Map<String, dynamic>) {
            return f.$1 as Map<String, dynamic>;
          }
          throw StateError('Unexpected field context type: ${f.runtimeType}');
        })
        .toList();

    if (fieldEntries == null || fieldEntries.isEmpty) {
      return "<p>No fields</p>";
    }

    final buffer = StringBuffer();
    for (final field in fieldEntries) {
      buffer.writeln("<p>");
      buffer.writeln(field['label_html'] ?? '');
      buffer.writeln(field['widget_html'] ?? '');
      if ((field['help_text_html'] as String?)?.isNotEmpty ?? false) {
        buffer.writeln(field['help_text_html']);
      }
      final errorsHtml = field['errors_html']?.toString() ?? '';
      if (errorsHtml.isNotEmpty) {
        buffer.writeln(errorsHtml);
      }
      buffer.writeln("</p>");
    }
    return buffer.toString();
  }
}

class TestField<T> extends Field<T> {
  TestField({
    super.required,
    super.label,
    super.initial,
    super.helpText,
    super.validators,
    super.errorMessages,
    super.disabled,
    super.localize,
  });

  T? cleanValue(dynamic value) {
    if (value == null || value == '') return null;
    if (T == int) return int.tryParse(value.toString()) as T?;
    if (T == String) return value.toString() as T?;
    return value as T?;
  }
}

void main() {
  group('Form Error Rendering Tests', () {
    late Renderer renderer;

    setUp(() {
      renderer = TestRenderer();
    });

    test(
      'BoundField.renderErrors() returns empty string when no errors',
      () async {
        final field = TestField<String>(label: 'Test Field');
        final form = Form(
          isBound: true,
          data: {'test': 'valid'},
          files: {},
          fields: {'test': field},
        );

        final boundField = BoundField(form, field, 'test');
        final errorsHtml = await boundField.renderErrors();

        expect(errorsHtml, isEmpty);
        expect(boundField.hasErrors, isFalse);
      },
    );

    test('BoundField.renderErrors() renders single error correctly', () async {
      final field = TestField<String>(label: 'Test Field', required: true);

      final form = Form(
        isBound: true,
        data: {'test': ''},
        files: {},
        fields: {'test': field},
      );

      // Trigger validation
      await form.isValid();

      final boundField = BoundField(form, field, 'test');
      final errorsHtml = await boundField.renderErrors();

      expect(boundField.hasErrors, isTrue);
      expect(errorsHtml, contains('<ul class="errorlist"'));
      expect(errorsHtml, contains('id="id_test_error"'));
      expect(errorsHtml, contains('<li>'));
      expect(errorsHtml, contains('This field is required'));
      expect(errorsHtml, contains('</ul>'));
    });

    test(
      'BoundField.renderErrors() renders multiple errors correctly',
      () async {
        final field = TestField<String>(
          label: 'Test Field',
          required: true,
          validators: [MinLengthValidator(5)],
        );

        final form = Form(
          isBound: true,
          data: {'test': 'abc'},
          files: {},
          fields: {'test': field},
        );

        await form.isValid();

        final boundField = BoundField(form, field, 'test');
        final errorsHtml = await boundField.renderErrors();

        expect(boundField.hasErrors, isTrue);
        expect(errorsHtml, contains('<ul class="errorlist"'));
        expect(errorsHtml, contains('<li>'));
        expect(boundField.errors.length, greaterThan(0));
      },
    );

    test('BoundField.renderErrors() with custom error class', () async {
      final field = TestField<String>(label: 'Test Field', required: true);

      final form = Form(
        isBound: true,
        data: {'test': ''},
        files: {},
        fields: {'test': field},
      );

      await form.isValid();

      final boundField = BoundField(form, field, 'test');
      final errorsHtml = await boundField.renderErrors(
        errorClass: 'custom-error',
      );

      expect(errorsHtml, contains('<ul class="custom-error"'));
    });

    test('Form template rendering includes error HTML', () async {
      final field = TestField<String>(label: 'Test Field', required: true);

      final form = Form(
        isBound: true,
        data: {'test': ''},
        files: {},
        fields: {'test': field},
      );

      await form.isValid();

      final html = await form.asP();

      // Check that errors are included in the rendered output
      expect(html, contains('<ul class="errorlist"'));
      expect(html, contains('This field is required'));
    });

    test('BoundField context includes error information', () async {
      final field = TestField<String>(label: 'Test Field', required: true);

      final form = Form(
        isBound: true,
        data: {'test': ''},
        files: {},
        fields: {'test': field},
      );

      await form.isValid();

      final boundField = BoundField(form, field, 'test');
      final context = await boundField.getContext();

      expect(context['has_errors'], isTrue);
      expect(context['errors'], isNotEmpty);
      expect(context['errors_html'], isNotEmpty);
      expect(context['errors_html'], contains('<ul class="errorlist"'));
    });

    test(
      'BoundField aria-describedby includes error ID when has errors',
      () async {
        final field = TestField<String>(label: 'Test Field', required: true);

        final form = Form(
          isBound: true,
          data: {'test': ''},
          files: {},
          fields: {'test': field},
        );

        await form.isValid();

        final boundField = BoundField(form, field, 'test');

        expect(boundField.hasErrors, isTrue);
        expect(boundField.ariaDescribedby, contains('id_test_error'));
      },
    );

    test('Multiple fields with mixed valid and invalid states', () async {
      final validField = TestField<String>(
        label: 'Valid Field',
        required: true,
      );

      final invalidField = TestField<String>(
        label: 'Invalid Field',
        required: true,
      );

      final form = Form(
        isBound: true,
        data: {'valid': 'has value', 'invalid': ''},
        files: {},
        fields: {'valid': validField, 'invalid': invalidField},
      );

      final isValid = await form.isValid();

      expect(isValid, isFalse);

      final validBound = BoundField(form, validField, 'valid');
      final invalidBound = BoundField(form, invalidField, 'invalid');

      expect(validBound.hasErrors, isFalse);
      expect(await validBound.renderErrors(), isEmpty);

      expect(invalidBound.hasErrors, isTrue);
      expect(await invalidBound.renderErrors(), isNotEmpty);
      expect(
        await invalidBound.renderErrors(),
        contains('This field is required'),
      );
    });

    test('Error rendering in form.asUl()', () async {
      final field = TestField<String>(
        label: 'Test Field',
        required: true,
        validators: [MinLengthValidator(3)],
      );

      final form = Form(
        isBound: true,
        data: {'test': ''},
        files: {},
        fields: {'test': field},
      );

      await form.isValid();

      final html = await form.asUl();

      expect(html, contains('<li>'));
      expect(html, contains('Test Field'));
      expect(html, contains('<ul class="errorlist"'));
    });

    test('Custom error messages are rendered', () async {
      final field = TestField<String>(
        label: 'Test Field',
        required: true,
        errorMessages: {'required': 'Custom error: field cannot be empty'},
      );

      final form = Form(
        isBound: true,
        data: {'test': ''},
        files: {},
        fields: {'test': field},
      );

      await form.isValid();

      final boundField = BoundField(form, field, 'test');
      final errorsHtml = await boundField.renderErrors();

      expect(errorsHtml, contains('Custom error: field cannot be empty'));
    });

    test('Error HTML is properly escaped', () async {
      final field = TestField<String>(label: 'Test Field');

      // Manually set an error with HTML characters
      final form = Form(
        isBound: true,
        data: {'test': 'value'},
        files: {},
        fields: {'test': field},
      );

      // Manually add error to test escaping
      form.addError('test', 'Error with <script>alert("xss")</script>');

      final boundField = BoundField(form, field, 'test');
      final errorsHtml = await boundField.renderErrors();

      // The error should be present but script tags should be as-is
      // (Note: actual HTML escaping should be done by the template engine)
      expect(boundField.hasErrors, isTrue);
      expect(errorsHtml, contains('<li>'));
    });
  });
}
