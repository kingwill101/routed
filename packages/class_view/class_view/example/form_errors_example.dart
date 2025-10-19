import 'package:class_view/class_view.dart';
import 'package:decimal/decimal.dart';

/// Example demonstrating form error rendering in class_view
///
/// This example shows:
/// 1. Form validation errors
/// 2. Field-specific errors
/// 3. How errors are rendered in templates
/// 4. Different error display formats
void main() async {
  print('=== Form Errors Rendering Example ===\n');

  // Configure TemplateManager for the examples
  TemplateManager.configureMemoryOnly(
    extraTemplates: {
      // Template with error display
      'form_with_errors.html': '''
        <div class="form-container">
          <h2>{{ title }}</h2>
          
          {% if errors %}
            <div class="form-errors">
              <h3>Please correct the following errors:</h3>
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
              
              <div class="form-field {% if field_errors %}has-error{% endif %}">
                <label for="{{ field.autoId }}">{{ field.label }}</label>
                <div class="field-input">
                  {{ field.widget_html }}
                </div>
                
                {% if field_errors %}
                  <div class="field-errors">
                    {% for error in field_errors %}
                      <span class="error-message">{{ error }}</span>
                    {% endfor %}
                  </div>
                {% endif %}
                
                {% if field.helpText %}
                  <div class="help-text">{{ field.helpText }}</div>
                {% endif %}
              </div>
            {% endfor %}
            
            <button type="submit" class="btn btn-primary">Submit</button>
          </form>
        </div>
      ''',

      // Simple error display template
      'simple_errors.html': '''
        <div class="simple-form">
          {% if errors %}
            <div class="errors">
              {% for error in errors %}
                <p class="error">{{ error }}</p>
              {% endfor %}
            </div>
          {% endif %}
          
          {% for field_data in fields %}
            {% assign field = field_data[0] %}
            {% assign field_errors = field_data[1] %}
            
            <div class="field">
              {{ field.labelHtml }}
              {{ field.widget_html }}
              {% if field_errors %}
                <div class="field-errors">
                  {% for error in field_errors %}
                    <small class="error">{{ error }}</small>
                  {% endfor %}
                </div>
              {% endif %}
            </div>
          {% endfor %}
        </div>
      ''',

      // Bootstrap-style error template
      'bootstrap_errors.html': '''
        <div class="container">
          <h2>{{ title }}</h2>
          
          {% if errors %}
            <div class="alert alert-danger">
              <h4>Please fix the following errors:</h4>
              <ul class="mb-0">
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
              
              <div class="form-group {% if field_errors %}has-error{% endif %}">
                <label for="{{ field.autoId }}">{{ field.label }}</label>
                {{ field.widget_html }}
                
                {% if field_errors %}
                  <div class="invalid-feedback">
                    {% for error in field_errors %}
                      <div>{{ error }}</div>
                    {% endfor %}
                  </div>
                {% endif %}
                
                {% if field.helpText %}
                  <small class="form-text text-muted">{{ field.helpText }}</small>
                {% endif %}
              </div>
            {% endfor %}
            
            <button type="submit" class="btn btn-primary">Submit</button>
          </form>
        </div>
      ''',
    },
  );

  // Example 1: Form with validation errors
  print('1. Form with validation errors:');
  await demonstrateFormErrors();
  print('');

  // Example 2: Field-specific errors
  print('2. Field-specific errors:');
  await demonstrateFieldErrors();
  print('');

  // Example 3: Different error templates
  print('3. Different error templates:');
  await demonstrateErrorTemplates();
  print('');

  // Example 4: Form processing with errors
  print('4. Form processing with errors:');
  await demonstrateFormProcessing();
  print('');

  print('=== Example Complete ===');
  print('\nKey Features Demonstrated:');
  print('✅ Form-level validation errors');
  print('✅ Field-specific error messages');
  print('✅ Error rendering in templates');
  print('✅ Different error display styles');
  print('✅ Form processing with error handling');
}

/// Demonstrate basic form validation errors
Future<void> demonstrateFormErrors() async {
  // Create a form with validation rules
  final form = UserRegistrationForm(
    data: {
      'username': 'a', // Too short
      'email': 'invalid-email', // Invalid email
      'password': '123', // Too short
      'confirm_password': '456', // Doesn't match
    },
  );

  // Validate the form
  final isValid = await form.isValid();
  print('   Form is valid: $isValid');
  print('   Form errors: ${form.errors}');

  // Render the form with errors
  final renderer = TemplateRenderer();
  final context = await form.getContext();
  context['title'] = 'User Registration (with errors)';

  final html = await renderer.renderAsync('form_with_errors.html', context);
  print('   Rendered HTML:');
  print('   ${html.replaceAll('\n', '\n   ')}');
}

/// Demonstrate field-specific errors
Future<void> demonstrateFieldErrors() async {
  // Create a form with field-specific validation
  final form = ContactForm(
    data: {
      'name': '', // Required field
      'email': 'not-an-email', // Invalid format
      'message': 'Hi', // Too short
      'age': 'abc', // Not a number
    },
  );

  // Validate the form
  final isValid = await form.isValid();
  print('   Form is valid: $isValid');

  // Show field-specific errors
  for (final fieldName in form.fields.keys) {
    final boundField = form[fieldName];
    if (boundField.errors.isNotEmpty) {
      print('   $fieldName errors: ${boundField.errors}');
    }
  }

  // Render with simple template
  final renderer = TemplateRenderer();
  final context = await form.getContext();
  context['title'] = 'Contact Form (field errors)';

  final html = await renderer.renderAsync('simple_errors.html', context);
  print('   Rendered HTML:');
  print('   ${html.replaceAll('\n', '\n   ')}');
}

/// Demonstrate different error templates
Future<void> demonstrateErrorTemplates() async {
  // Create a form with various errors
  final form = ProductForm(
    data: {
      'name': '', // Required
      'price': '-10', // Negative price
      'description': 'Short', // Too short
      'category': '', // Required
    },
  );

  await form.isValid(); // Trigger validation

  final renderer = TemplateRenderer();
  final context = await form.getContext();
  context['title'] = 'Product Form';

  // Render with different templates
  final templates = [
    'form_with_errors.html',
    'simple_errors.html',
    'bootstrap_errors.html',
  ];

  for (final template in templates) {
    print('   Template: $template');
    final html = await renderer.renderAsync(template, context);
    print('   ${html.replaceAll('\n', '\n   ')}');
    print('');
  }
}

/// Demonstrate form processing with error handling
Future<void> demonstrateFormProcessing() async {
  // Create a form view that processes the form
  final view = FormProcessingView();

  // Simulate form submission with errors
  print('   Processing form with errors...');
  await view.processFormWithErrors();
}

/// User registration form with validation
class UserRegistrationForm extends Form {
  UserRegistrationForm({Map<String, dynamic>? data})
    : super(
        isBound: data != null,
        data: data ?? {},
        files: {},
        fields: {
          'username': CharField(
            required: true,
            minLength: 3,
            maxLength: 20,
            widget: TextInput(
              attrs: {'placeholder': 'Enter username', 'class': 'form-control'},
            ),
          ),
          'email': EmailField(
            required: true,
            widget: EmailInput(
              attrs: {'placeholder': 'Enter email', 'class': 'form-control'},
            ),
          ),
          'password': CharField(
            required: true,
            minLength: 8,
            widget: PasswordInput(
              attrs: {'placeholder': 'Enter password', 'class': 'form-control'},
            ),
          ),
          'confirm_password': CharField(
            required: true,
            widget: PasswordInput(
              attrs: {
                'placeholder': 'Confirm password',
                'class': 'form-control',
              },
            ),
          ),
        },
      );

  @override
  void clean() {
    super.clean();

    // Custom validation: check if passwords match
    final password = cleanedData['password'];
    final confirmPassword = cleanedData['confirm_password'];

    if (password != null &&
        confirmPassword != null &&
        password != confirmPassword) {
      errors['confirm_password'] = 'Passwords do not match';
    }
  }
}

/// Contact form with various field types
class ContactForm extends Form {
  ContactForm({Map<String, dynamic>? data})
    : super(
        isBound: data != null,
        data: data ?? {},
        files: {},
        fields: {
          'name': CharField(
            required: true,
            minLength: 2,
            widget: TextInput(
              attrs: {'placeholder': 'Your name', 'class': 'form-control'},
            ),
          ),
          'email': EmailField(
            required: true,
            widget: EmailInput(
              attrs: {'placeholder': 'your@email.com', 'class': 'form-control'},
            ),
          ),
          'message': CharField(
            required: true,
            minLength: 10,
            widget: Textarea(
              attrs: {
                'rows': '4',
                'placeholder': 'Your message...',
                'class': 'form-control',
              },
            ),
          ),
          'age': IntegerField(
            required: false,
            minValue: 0,
            maxValue: 120,
            widget: NumberInput(
              attrs: {'placeholder': 'Your age', 'class': 'form-control'},
            ),
          ),
        },
      );
}

/// Product form with business logic validation
class ProductForm extends Form {
  ProductForm({Map<String, dynamic>? data})
    : super(
        isBound: data != null,
        data: data ?? {},
        files: {},
        fields: {
          'name': CharField(
            required: true,
            minLength: 3,
            widget: TextInput(
              attrs: {'placeholder': 'Product name', 'class': 'form-control'},
            ),
          ),
          'price': DecimalField(
            required: true,
            minValue: Decimal.parse('0'),
            widget: NumberInput(
              attrs: {
                'placeholder': 'Price',
                'class': 'form-control',
                'step': '0.01',
              },
            ),
          ),
          'description': CharField(
            required: true,
            minLength: 20,
            widget: Textarea(
              attrs: {
                'rows': '3',
                'placeholder': 'Product description...',
                'class': 'form-control',
              },
            ),
          ),
          'category': ChoiceField(
            required: true,
            choices: [
              ['electronics', 'Electronics'],
              ['clothing', 'Clothing'],
              ['books', 'Books'],
              ['home', 'Home & Garden'],
            ],
            widget: Select(
              choices: [
                ['electronics', 'Electronics'],
                ['clothing', 'Clothing'],
                ['books', 'Books'],
                ['home', 'Home & Garden'],
              ],
              attrs: {'class': 'form-control'},
            ),
          ),
        },
      );
}

/// Form processing view that demonstrates error handling
class FormProcessingView {
  Future<void> processFormWithErrors() async {
    // Create a form with invalid data
    final form = UserRegistrationForm(
      data: {
        'username': 'a',
        'email': 'invalid',
        'password': '123',
        'confirm_password': '456',
      },
    );

    try {
      // Attempt to process the form
      final isValid = await form.isValid();

      if (!isValid) {
        print('   Form validation failed:');
        print('   - Form errors: ${form.errors}');

        for (final fieldName in form.fields.keys) {
          final boundField = form[fieldName];
          if (boundField.errors.isNotEmpty) {
            print('   - $fieldName: ${boundField.errors}');
          }
        }

        // Render the form with errors
        final renderer = TemplateRenderer();
        final context = await form.getContext();
        context['title'] = 'Registration Failed';

        final html = await renderer.renderAsync(
          'form_with_errors.html',
          context,
        );
        print('   Rendered form with errors:');
        print('   ${html.replaceAll('\n', '\n   ')}');
      } else {
        print('   Form is valid - processing...');
        // Process the form data
        print('   Username: ${form.cleanedData['username']}');
        print('   Email: ${form.cleanedData['email']}');
      }
    } catch (e) {
      print('   Error processing form: $e');
    }
  }
}
