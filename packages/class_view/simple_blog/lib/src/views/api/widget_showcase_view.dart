import 'package:class_view/class_view.dart';

/// Comprehensive widget showcase demonstrating all available form fields
///
/// This view provides a living catalog of all form field types. Perfect for:
/// - Learning what field types are available
/// - Testing field behavior and validation
/// - Reference implementation
/// - API testing
///
/// Access: GET/POST /api/widgets
class WidgetShowcaseView extends View {
  @override
  List<String> get allowedMethods => ['GET', 'POST'];

  @override
  Future<void> get() async {
    final form = _createShowcaseForm();

    sendJson({
      'title': 'Widget Showcase - All Form Fields',
      'description':
          'Comprehensive demonstration of all class_view form field types',
      'field_count': form.fields.length,
      'sections': [
        'Text Input Fields',
        'Boolean Fields',
        'Choice Fields',
        'Numeric Fields',
        'Date/Time Fields',
        'Special Fields',
      ],
      'field_info': _getFieldInfo(form),
      'usage': {
        'get': 'GET /api/widgets - View available fields',
        'post': 'POST /api/widgets - Submit with field data',
      },
      'example_payload': _getExamplePayload(),
    });
  }

  @override
  Future<void> post() async {
    final data = await getJsonBody();
    final form = Form(
      isBound: true,
      data: data,
      files: {},
      fields: _createShowcaseForm().fields,
    );

    await form.fullClean();

    if (form.errors.isEmpty) {
      // Convert DateTime objects to ISO strings for JSON serialization
      final cleanedData = <String, dynamic>{};
      for (final entry in form.cleanedData.entries) {
        final value = entry.value;
        if (value is DateTime) {
          cleanedData[entry.key] = value.toIso8601String();
        } else {
          cleanedData[entry.key] = value;
        }
      }

      sendJson({
        'success': true,
        'message': 'All fields validated successfully!',
        'submitted_data': cleanedData,
        'field_types': _getFieldTypes(form),
      }, statusCode: 200);
    } else {
      sendJson({
        'success': false,
        'message': 'Form validation failed',
        'errors': _formatErrors(form),
        'field_details': _getFieldValidationDetails(form),
      }, statusCode: 400);
    }
  }

  /// Create the comprehensive showcase form
  Form _createShowcaseForm() {
    return Form(
      isBound: false,
      data: {},
      files: {},
      fields: {
        // TEXT INPUT FIELDS
        'text_basic': CharField<String>(
          label: 'Basic Text Field',
          helpText: 'Simple text input with no constraints',
          required: false,
        ),

        'text_required': CharField<String>(
          label: 'Required Text Field',
          required: true,
          helpText: 'This field is required',
          validators: [MinLengthValidator(3)],
        ),

        'text_max_length': CharField<String>(
          label: 'Text with Max Length',
          maxLength: 50,
          helpText: 'Maximum 50 characters',
          required: false,
        ),

        'text_min_length': CharField<String>(
          label: 'Text with Min Length',
          minLength: 10,
          helpText: 'Minimum 10 characters',
          required: false,
          validators: [MinLengthValidator(10)],
        ),

        // EMAIL FIELD
        'email': EmailField(
          label: 'Email Address',
          required: true,
          helpText: 'Valid email required (e.g., user@example.com)',
        ),

        // URL FIELD
        'url': URLField(
          label: 'Website URL',
          helpText: 'Valid URL (http:// or https://)',
          required: false,
        ),

        // BOOLEAN FIELDS
        'checkbox': BooleanField(
          label: 'Accept Terms',
          required: true,
          helpText: 'Must accept to continue',
        ),

        'checkbox_optional': BooleanField(
          label: 'Subscribe to Newsletter',
          helpText: 'Optional subscription',
          required: false,
        ),

        // CHOICE FIELDS
        'choice_single': ChoiceField<String>(
          label: 'Single Choice',
          choices: [
            ['option1', 'Option 1'],
            ['option2', 'Option 2'],
            ['option3', 'Option 3'],
          ],
          helpText: 'Select one option',
          required: true,
        ),

        'choice_multiple': MultipleChoiceField(
          label: 'Multiple Choice',
          choices: [
            ['red', 'Red'],
            ['green', 'Green'],
            ['blue', 'Blue'],
            ['yellow', 'Yellow'],
          ],
          helpText: 'Select multiple options',
          required: false,
        ),

        // INTEGER FIELDS
        'integer_basic': IntegerField(
          label: 'Integer Number',
          helpText: 'Whole numbers only',
          required: false,
        ),

        'integer_range': IntegerField(
          label: 'Integer with Range',
          minValue: 1,
          maxValue: 100,
          helpText: 'Between 1 and 100',
          required: false,
          validators: [MinValueValidator<int>(1), MaxValueValidator<int>(100)],
        ),

        // DECIMAL FIELDS
        'decimal': DecimalField(
          label: 'Decimal Number',
          helpText: 'Decimal/floating point (e.g., 99.99)',
          maxDigits: 10,
          maxDecimalPlaces: 2,
          required: false,
        ),

        'price': DecimalField(
          label: 'Price (USD)',
          helpText: 'Price with 2 decimals (e.g., 19.99)',
          maxDigits: 10,
          maxDecimalPlaces: 2,
          required: false,
        ),

        // DATE/TIME FIELDS
        'date': DateField(
          label: 'Date',
          helpText: 'Format: YYYY-MM-DD (e.g., 2024-01-01)',
          required: false,
        ),

        'time': TimeField(
          label: 'Time',
          helpText: 'Format: HH:MM or HH:MM:SS (e.g., 14:30)',
          required: false,
        ),

        'datetime': DateTimeField(
          label: 'Date and Time',
          helpText: 'Format: YYYY-MM-DDTHH:MM:SS (e.g., 2024-01-01T14:30:00)',
          required: false,
        ),

        // SPECIAL FIELDS
        'slug': SlugField(
          label: 'URL Slug',
          helpText: 'URL-friendly (lowercase, hyphens, e.g., my-url-slug)',
          maxLength: 100,
          required: false,
        ),

        'uuid': UUIDField(
          label: 'UUID',
          helpText:
              'Universally Unique Identifier (e.g., 123e4567-e89b-12d3-a456-426614174000)',
          required: false,
        ),

        'json_data': JSONField(
          label: 'JSON Data',
          helpText: 'Valid JSON object or array (e.g., {"key": "value"})',
          required: false,
        ),
      },
    );
  }

  /// Get information about each field
  Map<String, Map<String, dynamic>> _getFieldInfo(Form form) {
    final info = <String, Map<String, dynamic>>{};

    for (final entry in form.fields.entries) {
      final field = entry.value;
      info[entry.key] = {
        'type': field.runtimeType.toString(),
        'label': field.label,
        'required': field.required,
        'help_text': field.helpText,
        'disabled': field.disabled,
      };
    }

    return info;
  }

  /// Get field type names
  Map<String, String> _getFieldTypes(Form form) {
    final types = <String, String>{};
    for (final entry in form.fields.entries) {
      types[entry.key] = entry.value.runtimeType.toString();
    }
    return types;
  }

  /// Get detailed validation info
  Map<String, dynamic> _getFieldValidationDetails(Form form) {
    final details = <String, dynamic>{};

    for (final entry in form.fields.entries) {
      final field = entry.value;
      final fieldDetails = <String, dynamic>{
        'type': field.runtimeType.toString(),
        'required': field.required,
      };

      details[entry.key] = fieldDetails;
    }

    return details;
  }

  /// Format form errors for JSON response
  List<String> _formatErrors(Form form) {
    final errorList = <String>[];
    for (final entry in form.errors.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is List) {
        for (final error in value) {
          errorList.add('$key: $error');
        }
      } else {
        errorList.add('$key: $value');
      }
    }
    return errorList;
  }

  /// Get example payload
  Map<String, dynamic> _getExamplePayload() {
    return {
      'text_basic': 'Sample text',
      'text_required': 'Required value here',
      'text_max_length': 'Under 50 chars',
      'text_min_length': 'At least 10 characters here',
      'email': 'user@example.com',
      'url': 'https://example.com',
      'checkbox': true,
      'checkbox_optional': false,
      'choice_single': 'option1',
      'choice_multiple': ['red', 'blue'],
      'integer_basic': 42,
      'integer_range': 50,
      'decimal': 99.99,
      'price': 19.99,
      'date': '2024-01-01',
      'time': '14:30',
      'datetime': '2024-01-01T14:30:00',
      'slug': 'my-url-slug',
      'uuid': '123e4567-e89b-12d3-a456-426614174000',
      'json_data': {'key': 'value'},
    };
  }
}
