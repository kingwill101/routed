# Widget Showcase

## Overview

The Widget Showcase is a comprehensive interactive demonstration of **all form field types and widgets** available in
class_view.

## Purpose

- 📚 **Reference** - See all available field types in one place
- 🧪 **Testing** - Experiment with different field configurations
- 📖 **Learning** - Understand widget behavior and validation
- 🎨 **UI/UX** - Preview how fields render and behave

## Accessing the Widget Showcase

### API Endpoint (JSON)

```bash
# View the form metadata
GET http://localhost:8080/api/widgets

# Submit the form
POST http://localhost:8080/api/widgets
Content-Type: application/json

{
  "text_basic": "Hello World",
  "email": "user@example.com",
  "checkbox": true,
  ...
}
```

### Web Interface (HTML)

```bash
# Interactive form interface
GET http://localhost:8080/widgets
```

## Field Types Demonstrated

### 1. Text Input Fields

#### CharField (Basic)

```dart
'text_basic': CharField<String>(
  label: 'Basic Text Field',
  helpText: 'Simple text input with no constraints',
  initial: 'Default value',
)
```

#### CharField (Required)

```dart
'text_required': CharField<String>(
  label: 'Required Text Field',
  required: true,
  errorMessages: {
    'required': 'Please provide a value',
  },
)
```

#### CharField (Max Length)

```dart
'text_max_length': CharField<String>(
  label: 'Text with Max Length',
  maxLength: 50,
  helpText: 'Maximum 50 characters allowed',
)
```

#### CharField (Min Length)

```dart
'text_min_length': CharField<String>(
  label: 'Text with Min Length',
  minLength: 10,
  helpText: 'Minimum 10 characters required',
)
```

### 2. Specialized Text Fields

#### EmailField

```dart
'email': EmailField(
  label: 'Email Address',
  required: true,
  errorMessages: {
    'invalid': 'Please enter a valid email address',
  },
)
```

#### URLField

```dart
'url': URLField(
  label: 'Website URL',
  helpText: 'Enter a valid URL (http:// or https://)',
)
```

#### SlugField

```dart
'slug': SlugField(
  label: 'URL Slug',
  helpText: 'URL-friendly identifier (lowercase, hyphens)',
  maxLength: 100,
)
```

#### TextAreaField

```dart
'textarea': TextAreaField(
  label: 'Long Text / Description',
  maxLength: 1000,
  rows: 5,
)
```

### 3. Boolean Fields

#### BooleanField (Required)

```dart
'checkbox': BooleanField(
  label: 'Accept Terms and Conditions',
  required: true,
  initial: false,
)
```

#### BooleanField (Optional)

```dart
'checkbox_optional': BooleanField(
  label: 'Subscribe to Newsletter',
  required: false,
  initial: true,
)
```

### 4. Choice Fields

#### ChoiceField (Single Select)

```dart
'choice_single': ChoiceField<String>(
  label: 'Single Choice (Dropdown)',
  choices: [
    ('option1', 'Option 1'),
    ('option2', 'Option 2'),
    ('option3', 'Option 3'),
  ],
  required: true,
)
```

#### MultipleChoiceField

```dart
'choice_multiple': MultipleChoiceField<String>(
  label: 'Multiple Choice',
  choices: [
    ('red', 'Red'),
    ('green', 'Green'),
    ('blue', 'Blue'),
  ],
  initial: ['red', 'blue'],
)
```

### 5. Numeric Fields

#### IntegerField (Basic)

```dart
'integer_basic': IntegerField(
  label: 'Integer Number',
  initial: 42,
)
```

#### IntegerField (Range)

```dart
'integer_range': IntegerField(
  label: 'Integer with Range',
  minValue: 1,
  maxValue: 100,
  required: true,
)
```

#### DecimalField

```dart
'decimal': DecimalField(
  label: 'Decimal Number',
  maxDigits: 10,
  decimalPlaces: 2,
  initial: 99.99,
)
```

#### DecimalField (Price)

```dart
'price': DecimalField(
  label: 'Price (USD)',
  maxDigits: 10,
  decimalPlaces: 2,
  minValue: 0.01,
  initial: 19.99,
)
```

### 6. Date/Time Fields

#### DateField

```dart
'date': DateField(
  label: 'Date',
  helpText: 'Select a date (YYYY-MM-DD)',
  required: true,
)
```

#### TimeField

```dart
'time': TimeField(
  label: 'Time',
  helpText: 'Select a time (HH:MM)',
)
```

#### DateTimeField

```dart
'datetime': DateTimeField(
  label: 'Date and Time',
  helpText: 'Select both date and time',
)
```

### 7. File Upload Fields

#### FileField

```dart
'file': FileField(
  label: 'File Upload',
  maxSize: 5 * 1024 * 1024, // 5MB
)
```

#### ImageField

```dart
'image': ImageField(
  label: 'Image Upload',
  maxSize: 2 * 1024 * 1024, // 2MB
  allowedExtensions: ['.jpg', '.jpeg', '.png', '.gif'],
)
```

### 8. Special Fields

#### UUIDField

```dart
'uuid': UUIDField(
  label: 'UUID',
  helpText: 'Universally Unique Identifier',
)
```

#### JSONField

```dart
'json': JSONField(
  label: 'JSON Data',
  helpText: 'Enter valid JSON data',
)
```

### 9. Field States

#### Disabled Field

```dart
'disabled_field': CharField<String>(
  label: 'Disabled Field',
  disabled: true,
  initial: 'This field cannot be edited',
)
```

#### Hidden Field

```dart
'hidden_field': CharField<String>(
  label: 'Hidden Field',
  initial: 'secret_value',
  // Rendered with HiddenInput widget
)
```

## Usage Examples

### Test All Fields (API)

```bash
curl -X POST http://localhost:8080/api/widgets \
  -H "Content-Type: application/json" \
  -d '{
    "text_basic": "Sample text",
    "text_required": "Required value",
    "email": "test@example.com",
    "url": "https://example.com",
    "checkbox": true,
    "choice_single": "option1",
    "choice_multiple": ["red", "blue"],
    "integer_basic": 42,
    "integer_range": 50,
    "decimal": 99.99,
    "price": 19.99,
    "date": "2024-01-01",
    "time": "14:30",
    "datetime": "2024-01-01T14:30:00",
    "slug": "my-url-slug"
  }'
```

### Test Validation Errors

```bash
# Missing required fields
curl -X POST http://localhost:8080/api/widgets \
  -H "Content-Type: application/json" \
  -d '{
    "text_basic": "test"
  }'

# Response:
{
  "success": false,
  "message": "Form validation failed",
  "errors": {...},
  "field_errors": {
    "text_required": ["This field is required"],
    "email": ["This field is required"],
    ...
  }
}
```

### Test Field Constraints

```bash
# Integer out of range
{
  "integer_range": 150  # Max is 100
}

# Email invalid
{
  "email": "not-an-email"
}

# Text too short
{
  "text_min_length": "short"  # Min is 10 chars
}
```

## Response Format

### Success Response

```json
{
  "success": true,
  "message": "Widget showcase form submitted successfully!",
  "submitted_data": {
    "text_basic": "Sample text",
    "email": "test@example.com",
    ...
  },
  "field_types": {
    "text_basic": "CharField<String>",
    "email": "EmailField",
    "checkbox": "BooleanField",
    ...
  }
}
```

### Error Response

```json
{
  "success": false,
  "message": "Form validation failed",
  "errors": ["Form has validation errors"],
  "field_errors": {
    "email": ["Enter a valid email address"],
    "integer_range": ["Ensure this value is less than or equal to 100"]
  }
}
```

## Web Interface Features

When accessing `/widgets` in a browser:

- ✅ Interactive form with all field types
- ✅ Real-time field validation
- ✅ Visual error display
- ✅ Help text for each field
- ✅ Success confirmation page
- ✅ Responsive design

## Use Cases

### For Developers

- Quick reference for field syntax
- Test field behavior before implementing
- Copy-paste examples for your forms
- Understand validation rules

### For Designers

- See how fields render
- Test UX flows
- Verify accessibility
- Check responsive behavior

### For Testing

- Validate all field types work correctly
- Test edge cases and error handling
- Verify validation rules
- Check error messages

## Field Configuration Options

All fields support these common options:

| Option          | Type   | Description                   |
|-----------------|--------|-------------------------------|
| `label`         | String | Display label for the field   |
| `required`      | bool   | Whether the field is required |
| `initial`       | T      | Default/initial value         |
| `helpText`      | String | Help text displayed to user   |
| `disabled`      | bool   | Whether field is disabled     |
| `errorMessages` | Map    | Custom error messages         |
| `validators`    | List   | Custom validators             |

## Extending the Showcase

To add more field examples:

1. Add the field to `WidgetShowcaseForm.fields`
2. Update the documentation
3. Add test cases

```dart
'my_custom_field': MyCustomField(
  label: 'Custom Field',
  helpText: 'Description of custom field',
  // ... field-specific options
)
```

## Related Documentation

- [Forms Guide](../../../docs/forms.md)
- [Field Reference](../../../docs/fields.md)
- [Widget Reference](../../../docs/widgets.md)
- [Validation Guide](../../../docs/validation.md)

---

**Widget Showcase** - Your interactive field reference! 🎨
