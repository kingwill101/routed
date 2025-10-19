import 'package:class_view/class_view.dart';

/// Simple example demonstrating form error rendering
///
/// This example shows how form validation errors are captured and rendered
void main() async {
  print('=== Simple Form Errors Example ===\n');

  // Configure TemplateManager with a simple template
  TemplateManager.configureMemoryOnly(
    extraTemplates: {
      'simple_form.html': '''
        <div class="form">
          <h2>{{ title }}</h2>
          
          {% if errors %}
            <div class="form-errors">
              <h3>Please fix these errors:</h3>
              <ul>
                {% for error in errors %}
                  <li>{{ error }}</li>
                {% endfor %}
              </ul>
            </div>
          {% endif %}
          
          <form method="post">
            {% for field_data in fields %}
              {% assign field = field_data[0] %}
              {% assign field_errors = field_data[1] %}
              
              <div class="field {% if field_errors %}has-error{% endif %}">
                <label>{{ field.label }}</label>
                <div class="input">
                  {{ field.widget_html }}
                </div>
                
                {% if field_errors %}
                  <div class="field-errors">
                    {% for error in field_errors %}
                      <span class="error">{{ error }}</span>
                    {% endfor %}
                  </div>
                {% endif %}
              </div>
            {% endfor %}
            
            <button type="submit">Submit</button>
          </form>
        </div>
      ''',
    },
  );

  // Example 1: Form with validation errors
  print('1. Creating form with invalid data...');
  final form = SimpleForm(
    data: {
      'name': '', // Required field - empty
      'email': 'not-an-email', // Invalid email format
      'age': 'abc', // Not a number
    },
  );

  // Validate the form
  print('2. Validating form...');
  final isValid = await form.isValid();
  print('   Form is valid: $isValid');

  // Show form errors
  print('3. Form errors:');
  print('   ${form.errors}');

  // Show field-specific errors
  print('4. Field-specific errors:');
  for (final fieldName in form.fields.keys) {
    final boundField = form[fieldName];
    if (boundField.errors.isNotEmpty) {
      print('   $fieldName: ${boundField.errors}');
    }
  }

  // Render the form with errors
  print('5. Rendering form with errors...');
  final renderer = TemplateRenderer();
  final context = await form.getContext();
  context['title'] = 'Simple Form (with errors)';

  final html = await renderer.renderAsync('simple_form.html', context);
  print('6. Rendered HTML:');
  print(html);

  // Example 2: Form with valid data
  print('\n7. Creating form with valid data...');
  final validForm = SimpleForm(
    data: {'name': 'John Doe', 'email': 'john@example.com', 'age': '25'},
  );

  final validIsValid = await validForm.isValid();
  print('   Form is valid: $validIsValid');
  print('   Form errors: ${validForm.errors}');

  // Render the valid form
  final validContext = await validForm.getContext();
  validContext['title'] = 'Simple Form (valid)';
  final validHtml = await renderer.renderAsync(
    'simple_form.html',
    validContext,
  );
  print('8. Rendered HTML (valid form):');
  print(validHtml);

  print('\n=== Example Complete ===');
  print('\nKey Points Demonstrated:');
  print('✅ Form validation detects invalid data');
  print('✅ Field-specific error messages are captured');
  print('✅ Form-level errors are available');
  print('✅ Errors are rendered in templates');
  print('✅ Valid forms render without errors');
}

/// Simple form with basic validation
class SimpleForm extends Form {
  SimpleForm({Map<String, dynamic>? data})
    : super(
        isBound: data != null,
        data: data ?? {},
        files: {},
        fields: {
          'name': CharField(
            required: true,
            minLength: 2,
            widget: TextInput(
              attrs: {
                'placeholder': 'Enter your name',
                'class': 'form-control',
              },
            ),
          ),
          'email': EmailField(
            required: true,
            widget: EmailInput(
              attrs: {
                'placeholder': 'Enter your email',
                'class': 'form-control',
              },
            ),
          ),
          'age': IntegerField(
            required: false,
            minValue: 0,
            maxValue: 120,
            widget: NumberInput(
              attrs: {'placeholder': 'Enter your age', 'class': 'form-control'},
            ),
          ),
        },
      );
}
