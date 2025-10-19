import 'package:class_view/class_view.dart';

/// Newsletter signup form for the home page
class NewsletterForm extends Form {
  NewsletterForm({Map<String, dynamic>? data, super.isBound = false})
    : super(
        data: data ?? {},
        files: {},
        fields: {
          'email': EmailField(
            label: 'Email Address',
            required: true,
            helpText: 'We\'ll never share your email address',
            widget: EmailInput(
              attrs: {
                'placeholder': 'Enter your email address...',
                'class':
                    'w-full px-4 py-3 border border-gray-200 rounded-lg bg-white focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all duration-200 placeholder-gray-400',
                'id': 'email',
              },
            ),
          ),
          'name': CharField(
            label: 'Name',
            required: false,
            helpText: 'Optional - helps us personalize our emails',
            maxLength: 100,
            widget: TextInput(
              attrs: {
                'placeholder': 'Your name (optional)...',
                'class':
                    'w-full px-4 py-3 border border-gray-200 rounded-lg bg-white focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all duration-200 placeholder-gray-400',
                'id': 'name',
              },
            ),
          ),
        },
      );

  @override
  void clean() {
    super.clean();

    final email = cleanedData['email'] as String?;
    final name = cleanedData['name'] as String?;

    if (email != null) {
      final domain = email.split('@').last.toLowerCase();
      final blockedDomains = ['spam.com', 'fake.com', 'test.invalid'];

      if (blockedDomains.contains(domain)) {
        addError(
          'email',
          'Email addresses from domain "$domain" are not allowed',
        );
      }
    }

    if (name != null && name.isNotEmpty) {
      if (name.length < 2) {
        addError('name', 'Name must be at least 2 characters long');
      }

      final lowerName = name.toLowerCase();
      if (lowerName.contains('test') || lowerName.contains('fake')) {
        addError('name', 'Please enter your real name');
      }
    }
  }
}
