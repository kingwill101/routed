import 'dart:math' as math;
import 'dart:convert';

import 'package:class_view/class_view.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../shared/mock_adapter.mocks.dart';

/// Test form for template integration
class ContactForm extends Form {
  ContactForm({Map<String, dynamic>? data, super.renderer})
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
                'rows': '5',
                'placeholder': 'Your message...',
                'class': 'form-control',
              },
            ),
          ),
          'subscribe': BooleanField(required: false, widget: CheckboxInput()),
        },
      );

  // Add a toJson method for JSON serialization
  Map<String, dynamic> toJson() {
    return {
      'is_bound': isBound,
      'data': data,
      'errors': errors,
      'cleaned_data': cleanedData,
      'fields': fields.keys.toList(),
    };
  }
}

/// Test view that uses ContactForm with template rendering
class ContactFormView extends View with ContextMixin, TemplateResponseMixin {
  @override
  String get templateName => 'contact/form.html';

  @override
  List<String> get allowedMethods => ['GET', 'POST'];

  Map<String, dynamic> get initialData => {'subscribe': true};

  Future<bool> isBound() async => (await adapter.getMethod()) == 'POST';

  ContactForm? _form;

  Future<ContactForm> getForm() async {
    final data = await adapter.getFormData();
    return _form ??= ContactForm(
      data: await isBound() ? data : null,
      renderer: TemplateRenderer(),
    );
  }

  @override
  Future<Map<String, dynamic>> getContextData() async {
    final baseContext = await super.getContextData();
    final form = await getForm();
    return {
      ...baseContext,
      'form': form.toJson(), // Use toJson for serialization
      'title': 'Contact Us',
      'page_description': 'Send us a message!',
    };
  }

  @override
  Future<void> get() async {
    final contextData = await getContextData();
    adapter.write(jsonEncode(contextData));
  }

  @override
  Future<void> post() async {
    try {
      await processForm();
    } catch (e) {
      if (e is FormValidationError) {
        adapter.setStatusCode(400);
        final contextData = await getContextData();
        adapter.write(jsonEncode({...contextData, 'errors': e.errors}));
      } else {
        rethrow;
      }
    }
  }

  Future<void> formValid(Map<String, dynamic> data) async {
    // Process the valid form data
    print('Form submitted successfully with data: $data');

    // In a real app, you'd save to database, send email, etc.
    adapter.redirect('/thank-you/');
  }

  // Override to handle form validation
  Future<void> processForm() async {
    final form = await getForm();

    if (await form.isValid()) {
      await formValid(form.cleanedData);
    } else {
      // Form has errors - will be re-rendered with errors
      throw FormValidationError('Form has validation errors', form.errors);
    }
  }
}

/// Custom exception for form validation errors
class FormValidationError implements Exception {
  final String message;
  final Map<String, dynamic> errors;

  FormValidationError(this.message, this.errors);

  @override
  String toString() => message;
}

void main() {
  group('Template Integration Tests', () {
    setUp(() {
      // Reset TemplateManager for each test
      TemplateManager.reset();
    });

    test('Form basic functionality works', () async {
      // Setup: Create form with valid data
      final form = ContactForm(
        data: {
          'name': 'John Doe',
          'email': 'john@example.com',
          'message': 'Hello there! This is a test message.',
          'subscribe': 'true',
        },
        renderer: TemplateRenderer(),
      );

      // Test: Validate form
      final isValid = await form.isValid();
      expect(isValid, isTrue);
      expect(form.cleanedData, isNotEmpty);
      expect(form.cleanedData['name'], equals('John Doe'));
      expect(form.cleanedData['email'], equals('john@example.com'));
      expect(
        form.cleanedData['message'],
        equals('Hello there! This is a test message.'),
      );
      expect(form.cleanedData['subscribe'], isTrue);
    });

    test('Form validation errors work', () async {
      // Setup: Create form with invalid data
      final form = ContactForm(
        data: {
          'name': 'J', // Too short
          'email': 'invalid-email', // Invalid email
          'message': 'Short', // Too short
        },
        renderer: TemplateRenderer(),
      );

      // Test: Validate form
      final isValid = await form.isValid();
      expect(isValid, isFalse);
      expect(form.errors, isNotEmpty);
      expect(form.errors['name'], isNotEmpty);
      expect(form.errors['email'], isNotEmpty);
      expect(form.errors['message'], isNotEmpty);
    });

    test('Form renders with TemplateRenderer', () async {
      // Setup: Configure TemplateManager with a simple template that won't cause hanging
      TemplateManager.configureMemoryOnly(
        extraTemplates: {
          'form/form_div.html': '''
            <div class="form-with-renderer">
              <p>Form rendered with TemplateRenderer</p>
            </div>
          ''',
        },
      );

      final form = ContactForm(
        data: {
          'name': 'Jane Doe',
          'email': 'jane@example.com',
          'message': 'This is a test message with template renderer.',
        },
        renderer:
            TemplateRenderer(), // Now it will work with configured templates
      );

      // Test: Just verify that the form can be created with TemplateRenderer without hanging
      expect(form.isBound, isTrue);
      expect(form.data['name'], equals('Jane Doe'));
      expect(form.data['email'], equals('jane@example.com'));

      // Try to render just one method to avoid hanging
      final divHtml = await form.asDiv();
      expect(divHtml, isNotEmpty);
    });

    test('Form renders with fallback (no TemplateRenderer)', () async {
      // Setup: Create form without renderer to test fallback
      final form = ContactForm(
        data: {
          'name': 'Jane Doe',
          'email': 'jane@example.com',
          'message': 'This is a test message without renderer.',
        },
        // No renderer provided - should use fallback
      );

      // Test: Render form (should use fallback)
      final divHtml = await form.asDiv();
      final pHtml = await form.asP();

      // Verify: Fallback rendering works
      expect(divHtml, isNotEmpty);
      expect(pHtml, isNotEmpty);

      // Verify: Contains form data
      expect(divHtml, contains('Jane Doe'));
      expect(divHtml, contains('jane@example.com'));

      print('✅ Form without renderer rendered successfully (fallback)');
      print('Fallback HTML length: ${divHtml.length}');
      print(
        'Sample HTML: ${divHtml.substring(0, math.min(200, divHtml.length))}...',
      );
    });

    test('TemplateManager basic rendering', () async {
      // Setup: Use memory-only configuration to avoid filesystem issues
      TemplateManager.configureMemoryOnly(
        extraTemplates: {
          'test/simple.html': '''
            <div class="test">
              <h1>{{ title }}</h1>
              <p>{{ message }}</p>
            </div>
          ''',
        },
      );

      // Test: Render with custom template
      final html = await TemplateManager.render('test/simple.html', {
        'title': 'Test Title',
        'message': 'Test Message',
      });

      // Verify: Template rendered correctly
      expect(html, contains('Test Title'));
      expect(html, contains('Test Message'));
      expect(html, contains('class="test"'));

      print('✅ TemplateManager basic rendering works');
      print('Rendered HTML: $html');
    });

    test('TemplateRenderer integration', () async {
      // Setup: Configure TemplateManager with field template
      TemplateManager.configureMemoryOnly(
        extraTemplates: {
          'form/field_div.html': '''
            <div class="field-wrapper">
              <label>{{ field.label_html }}</label>
              <div class="field-input">{{ field.widget_html }}</div>
              {% if field.help_text %}
                <div class="help-text">{{ field.help_text }}</div>
              {% endif %}
            </div>
          ''',
        },
      );

      // Setup: Create TemplateRenderer
      final renderer = TemplateRenderer();

      // Test: Render a field template through the renderer
      final html = await renderer.renderAsync('form/field_div.html', {
        'field': {
          'label_html': '<label>Test Field</label>',
          'widget_html': '<input type="text" name="test">',
          'help_text': 'This is help text',
        },
      });

      // Verify: Renderer works
      expect(html, isNotEmpty);
      expect(html, contains('field-wrapper'));
      expect(html, contains('Test Field'));

      print('✅ TemplateRenderer integration works');
      print('Rendered field HTML: $html');
    });

    test('Form view handles GET request', () async {
      final mockAdapter = MockViewAdapter();
      final view = ContactFormView();
      view.setAdapter(mockAdapter);

      when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
      when(mockAdapter.getFormData()).thenAnswer((_) async => {});

      await view.get();

      final capturedString =
          verify(mockAdapter.write(captureAny)).captured.first as String;
      final capturedContext =
          jsonDecode(capturedString) as Map<String, dynamic>;
      expect(capturedContext['title'], equals('Contact Us'));
      expect(capturedContext['page_description'], equals('Send us a message!'));
      expect(capturedContext['form'], isNotNull);
      expect(capturedContext['form']['is_bound'], isFalse);
    });

    test('Form view handles POST request with valid data', () async {
      final mockAdapter = MockViewAdapter();
      final view = ContactFormView();
      view.setAdapter(mockAdapter);

      when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
      when(mockAdapter.getFormData()).thenAnswer(
        (_) async => {
          'name': 'John Doe',
          'email': 'john@example.com',
          'message': 'Hello there! This is a test message.',
          'subscribe': 'true',
        },
      );

      await view.post();

      verify(mockAdapter.redirect('/thank-you/')).called(1);
    });

    test('Form view handles POST request with invalid data', () async {
      final mockAdapter = MockViewAdapter();
      final view = ContactFormView();
      view.setAdapter(mockAdapter);

      when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
      when(mockAdapter.getFormData()).thenAnswer(
        (_) async => {
          'name': 'J',
          'email': 'invalid-email',
          'message': 'Short',
        },
      );

      await view.post();

      verify(mockAdapter.setStatusCode(400)).called(1);
      final capturedString =
          verify(mockAdapter.write(captureAny)).captured.first as String;
      final capturedContext =
          jsonDecode(capturedString) as Map<String, dynamic>;
      expect(capturedContext['errors'], isNotNull);
      expect(capturedContext['errors']['name'], isNotEmpty);
      expect(capturedContext['errors']['email'], isNotEmpty);
      expect(capturedContext['errors']['message'], isNotEmpty);
    });

    test(
      'Form renders with TemplateRenderer and configured TemplateManager',
      () async {
        // Setup: Configure TemplateManager with memory templates only (avoid filesystem issues)
        TemplateManager.configureMemoryOnly(
          extraTemplates: {
            'form/form_div.html': '''
            <div class="form">
              {% if errors %}
                <div class="form-errors">
                  {% for error in errors %}
                    <div class="error">{{ error }}</div>
                  {% endfor %}
                </div>
              {% endif %}
              
              {% for field_data in fields %}
                {% assign field = field_data[0] %}
                {% assign field_errors = field_data[1] %}
                
                <div class="field-wrapper">
                  {% if field_errors %}
                    <div class="field-errors">
                      {% for error in field_errors %}
                        <span class="error">{{ error }}</span>
                      {% endfor %}
                    </div>
                  {% endif %}
                  
                  <div class="field-content">
                    <label>{{ field.label }}</label>
                    <div class="field-input">{{ field.widget_html }}</div>
                  </div>
                </div>
              {% endfor %}
              
              {% if hidden_fields %}
                <div class="hidden-fields">
                  {% for hidden in hidden_fields %}
                    {{ hidden }}
                  {% endfor %}
                </div>
              {% endif %}
            </div>
          ''',
          },
        );

        // Setup: Create form with TemplateRenderer
        final form = ContactForm(
          data: {
            'name': 'Jane Doe',
            'email': 'jane@example.com',
            'message':
                'This is a test message with template renderer and configured templates.',
          },
          renderer:
              TemplateRenderer(), // Now it should work with configured templates
        );

        // Test: Render form using template system
        final divHtml = await form.asDiv();

        // Verify: Template rendering works
        expect(divHtml, isNotEmpty);
        expect(
          divHtml,
          contains('class="form"'),
        ); // Should contain our template structure

        print(
          '✅ Form with TemplateRenderer and configured TemplateManager works',
        );
        print('Div HTML length: ${divHtml.length}');
        print(
          'Template HTML: ${divHtml.substring(0, math.min(500, divHtml.length))}...',
        );
      },
    );

    test('TemplateManager memory-only rendering', () async {
      // Setup: Configure TemplateManager with memory templates only
      TemplateManager.configureMemoryOnly(
        extraTemplates: {
          'test/simple.html': '''
            <div class="test">
              <h1>{{ title }}</h1>
              <p>{{ message }}</p>
            </div>
          ''',
        },
      );

      // Test: Render with custom template
      final html = await TemplateManager.render('test/simple.html', {
        'title': 'Test Title',
        'message': 'Test Message',
      });

      // Verify: Template rendered correctly
      expect(html, contains('Test Title'));
      expect(html, contains('Test Message'));
      expect(html, contains('class="test"'));

      print('✅ TemplateManager memory-only rendering works');
      print('Rendered HTML: $html');
    });

    test('Widget DefaultView fallback works when template does not exist', () async {
      // Setup: Configure TemplateManager WITHOUT widget templates to force fallbacks
      TemplateManager.configureMemoryOnly(
        extraTemplates: {
          'other/template.html': '<div>Other template</div>',
          // Deliberately NOT including widget templates
        },
      );

      // Create widgets with DefaultView implementations
      final textWidget = TextInput(
        attrs: {'class': 'test-input', 'placeholder': 'Enter text'},
      );
      final textareaWidget = Textarea(attrs: {'rows': '5', 'cols': '30'});
      final emailWidget = EmailInput(attrs: {'class': 'email-field'});
      final checkboxWidget = CheckboxInput();

      // Create TemplateRenderer (without fallbacks now)
      final renderer = TemplateRenderer();

      // Test 1: TextInput should use DefaultView when template doesn't exist
      print('Testing TextInput...');
      final textHtml = await textWidget.render(
        'username',
        'john_doe',
        renderer: renderer,
      );
      print('TextInput rendered: "$textHtml"');

      // Test 2: Textarea should use DefaultView when template doesn't exist
      print('Testing Textarea...');
      final textareaHtml = await textareaWidget.render(
        'message',
        'Hello World!',
        renderer: renderer,
      );
      print('Textarea rendered: "$textareaHtml"');

      // Test 3: EmailInput should use DefaultView when template doesn't exist
      print('Testing EmailInput...');
      final emailHtml = await emailWidget.render(
        'email',
        'test@example.com',
        renderer: renderer,
      );
      print('EmailInput rendered: "$emailHtml"');

      // Test 4: CheckboxInput should use DefaultView when template doesn't exist
      print('Testing CheckboxInput...');
      final checkboxHtml = await checkboxWidget.render(
        'subscribe',
        true,
        renderer: renderer,
      );
      print('CheckboxInput rendered: "$checkboxHtml"');

      // Verify: All widgets rendered using their DefaultView implementations
      // These should contain proper HTML even though templates don't exist

      // TextInput should render as <input type="text">
      expect(
        textHtml,
        isNotEmpty,
        reason: 'TextInput should not return empty string',
      );
      expect(textHtml, contains('<input type="text"'));
      expect(textHtml, contains('name="username"'));
      expect(textHtml, contains('value="john_doe"'));
      expect(textHtml, contains('class="test-input"'));
      expect(textHtml, contains('placeholder="Enter text"'));

      // Textarea should render as <textarea>
      expect(
        textareaHtml,
        isNotEmpty,
        reason: 'Textarea should not return empty string',
      );
      expect(textareaHtml, contains('<textarea'));
      expect(textareaHtml, contains('name="message"'));
      expect(textareaHtml, contains('Hello World!'));
      expect(textareaHtml, contains('rows="5"'));
      expect(textareaHtml, contains('cols="30"'));

      // EmailInput should render as <input type="email">
      expect(
        emailHtml,
        isNotEmpty,
        reason: 'EmailInput should not return empty string',
      );
      expect(emailHtml, contains('<input type="email"'));
      expect(emailHtml, contains('name="email"'));
      expect(emailHtml, contains('value="test@example.com"'));
      expect(emailHtml, contains('class="email-field"'));

      // CheckboxInput should render as <input type="checkbox">
      expect(
        checkboxHtml,
        isNotEmpty,
        reason: 'CheckboxInput should not return empty string',
      );
      expect(checkboxHtml, contains('<input type="checkbox"'));
      expect(checkboxHtml, contains('name="subscribe"'));
      expect(
        checkboxHtml,
        contains('checked'),
      ); // Should be checked since value is true

      print('✅ Widget DefaultView fallbacks work correctly');
      print(
        'TextInput HTML: ${textHtml.substring(0, math.min(100, textHtml.length))}...',
      );
      print(
        'Textarea HTML: ${textareaHtml.substring(0, math.min(100, textareaHtml.length))}...',
      );
      print(
        'EmailInput HTML: ${emailHtml.substring(0, math.min(100, emailHtml.length))}...',
      );
      print(
        'CheckboxInput HTML: ${checkboxHtml.substring(0, math.min(100, checkboxHtml.length))}...',
      );
    });
  });
}
