import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

void main() {
  group('BoundField', () {
    late Form form;
    late Field<String> field;
    late BoundField<String> boundField;

    setUp(() {
      field = TestField(label: 'Test Field', helpText: 'This is a test field');

      form = Form(
        isBound: true,
        data: {'test_field': 'test value'},
        files: {},
        fields: {'test_field': field},
      );

      boundField = BoundField<String>(form, field, 'test_field');
    });

    group('Initialization', () {
      test('initializes with correct values', () {
        expect(boundField.name, equals('test_field'));
        expect(boundField.htmlName, equals('test_field'));
        expect(boundField.autoId, equals('id_test_field'));
        expect(boundField.label, equals('Test Field'));
        expect(boundField.helpText, equals('This is a test field'));
        expect(boundField.value, equals('test value'));
      });

      test('handles missing label and help text', () {
        final unlabeledField = TestField();
        final simpleForm = Form(
          isBound: true,
          data: {},
          files: {},
          fields: {'test_field': unlabeledField},
        );
        final simpleBoundField = BoundField<String>(
          simpleForm,
          unlabeledField,
          'test_field',
        );

        expect(
          simpleBoundField.label,
          equals('Test Field'),
        ); // Should convert from snake_case
        expect(simpleBoundField.helpText, isEmpty);
      });

      test('handles prefixed field names', () {
        form = Form(
          isBound: true,
          data: {'prefix-test_field': 'test value'},
          files: {},
          fields: {'test_field': field},
          prefix: 'prefix',
        );
        boundField = BoundField<String>(form, field, 'test_field');

        expect(boundField.htmlName, equals('prefix-test_field'));
      });
    });

    group('Error Handling', () {
      test('handles single error string', () {
        form.addError('test_field', 'Single error');
        expect(boundField.errors, equals(['Single error']));
        expect(boundField.hasErrors, isTrue);
      });

      test('handles multiple errors', () {
        form.errors['test_field'] = ['Error 1', 'Error 2'];
        expect(boundField.errors, equals(['Error 1', 'Error 2']));
        expect(boundField.hasErrors, isTrue);
      });

      test('handles no errors', () {
        expect(boundField.errors, isEmpty);
        expect(boundField.hasErrors, isFalse);
      });

      test('renders errors with custom attributes', () async {
        form.addError('test_field', 'Test error');
        final errors = await boundField.renderErrors(
          errorClass: 'error-message',
        );
        expect(errors, contains('class="error-message"'));
        expect(errors, contains('<ul'));
        expect(errors, contains('<li>Test error</li>'));
        expect(errors, contains('</ul>'));
      });
    });

    group('Widget Rendering', () {
      test('renders as text input', () async {
        final rendered = await boundField.asWidget(
          widget: TextInput(attrs: {'class': 'text-input'}),
        );
        expect(rendered, contains('type="text"'));
        expect(rendered, contains('class="text-input"'));
        expect(rendered, contains('value="test value"'));
      });

      test('renders as textarea', () async {
        final rendered = await boundField.asWidget(
          widget: Textarea(attrs: {'rows': '5'}),
        );
        expect(rendered, contains('<textarea'));
        expect(rendered, contains('rows="5"'));
        expect(rendered, contains('>test value</textarea>'));
      });

      test('renders as hidden input', () async {
        final rendered = await boundField.asHidden();
        expect(rendered, contains('type="hidden"'));
        expect(rendered, contains('value="test value"'));
      });

      test('renders with initial value', () async {
        form = Form(
          isBound: true,
          data: {'test_field_initial': 'initial value'},
          files: {},
          fields: {'test_field': field},
        );
        boundField = BoundField<String>(form, field, 'test_field');

        final rendered = await boundField.asWidget(onlyInitial: true);
        expect(rendered, contains('value="initial value"'));
        expect(rendered, contains('id="id_test_field_initial"'));
      });

      test('handles localized fields', () async {
        field = TestField(localize: true);
        boundField = BoundField<String>(form, field, 'test_field');
        await boundField.asWidget();
        expect(field.widget.isLocalized, isTrue);
      });

      test('handles multi-value fields', () async {
        final multiField = MultiValueTestField(
          fields: [TestField(required: true), TestField(required: false)],
        );
        form = Form(
          isBound: true,
          data: {
            'test_field': ['value1', 'value2'],
          },
          files: {},
          fields: {'test_field': multiField},
        );
        final multiBoundField = BoundField<List<String>>(
          form,
          multiField,
          'test_field',
        );

        expect(multiBoundField.value, equals(['value1', 'value2']));

        final rendered = await multiBoundField.asWidget(
          widget: MultiValueWidget(
            widgets: [
              TextInput(
                attrs: {'multiple': 'multiple', 'required': 'required'},
              ),
              TextInput(attrs: {'multiple': 'multiple'}),
            ],
          ),
        );
        expect(rendered, contains('multiple'));
        expect(rendered, contains('required'));
        expect(rendered, contains('value="value1"'));
        expect(rendered, contains('value="value2"'));
      });

      test('handles file fields', () async {
        final fileField = TestField();
        form = Form(
          isBound: true,
          data: {},
          files: {'test_field': 'test_file.txt'},
          fields: {'test_field': fileField},
        );
        boundField = BoundField<String>(form, fileField, 'test_field');

        final rendered = await boundField.asWidget(
          widget: TextInput(attrs: {'type': 'file'}),
        );
        expect(rendered, contains('type="file"'));
      });

      test('renders help text when provided', () async {
        field = TestField(helpText: 'This is help text');
        form = Form(
          isBound: true,
          data: {},
          files: {},
          fields: {'test_field': field},
        );
        boundField = BoundField<String>(form, field, 'test_field');

        final rendered = await boundField.toHtml();
        expect(rendered, contains('This is help text'));
      });

      test('renders placeholder when provided', () async {
        field = TestField();
        form = Form(
          isBound: true,
          data: {},
          files: {},
          fields: {'test_field': field},
        );
        boundField = BoundField<String>(form, field, 'test_field');

        final rendered = await boundField.asWidget(
          widget: TextInput(attrs: {'placeholder': 'Enter value'}),
        );
        expect(rendered, contains('placeholder="Enter value"'));
      });

      test('handles custom widget attributes', () async {
        final rendered = await boundField.asWidget(
          widget: TextInput(
            attrs: {'data-test': 'test-value', 'autocomplete': 'off'},
          ),
        );
        expect(rendered, contains('data-test="test-value"'));
        expect(rendered, contains('autocomplete="off"'));
      });

      test('adds aria-invalid when field has errors', () async {
        form.errors['test_field'] = 'Error message';
        final rendered = await boundField.asWidget(widget: TextInput());
        expect(rendered, contains('aria-invalid'));
        expect(
          rendered,
          contains(
            'aria-describedby="id_test_field_helptext id_test_field_error"',
          ),
        );
      });
    });

    group('Label Rendering', () {
      test('renders label with default text', () {
        final label = boundField.renderLabel();
        expect(label, contains('for="id_test_field"'));
        expect(label, contains('>Test Field<'));
      });

      test('renders label with custom text', () {
        final label = boundField.renderLabel(labelText: 'Custom Label');
        expect(label, contains('>Custom Label<'));
      });

      test('renders label with custom attributes', () {
        final label = boundField.renderLabel(
          attrs: {'class': 'custom-label', 'data-test': 'label'},
        );
        expect(label, contains('class="custom-label"'));
        expect(label, contains('data-test="label"'));
      });
    });

    group('Help Text Rendering', () {
      test('renders help text when present', () {
        final helpText = boundField.renderHelpText();
        expect(helpText, contains('>This is a test field<'));
      });

      test('renders help text with custom attributes', () {
        final helpText = boundField.renderHelpText(
          attrs: {'class': 'help-text', 'data-test': 'help'},
        );
        expect(helpText, contains('class="help-text"'));
        expect(helpText, contains('data-test="help"'));
      });

      test('returns empty string when no help text', () {
        field = TestField();
        boundField = BoundField<String>(form, field, 'test_field');
        expect(boundField.renderHelpText(), isEmpty);
      });
    });

    group('Accessibility Features', () {
      test('generates aria-describedby for help text', () {
        expect(boundField.ariaDescribedby, contains('id_test_field_helptext'));
      });

      test('generates aria-describedby for errors', () {
        form.addError('test_field', 'Error message');
        expect(boundField.ariaDescribedby, contains('id_test_field_error'));
      });

      test('combines aria-describedby for help text and errors', () {
        form.addError('test_field', 'Error message');
        final describedby = boundField.ariaDescribedby;
        expect(describedby, contains('id_test_field_helptext'));
        expect(describedby, contains('id_test_field_error'));
      });

      test('preserves custom aria-describedby', () {
        field.widget.attrs['aria-describedby'] = 'custom-desc';
        expect(boundField.ariaDescribedby, isNull);
      });
    });

    group('Widget Attributes', () {
      test('adds required attribute when appropriate', () async {
        field = TestField(required: true);
        form = Form(
          isBound: true,
          data: {},
          files: {},
          fields: {'test_field': field},
          useRequiredAttribute: true,
        );
        boundField = BoundField<String>(form, field, 'test_field');

        final rendered = await boundField.asWidget();
        expect(rendered, contains('required'));
      });

      test('adds disabled attribute when field is disabled', () async {
        field.disabled = true;
        final rendered = await boundField.asWidget();
        expect(rendered, contains('disabled'));
      });

      test('adds aria-invalid when field has errors', () async {
        form.errors['test_field'] = 'Error message';
        final rendered = await boundField.asWidget(widget: TextInput());
        expect(rendered, contains('aria-invalid'));
        expect(
          rendered,
          contains(
            'aria-describedby="id_test_field_helptext id_test_field_error"',
          ),
        );
      });
    });

    group('MultiValue Fields', () {
      late MultiValueTestField multiField;
      late BoundField<List<String>> multiBoundField;

      setUp(() {
        multiField = MultiValueTestField(
          fields: [TestField(required: true), TestField(required: false)],
        );
        form = Form(
          isBound: true,
          data: {
            'multi_field': ['value1', 'value2'],
          },
          files: {},
          fields: {'multi_field': multiField},
          useRequiredAttribute: true,
        );
        multiBoundField = BoundField<List<String>>(
          form,
          multiField,
          'multi_field',
        );
      });

      test('handles multiple fields correctly', () async {
        final rendered = await multiBoundField.asWidget();
        expect(rendered, contains('value1'));
        expect(rendered, contains('value2'));
      });

      test('respects individual field requirements', () async {
        final rendered = await multiBoundField.asWidget();
        expect(rendered, contains('required'));
        expect(rendered, isNot(contains('required="false"')));
      });
    });
  });
}

/// Test implementation of Field for testing BoundField
class TestField extends Field<String> {
  TestField({
    super.label,
    super.helpText,
    super.required = false,
    super.localize = false,
  }) : super(widget: TextInput(), name: 'test_field');
}

/// Test implementation of MultiValueField
class MultiValueTestField extends MultiValueField<List<String>> {
  MultiValueTestField({required List<Field<String>> fields})
    : super(
        fields: fields,
        widget: MultiValueWidget(widgets: fields.map((f) => f.widget).toList()),
      );

  @override
  List<String>? toDart(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value.cast<String>();
  }

  @override
  List<String>? compress(List<dynamic>? dataList) {
    if (dataList == null) return null;
    return dataList.map((e) => e.toString()).toList();
  }
}
