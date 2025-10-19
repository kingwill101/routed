import 'package:class_view/class_view.dart';

/// Example demonstrating template-first form views
///
/// This example shows how form views default to HTML template rendering,
/// with JSON responses available as an override when needed.

/// A simple contact form
class ContactForm extends Form {
  ContactForm({Map<String, dynamic>? data, super.isBound = false})
    : super(
        data: data ?? {},
        files: {},
        fields: {
          'name': CharField<String>(required: true),
          'email': EmailField(required: true),
          'message': CharField<String>(required: true, maxLength: 1000),
        },
      );
}

/// DEFAULT BEHAVIOR: Template-first form view
/// This renders HTML templates automatically - no JSON handling needed!
class ContactFormView extends BaseFormView {
  @override
  String get templateName => 'contact_form.html';

  @override
  Form getForm([Map<String, dynamic>? data]) {
    return ContactForm(data: data, isBound: data != null);
  }

  @override
  Future<void> formValid(Form form) async {
    final contact = form as ContactForm;

    // Process the form (send email, save to database, etc.)
    print('Contact form submitted:');
    print('Name: ${contact.cleanedData['name']}');
    print('Email: ${contact.cleanedData['email']}');
    print('Message: ${contact.cleanedData['message']}');

    // Standard HTML redirect - template rendered automatically!
    redirect('/contact/success');
  }

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'page_title': 'Contact Us',
      'page_description': 'Get in touch with our team',
    };
  }
}

/// OVERRIDE: JSON API view when you need JSON responses
/// Extends View (not BaseFormView) for pure API behavior
class ContactApiView extends View {
  @override
  List<String> get allowedMethods => ['POST'];

  @override
  Future<void> post() async {
    try {
      final data = await getJsonBody();
      final form = ContactForm(data: data, isBound: true);

      if (await form.isValid()) {
        // Process the valid form
        print('API contact submitted: ${form.cleanedData}');

        // JSON response
        sendJson({
          'success': true,
          'message': 'Contact form submitted successfully',
          'data': form.cleanedData,
        });
      } else {
        // JSON error response
        sendJson({'success': false, 'errors': form.errors}, statusCode: 400);
      }
    } catch (e) {
      sendJson({'success': false, 'error': e.toString()}, statusCode: 500);
    }
  }
}

/// HYBRID: Handle both HTML forms and AJAX requests
class ContactHybridView extends BaseFormView {
  @override
  String get templateName => 'contact_form.html';

  @override
  Form getForm([Map<String, dynamic>? data]) {
    return ContactForm(data: data, isBound: data != null);
  }

  @override
  Future<void> formValid(Form form) async {
    final contact = form as ContactForm;

    // Process the form
    print('Hybrid contact submitted: ${contact.cleanedData}');

    // Check if this is an AJAX/JSON request
    final acceptHeader = await getHeader('Accept') ?? '';
    final isJsonRequest =
        acceptHeader.contains('application/json') ||
        acceptHeader.contains('*/*');

    if (isJsonRequest &&
        await getHeader('X-Requested-With') == 'XMLHttpRequest') {
      // Return JSON for AJAX requests
      sendJson({
        'success': true,
        'message': 'Form submitted successfully',
        'redirect': '/contact/success',
      });
    } else {
      // Standard HTML redirect for regular form submissions
      redirect('/contact/success');
    }
  }

  @override
  Future<void> formInvalid(Form form) async {
    final acceptHeader = await getHeader('Accept') ?? '';
    final isJsonRequest = acceptHeader.contains('application/json');

    if (isJsonRequest &&
        await getHeader('X-Requested-With') == 'XMLHttpRequest') {
      // Return JSON errors for AJAX requests
      sendJson({'success': false, 'errors': form.errors}, statusCode: 400);
    } else {
      // Standard template rendering for regular form submissions
      await super.formInvalid(form);
    }
  }
}

/// The corresponding HTML template would be:
///
/// ```html
/// <!-- contact_form.html -->
/// <!DOCTYPE html>
/// <html>
/// <head>
///   <title>{{ page_title }}</title>
///   <meta name="description" content="{{ page_description }}">
/// </head>
/// <body>
///   <h1>{{ page_title }}</h1>
///   <p>{{ page_description }}</p>
///
///   <form method="POST">
///     {{ form.asP }}  <!-- Form HTML automatically generated -->
///     <button type="submit">Send Message</button>
///   </form>
///
///   <!-- Optional: Add AJAX enhancement -->
///   <script>
///     document.querySelector('form').addEventListener('submit', async (e) => {
///       e.preventDefault();
///       const formData = new FormData(e.target);
///       const response = await fetch(e.target.action || '', {
///         method: 'POST',
///         headers: {
///           'Accept': 'application/json',
///           'X-Requested-With': 'XMLHttpRequest'
///         },
///         body: formData
///       });
///       const result = await response.json();
///       if (result.success) {
///         window.location.href = result.redirect;
///       } else {
///         // Handle errors...
///       }
///     });
///   </script>
/// </body>
/// </html>
/// ```

void main() {
  print('Template-First Form Views Example');
  print('===================================');
  print('');
  print('Form views default to HTML template rendering:');
  print('- ContactFormView: Pure HTML form (default behavior)');
  print('- ContactApiView: Pure JSON API (override)');
  print('- ContactHybridView: Supports both HTML and AJAX');
  print('');
  print('The template-first approach means you get beautiful web forms');
  print('by default, with JSON APIs available when you need them!');
}
