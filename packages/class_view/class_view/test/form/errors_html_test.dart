import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

void main() {
  group('Form errors_html rendering', () {
    test(
      'errors_html should contain ul.errorlist when field has errors',
      () async {
        final form = Form(
          isBound: true,
          data: {'name': ''}, // Empty value will fail required validation
          files: {},
          fields: {
            'name': CharField(
              label: 'Name',
              required: true,
              helpText: 'Your full name',
            ),
          },
        );

        // Validate the form - this should fail
        final isValid = await form.isValid();
        expect(isValid, isFalse);

        // Get the bound field
        final boundField = BoundField(form, form.fields['name']!, 'name');

        // Check that errors exist
        expect(boundField.hasErrors, isTrue);
        expect(boundField.errors, isNotEmpty);

        // Check errors_html rendering
        final errorsHtml = await boundField.renderErrors();
        print('errors_html output: $errorsHtml');

        // Verify structure
        expect(errorsHtml, contains('<ul'));
        expect(errorsHtml, contains('class="errorlist"'));
        expect(errorsHtml, contains('<li>'));
        expect(errorsHtml, contains('This field is required'));
        expect(errorsHtml, contains('</li>'));
        expect(errorsHtml, contains('</ul>'));
      },
    );

    test(
      'errors_html should be empty string when field has no errors',
      () async {
        final form = Form(
          isBound: true,
          data: {'name': 'John Doe'},
          files: {},
          fields: {'name': CharField(label: 'Name', required: true)},
        );

        // Validate the form - this should pass
        final isValid = await form.isValid();
        expect(isValid, isTrue);

        // Get the bound field
        final boundField = BoundField(form, form.fields['name']!, 'name');

        // Check that no errors exist
        expect(boundField.hasErrors, isFalse);

        // Check errors_html is empty
        final errorsHtml = await boundField.renderErrors();
        expect(errorsHtml, isEmpty);
      },
    );

    test('Form asP should include errors_html in output', () async {
      final form = Form(
        isBound: true,
        data: {'email': 'invalid-email'}, // Invalid email
        files: {},
        fields: {'email': EmailField(label: 'Email', required: true)},
      );

      // Validate the form - this should fail
      await form.isValid();

      // Render as P
      final html = await form.asP();
      print('Form asP output:\n$html');

      // Check that errors are rendered
      expect(html, contains('<ul'));
      expect(html, contains('errorlist'));
      expect(html, contains('<li>'));
    });

    test('Form asDiv should include errors_html in output', () async {
      final form = Form(
        isBound: true,
        data: {'number': 'not-a-number'}, // Invalid number
        files: {},
        fields: {'number': IntegerField(label: 'Number', required: true)},
      );

      // Validate the form
      await form.isValid();

      // Render as Div
      final html = await form.asDiv();
      print('Form asDiv output:\n$html');

      // Check that errors are rendered
      expect(html, contains('<ul'));
      expect(html, contains('errorlist'));
      expect(html, contains('<li>'));
    });

    test(
      'Multiple errors should be rendered as multiple li elements',
      () async {
        final form = Form(
          isBound: true,
          data: {'text': 'ab'},
          // Too short (min 5) and too long validation will pass
          files: {},
          fields: {
            'text': CharField(
              label: 'Text',
              required: true,
              minLength: 5,
              validators: [MinLengthValidator(5)],
            ),
          },
        );

        await form.isValid();

        final boundField = BoundField(form, form.fields['text']!, 'text');
        final errorsHtml = await boundField.renderErrors();
        print('Multiple errors HTML: $errorsHtml');

        // Should have error list
        expect(errorsHtml, contains('<ul'));
        expect(errorsHtml, contains('errorlist'));
        expect(errorsHtml, contains('<li>'));
      },
    );
  });
}
