import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_class_view/shelf_class_view.dart';
import 'package:shelf_router/shelf_router.dart';

/// Contact message model
class ContactMessage {
  final String name;
  final String email;
  final String subject;
  final String message;

  ContactMessage({
    required this.name,
    required this.email,
    required this.subject,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'subject': subject,
    'message': message,
  };
}

/// Simple field implementation for the example
class SimpleTextField extends Field<String> {
  SimpleTextField({
    super.label,
    super.helpText,
    super.required = true,
    super.disabled = false,
    super.initial,
    super.validators,
    String name = 'text_field',
  }) : super(widget: TextInput(), name: name);

  @override
  String? toDart(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }

  @override
  Field<String> deepCopy() {
    return SimpleTextField(
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

/// Django-style form view with Laravel-style responses
class ContactFormView extends View with ContextMixin {
  @override
  List<String> get allowedMethods => ['GET', 'POST'];

  /// Create a contact form instance
  Form getForm([Map<String, dynamic>? data]) {
    final nameField = SimpleTextField(
      label: 'Your Name',
      name: 'name',
      required: true,
      helpText: 'Enter your full name',
      validators: [MinLengthValidator(2)],
    );

    final emailField = SimpleTextField(
      label: 'Email Address',
      name: 'email',
      required: true,
      helpText: 'We\'ll never share your email',
      validators: [EmailValidator()],
    );

    final subjectField = SimpleTextField(
      label: 'Subject',
      name: 'subject',
      required: true,
      helpText: 'Brief description of your inquiry',
      validators: [MinLengthValidator(5)],
    );

    final messageField = SimpleTextField(
      label: 'Message',
      name: 'message',
      required: true,
      helpText: 'Please describe your inquiry in detail',
      validators: [MinLengthValidator(10)],
    );

    return Form(
      isBound: data != null,
      data: data ?? {},
      files: {},
      fields: {
        'name': nameField,
        'email': emailField,
        'subject': subjectField,
        'message': messageField,
      },
    );
  }

  @override
  Future<void> get() async {
    final form = getForm();

    // 🎨 Django-style form rendering with HTML response
    response().view('contact_form.html', {
      'title': 'Contact Us',
      'form': form,
      'form_html': await form.asP(), // Django-style paragraph form
      'form_action': '/contact',
      'form_method': 'POST',
    });
  }

  @override
  Future<void> post() async {
    final formData = await getFormData();
    final form = getForm(formData);

    // Validate Django-style
    if (await form.isValid()) {
      try {
        // Create contact message from cleaned data
        final message = ContactMessage(
          name: form.cleanedData['name'] as String,
          email: form.cleanedData['email'] as String,
          subject: form.cleanedData['subject'] as String,
          message: form.cleanedData['message'] as String,
        );

        // In a real app, you'd save to database here
        print('📧 Contact message received: ${message.toJson()}');

        // 🎯 Success - show confirmation page
        response().status(201).view('contact_success.html', {
          'title': 'Message Sent Successfully!',
          'message': message,
        });
      } catch (e) {
        // 🚨 Server error - show form with error
        response().status(500).view('contact_form.html', {
          'title': 'Contact Us - Server Error',
          'form': form,
          'form_html': await form.asP(),
          'form_action': '/contact',
          'form_method': 'POST',
          'errors': ['Server error: ${e.toString()}'],
        });
      }
    } else {
      // 🚨 Validation failed - show form with errors
      response().status(422).view('contact_form.html', {
        'title': 'Contact Us - Please fix errors',
        'form': form,
        'form_html': await form.asP(), // Form now contains validation errors
        'form_action': '/contact',
        'form_method': 'POST',
        'validation_errors': form.errors,
      });
    }
  }
}

/// Simple info view
class InfoView extends View {
  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<void> get() async {
    response().view('info.html', {
      'title': 'Django-Style Forms + Laravel Response Example',
      'features': [
        '✅ Django-style form definition with fields',
        '✅ Built-in validation (required, email, min length)',
        '✅ Laravel-style response building',
        '✅ HTML template rendering with response().view()',
        '✅ Form error handling and display',
        '✅ Success/failure flows',
        '✅ Clean separation of concerns',
      ],
    });
  }
}

/// API endpoint to show form structure
class ContactApiView extends View {
  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<void> get() async {
    final contactForm = ContactFormView();
    final form = contactForm.getForm();

    // 🔥 JSON response showing form structure
    response().json({
      'form_fields': {
        for (final entry in form.fields.entries)
          entry.key: {
            'type': entry.value.runtimeType.toString(),
            'label': entry.value.label,
            'required': entry.value.required,
            'help_text': entry.value.helpText,
          },
      },
      'validation_demo': {
        'url': '/contact',
        'method': 'POST',
        'valid_data': {
          'name': 'John Doe',
          'email': 'john@example.com',
          'subject': 'Question about your service',
          'message':
              'I have a question about your service. Could you please help me?',
        },
        'invalid_data_examples': {
          'short_name': {'name': 'J'}, // Too short
          'invalid_email': {'email': 'not-an-email'},
          'short_subject': {'subject': 'Hi'}, // Too short
          'short_message': {'message': 'Help'}, // Too short
        },
      },
    });
  }
}

/// Set up routes with clean router extensions
Router setupRoutes() {
  final router = Router();

  // 🏠 Info page
  router.getView('/', () => InfoView());

  // 📝 Contact form (handles GET and POST)
  router.allView('/contact', () => ContactFormView());

  // 🔧 API endpoint to show form structure
  router.getView('/api/contact', () => ContactApiView());

  return router;
}

void main() async {
  // ✨ Clean route setup - just one line!
  final router = setupRoutes();

  // Start the server
  await io.serve(router.call, 'localhost', 8083);
  print('🚀 Django-Style Forms + Laravel Response Example');
  print('   Server running on http://localhost:8083');
  print('');
  print('📝 Try these endpoints:');
  print('  http://localhost:8083/           - Info about the example');
  print('  http://localhost:8083/contact    - Contact form (GET/POST)');
  print('  http://localhost:8083/api/contact - Form structure API');
  print('');
  print('🎯 This example demonstrates:');
  print('  ✅ Django-style forms with validation');
  print('  ✅ Laravel-style response().view() and response().json()');
  print('  ✅ Clean view syntax without context generics');
  print('  ✅ Automatic form rendering with form.asP()');
  print('  ✅ Form error handling and display');
  print('  ✅ HTTP status codes (201, 422, 500)');
  print('  ✅ Router extensions for clean setup');
}
