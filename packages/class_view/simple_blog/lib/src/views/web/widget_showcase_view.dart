import 'package:class_view/class_view.dart';

/// Web view showcasing all available form widgets and fields
/// Demonstrates interactive form rendering with validation
class WebWidgetShowcaseView extends BaseFormView {
  @override
  List<String> get allowedMethods => ['GET', 'POST'];

  @override
  String get templateName => 'forms/widget_showcase';

  @override
  Form getForm([Map<String, dynamic>? data]) {
    return Form(
      isBound: data != null,
      data: data ?? {},
      files: {},
      renderer: null,
      fields: {
        // Text Input Fields
        'text_basic': CharField(
          label: 'Basic Text',
          helpText: 'A simple text field',
          required: false,
        ),
        'text_required': CharField(
          label: 'Required Text',
          helpText: 'This field is required (min 3 characters)',
          required: true,
          validators: [MinLengthValidator(3)],
        ),
        'text_maxlength': CharField(
          label: 'Text with Max Length',
          helpText: 'Maximum 50 characters',
          maxLength: 50,
          required: false,
        ),
        'text_minlength': CharField(
          label: 'Text with Min Length',
          helpText: 'Minimum 10 characters',
          minLength: 10,
          required: false,
          validators: [MinLengthValidator(10)],
        ),

        // Email Field
        'email': EmailField(
          label: 'Email Address',
          helpText: 'Enter a valid email address (e.g., user@example.com)',
          required: true,
        ),

        // URL Field
        'website': URLField(
          label: 'Website URL',
          helpText: 'Enter a valid URL (e.g., https://example.com)',
          required: false,
        ),

        // Boolean Fields
        'checkbox': BooleanField(
          label: 'Accept Terms',
          helpText: 'This checkbox is required',
          required: true,
        ),
        'newsletter': BooleanField(
          label: 'Subscribe to Newsletter',
          helpText: 'Optional subscription',
          required: false,
        ),

        // Choice Fields
        'choice_single': ChoiceField(
          label: 'Single Choice',
          helpText: 'Select one option',
          choices: [
            ['option1', 'First Option'],
            ['option2', 'Second Option'],
            ['option3', 'Third Option'],
          ],
          required: true,
        ),
        'choice_multiple': MultipleChoiceField(
          name: 'choice_multiple',
          label: 'Multiple Choice',
          helpText: 'Select one or more options',
          choices: [
            ['red', 'Red'],
            ['green', 'Green'],
            ['blue', 'Blue'],
            ['yellow', 'Yellow'],
          ],
          required: false,
        ),

        // Integer Fields
        'integer_basic': IntegerField(
          label: 'Basic Integer',
          helpText: 'Enter any whole number',
          required: false,
        ),
        'integer_range': IntegerField(
          label: 'Integer with Range',
          helpText: 'Enter a number between 1 and 100',
          minValue: 1,
          maxValue: 100,
          required: false,
          validators: [MinValueValidator<int>(1), MaxValueValidator<int>(100)],
        ),

        // Decimal Field
        'decimal': DecimalField(
          label: 'Decimal Number',
          helpText: 'Enter a decimal number (e.g., 19.99)',
          required: false,
          maxDigits: 10,
          maxDecimalPlaces: 2,
        ),

        'price': DecimalField(
          label: 'Price (USD)',
          helpText: 'Price with 2 decimals (e.g., 19.99)',
          maxDigits: 10,
          maxDecimalPlaces: 2,
          required: false,
        ),

        // Date and Time Fields
        'date': DateField(
          label: 'Date',
          helpText: 'Select a date (YYYY-MM-DD, e.g., 2024-01-01)',
          required: false,
        ),
        'time': TimeField(
          label: 'Time',
          helpText: 'Enter a time (HH:MM:SS or HH:MM, e.g., 14:30)',
          required: false,
        ),
        'datetime': DateTimeField(
          label: 'Date and Time',
          helpText:
              'Enter date and time (YYYY-MM-DDTHH:MM:SS, e.g., 2024-01-01T14:30:00)',
          required: false,
        ),

        // Special Fields
        'slug': SlugField(
          label: 'Slug',
          helpText:
              'Enter a URL-friendly slug (lowercase, hyphens, e.g., my-url-slug)',
          required: false,
          maxLength: 100,
        ),
        'uuid': UUIDField(
          label: 'UUID',
          helpText:
              'Enter a valid UUID (e.g., 123e4567-e89b-12d3-a456-426614174000)',
          required: false,
        ),
        'json_data': JSONField(
          label: 'JSON Data',
          helpText: 'Enter valid JSON (e.g., {"key": "value"})',
          required: false,
        ),
      },
    );
  }

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final fieldCategoriesData = _getFieldCategories();
    final queryParams = await getQueryParams();

    // Get the current form to check for validation errors
    final form = await getCurrentForm();
    final formContext = await form.getContext();

    // Extract field errors for display
    final fieldErrors = <Map<String, String>>[];
    if (formContext['fields'] != null) {
      for (final fieldData in formContext['fields'] as List) {
        if (fieldData['has_errors'] == true && fieldData['errors'] != null) {
          final errors = fieldData['errors'] as List;
          for (final error in errors) {
            fieldErrors.add({
              'field': fieldData['label'] ?? fieldData['name'],
              'message': error.toString(),
            });
          }
        }
      }
    }

    // Add non-field errors
    if (formContext['errors'] != null) {
      for (final error in formContext['errors'] as List) {
        fieldErrors.add({'field': 'Form', 'message': error.toString()});
      }
    }

    return {
      'page_title': 'Widget Showcase',
      'page_description':
          'Interactive demonstration of all available form fields and widgets',
      'success': queryParams['success'],
      'validation_errors': fieldErrors,
      ...fieldCategoriesData,
    };
  }

  Map<String, dynamic> _getFieldCategories() {
    return {
      'categories': [
        {
          'name': 'Text Fields',
          'fields': [
            {
              'name': 'text_basic',
              'description': 'Simple text input without validation',
            },
            {'name': 'text_required', 'description': 'Required text field'},
            {
              'name': 'text_maxlength',
              'description': 'Text limited to 50 characters',
            },
            {
              'name': 'text_minlength',
              'description': 'Text requiring at least 10 characters',
            },
            {'name': 'email', 'description': 'Email validation'},
            {'name': 'website', 'description': 'URL validation'},
          ],
        },
        {
          'name': 'Boolean Fields',
          'fields': [
            {'name': 'checkbox', 'description': 'Required checkbox'},
            {'name': 'newsletter', 'description': 'Optional checkbox'},
          ],
        },
        {
          'name': 'Choice Fields',
          'fields': [
            {
              'name': 'choice_single',
              'description': 'Single selection dropdown',
            },
            {
              'name': 'choice_multiple',
              'description': 'Multiple selection checkbox group',
            },
          ],
        },
        {
          'name': 'Numeric Fields',
          'fields': [
            {'name': 'integer_basic', 'description': 'Any whole number'},
            {'name': 'integer_range', 'description': 'Integer between 0-100'},
            {'name': 'decimal', 'description': 'Decimal/float number'},
          ],
        },
        {
          'name': 'Date & Time Fields',
          'fields': [
            {'name': 'date', 'description': 'Date picker (YYYY-MM-DD)'},
            {'name': 'time', 'description': 'Time input (HH:MM:SS)'},
            {'name': 'datetime', 'description': 'Combined date and time'},
          ],
        },
        {
          'name': 'Special Fields',
          'fields': [
            {'name': 'slug', 'description': 'URL-friendly identifier'},
            {'name': 'uuid', 'description': 'UUID validation'},
            {'name': 'json_data', 'description': 'JSON validation'},
          ],
        },
      ],
    };
  }

  @override
  Future<void> formValid(Form form) async {
    // Redirect back to showcase with success message
    redirect('/widgets?success=true');
  }
}
