import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

class DefaultTestRenderer extends Renderer {
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
    // Simple template rendering for testing
    final fieldEntries = (context['fields'] as List<dynamic>?)
        ?.map<Map<String, dynamic>>((f) {
          if (f is Map<String, dynamic>) {
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
      buffer.writeln("</p>");
    }
    return buffer.toString();
  }
}

void main() {
  group('Form', () {
    late Form form;
    late Field<String> nameField;
    late Field<String> emailField;
    late Field<int> ageField;

    setUp(() {
      nameField = TestField<String>(
        label: 'Name',
        validators: [MinLengthValidator(2)],
      );

      emailField = TestField<String>(
        label: 'Email',
        validators: [EmailValidator()],
      );

      ageField = TestField<int>(
        label: 'Age',
        validators: [MinValueValidator(18)],
      );

      form = Form(
        isBound: true,
        data: {'name': 'John Doe', 'email': 'john@example.com', 'age': '25'},
        files: {},
        fields: {'name': nameField, 'email': emailField, 'age': ageField},
      );
    });

    test('initializes with correct values', () {
      expect(form.isBound, isTrue);
      expect(form.data, containsPair('name', 'John Doe'));
      expect(form.fields.length, equals(3));
      expect(form.errors, isEmpty);
      expect(form.cleanedData, isEmpty);
    });

    test('validates form data correctly', () async {
      expect(await form.isValid(), isTrue);
      expect(form.cleanedData, isNotEmpty);
      expect(form.cleanedData['name'], equals('John Doe'));
      expect(form.cleanedData['email'], equals('john@example.com'));
      expect(form.cleanedData['age'], equals(25));
    });

    test('handles invalid data', () async {
      form = Form(
        isBound: true,
        data: {
          'name': 'J', // Too short
          'email': 'invalid-email', // Invalid email
          'age': '17', // Under 18
        },
        files: {},
        fields: {'name': nameField, 'email': emailField, 'age': ageField},
      );

      expect(await form.isValid(), isFalse);
      expect(form.errors.length, equals(3));
      expect(form.cleanedData, isEmpty);
    });

    test('handles field access via operator', () {
      final boundName = form['name'];
      expect(boundName.value, equals('John Doe'));
      expect(boundName.label, equals('Name'));
    });

    test('throws on invalid field access', () {
      expect(() => form['invalid_field'], throwsA(isA<ArgumentError>()));
    });

    test('handles form prefixes', () {
      form = Form(
        isBound: true,
        data: {'user-name': 'John Doe'},
        files: {},
        prefix: 'user',
        fields: {'name': nameField},
      );

      expect(form['name'].htmlName, equals('user-name'));
    });

    test('detects changed fields', () {
      form = Form(
        isBound: true,
        data: {'name': 'Jane Doe'},
        files: {},
        initial: {'name': 'John Doe'},
        fields: {'name': nameField},
      );

      expect(form.hasChanged(), isTrue);
      expect(form.changedData, equals(['name']));
    });

    test('handles empty permitted forms', () async {
      form = Form(
        isBound: true,
        data: {},
        files: {},
        emptyPermitted: true,
        fields: {'name': nameField},
      );

      expect(await form.isValid(), isTrue);
    });

    test('identifies hidden and visible fields', () {
      final hiddenField = TestField<String>();
      hiddenField.widget = HiddenInput();

      form = Form(
        isBound: true,
        data: {'visible': 'visible value', 'hidden': 'hidden value'},
        files: {},
        fields: {'visible': nameField, 'hidden': hiddenField},
      );

      expect(form.hiddenFields().length, equals(1));
      expect(form.visibleFields().length, equals(1));
    });

    test('handles multipart forms', () {
      final fileField = TestField<String>();
      fileField.widget = TestFileWidget();

      form = Form(
        isBound: true,
        data: {},
        files: {'file': 'test.txt'},
        fields: {'file': fileField},
      );

      expect(form.isMultipart(), isTrue);
    });

    test('handles non-field errors', () {
      form.addError(null, 'Form level error');
      expect(form.errors['__all__'], equals('Form level error'));
    });

    test('handles initial values', () {
      form = Form(
        isBound: false,
        data: {},
        files: {},
        initial: {'name': 'Initial Name'},
        fields: {'name': nameField},
      );

      final boundField = form['name'];
      expect(boundField.value, isNull);
      expect(
        form.getInitialForField(nameField, 'name'),
        equals('Initial Name'),
      );
    });

    test('handles callable initial values', () {
      form = Form(
        isBound: false,
        data: {},
        files: {},
        initial: {'timestamp': DateTime.now},
        fields: {'timestamp': TestField<DateTime>()},
      );

      final value = form.getInitialForField(
        form.fields['timestamp']!,
        'timestamp',
      );
      expect(value, isA<DateTime>());
    });

    test("asP", () async {
      form = Form(
        isBound: false,
        data: {},
        files: {},
        initial: {'timestamp': DateTime.now},
        fields: {'timestamp': TestField<DateTime>()},
      );

      final value = form.getInitialForField(
        form.fields['timestamp']!,
        'timestamp',
      );
      expect(value, isA<DateTime>());

      expect(await form.asP(), contains('Timestamp'));
    });

    test("renders form layouts correctly", () async {
      form = Form(
        isBound: true,
        data: {'name': 'John Doe', 'email': 'john@example.com', 'age': '25'},
        files: {},
        fields: {'name': nameField, 'email': emailField, 'age': ageField},
        // renderer: defaultRenderer,
      );

      // Test paragraph layout
      final pHtml = await form.asP();
      expect(pHtml, contains('<p'));
      expect(pHtml, contains('John Doe'));
      expect(pHtml, contains('john@example.com'));
      expect(pHtml, contains('25'));

      // Test div layout
      final divHtml = await form.asDiv();
      expect(divHtml, contains('<div'));
      expect(divHtml, contains('John Doe'));
      expect(divHtml, contains('john@example.com'));
      expect(divHtml, contains('25'));

      // Test table layout
      final tableHtml = await form.asTable();
      expect(tableHtml, contains('<tr'));
      expect(tableHtml, contains('<th>'));
      expect(tableHtml, contains('<td>'));
      expect(tableHtml, contains('John Doe'));
      expect(tableHtml, contains('john@example.com'));
      expect(tableHtml, contains('25'));

      // Test unordered list layout
      final ulHtml = await form.asUl();
      expect(ulHtml, contains('<li'));
      expect(ulHtml, contains('John Doe'));
      expect(ulHtml, contains('john@example.com'));
      expect(ulHtml, contains('25'));
    });

    test("handles missing renderer gracefully", () async {
      form = Form(
        isBound: true,
        data: {'name': 'John Doe', 'email': 'john@example.com', 'age': '25'},
        files: {},
        fields: {'name': nameField, 'email': emailField, 'age': ageField},
        // No renderer provided
      );

      // Should render using fallback templates without throwing
      expect(await form.asP(), isNotEmpty);
      expect(await form.asDiv(), isNotEmpty);
      expect(await form.asTable(), isNotEmpty);
      expect(await form.asUl(), isNotEmpty);
    });
  });
}

/// A test widget that requires multipart form encoding
class TestFileWidget extends TextInput {
  @override
  bool get needsMultipartForm => true;

  @override
  Future<String> render(
    String name,
    value, {
    Map<String, dynamic>? attrs,
    Renderer? renderer,
    String? templateName,
  }) async {
    final mergedAttrs = {'type': 'file', ...attrs ?? {}};
    return '<input name="$name" ${buildAttrs(mergedAttrs, null)}>';
  }
}

class TestField<T> extends Field<T> {
  TestField({
    super.label,
    super.helpText,
    super.required = true,
    super.disabled = false,
    super.initial,
    super.validators,
    String name = 'test_field',
  }) : super(widget: TextInput(), name: name);

  @override
  T? toDart(dynamic value) {
    if (value == null) return null;
    if (T == int) return int.parse(value.toString()) as T?;
    if (T == double) return double.parse(value.toString()) as T?;
    if (T == DateTime) return DateTime.parse(value.toString()) as T?;
    return value as T?;
  }

  @override
  Field<T> deepCopy() {
    return TestField<T>(
      label: label,
      helpText: helpText,
      required: required,
      disabled: disabled,
      initial: initial,
      validators: List.from(validators),
      name: name,
    );
  }
}
