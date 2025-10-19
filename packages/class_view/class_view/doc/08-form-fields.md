# Form Fields Reference

Form fields handle data validation, cleaning, and type conversion. Each field type provides specific validation rules
and can be paired with different widgets for various HTML representations.

## Core Field Concepts

### Field Lifecycle

Every field goes through these steps when processing data:

```dart
// 1. Raw input (from form submission)
final rawValue = 'john@example.com';

// 2. Convert to Dart type
final dartValue = field.toDart(rawValue); // String

// 3. Validate the value
await field.validate(dartValue); // Throws ValidationError if invalid

// 4. Clean the value
final cleanedValue = await field.clean(rawValue); // Final processed value
```

### Field Properties

All fields share common configuration options:

```dart
CharField(
  required: true,              // Whether field is mandatory
  initial: 'Default value',    // Default value when form is empty
  label: 'Custom Label',       // Override auto-generated label
  helpText: 'Guidance text',   // Help text shown with field
  errorMessages: {             // Custom error messages
    'required': 'This field cannot be empty',
    'invalid': 'Please enter valid text',
  },
  validators: [customValidator], // Additional validators
  disabled: false,             // Whether field should be disabled
  widget: CustomWidget(),      // Override default widget
)
```

## Text Fields

### CharField

Basic text field with length validation:

```dart
CharField(
  maxLength: 100,              // Maximum character length
  minLength: 5,                // Minimum character length
  stripWhitespace: true,       // Remove leading/trailing whitespace
  widget: TextInput(attrs: {
    'placeholder': 'Enter text...',
    'class': 'form-control',
  }),
)
```

**Default Widget**: `TextInput`
**Validates**: String length, required status
**Returns**: `String`

### EmailField

Email address field with built-in validation:

```dart
EmailField(
  widget: EmailInput(attrs: {
    'class': 'form-control',
    'placeholder': 'user@example.com',
  }),
)
```

**Default Widget**: `EmailInput`
**Validates**: Email format using RFC-compliant regex
**Returns**: `String` (validated email address)

### URLField

URL field with protocol validation:

```dart
URLField(
  schemes: ['http', 'https', 'ftp'], // Allowed URL schemes
  widget: URLInput(attrs: {
    'placeholder': 'https://example.com',
  }),
)
```

**Default Widget**: `URLInput`
**Validates**: URL format and allowed schemes
**Returns**: `String` (validated URL)

### SlugField

URL-safe string field (letters, numbers, hyphens, underscores):

```dart
SlugField(
  maxLength: 50,
  allowUnicode: false,         // Allow non-ASCII characters
  helpText: 'Only letters, numbers, hyphens, and underscores allowed.',
)
```

**Default Widget**: `TextInput`
**Validates**: Slug format (alphanumeric + hyphens/underscores)
**Returns**: `String`

### RegexField

Text field validated against a regular expression:

```dart
RegexField(
  regex: r'^[A-Z]{2}\d{4}$',
  errorMessage: 'Enter format: AB1234',
  widget: TextInput(attrs: {
    'pattern': r'^[A-Z]{2}\d{4}$',
    'placeholder': 'AB1234',
  }),
)
```

**Default Widget**: `TextInput`
**Validates**: Pattern matching against provided regex
**Returns**: `String`

## Numeric Fields

### IntegerField

Integer field with range validation:

```dart
IntegerField(
  minValue: 0,                 // Minimum allowed value
  maxValue: 100,               // Maximum allowed value
  widget: NumberInput(attrs: {
    'min': '0',
    'max': '100',
    'step': '1',
  }),
)
```

**Default Widget**: `NumberInput`
**Validates**: Integer format, range constraints
**Returns**: `int`

### FloatField

Floating-point number field:

```dart
FloatField(
  minValue: 0.0,
  maxValue: 999.99,
  widget: NumberInput(attrs: {
    'min': '0',
    'max': '999.99',
    'step': '0.01',
  }),
)
```

**Default Widget**: `NumberInput`
**Validates**: Float format, range constraints
**Returns**: `double`

### DecimalField

Precise decimal field for financial calculations:

```dart
DecimalField(
  maxDigits: 10,               // Total number of digits
  decimalPlaces: 2,            // Number of decimal places
  widget: NumberInput(attrs: {
    'step': '0.01',
  }),
)
```

**Default Widget**: `NumberInput`
**Validates**: Decimal format, precision constraints
**Returns**: `Decimal` (from decimal package)

## Date and Time Fields

### DateField

Date field with flexible input formats:

```dart
DateField(
  inputFormats: [              // Accepted input formats
    'yyyy-MM-dd',
    'MM/dd/yyyy',
    'dd/MM/yyyy',
  ],
  widget: DateInput(attrs: {
    'type': 'date',
  }),
)
```

**Default Widget**: `DateInput`
**Validates**: Date format and validity
**Returns**: `DateTime` (date only, time set to midnight)

### TimeField

Time field for time-of-day values:

```dart
TimeField(
  inputFormats: [
    'HH:mm:ss',
    'HH:mm',
  ],
  widget: TimeInput(attrs: {
    'type': 'time',
  }),
)
```

**Default Widget**: `TimeInput`
**Validates**: Time format and validity
**Returns**: `TimeOfDay`

### DateTimeField

Combined date and time field:

```dart
DateTimeField(
  inputFormats: [
    'yyyy-MM-dd HH:mm:ss',
    'yyyy-MM-dd HH:mm',
  ],
  widget: DateTimeInput(attrs: {
    'type': 'datetime-local',
  }),
)
```

**Default Widget**: `DateTimeInput`
**Validates**: DateTime format and validity
**Returns**: `DateTime`

### DurationField

Duration field for time spans:

```dart
DurationField(
  helpText: 'Enter duration in format: HH:MM:SS or number of seconds',
)
```

**Default Widget**: `TextInput`
**Validates**: Duration format (various formats supported)
**Returns**: `Duration`

### SplitDateTimeField

Separate date and time inputs combined into one field:

```dart
SplitDateTimeField(
  dateField: DateField(),
  timeField: TimeField(),
  widget: SplitDateTimeWidget(
    dateWidget: DateInput(attrs: {'type': 'date'}),
    timeWidget: TimeInput(attrs: {'type': 'time'}),
  ),
)
```

**Default Widget**: `SplitDateTimeWidget`
**Validates**: Both date and time components
**Returns**: `DateTime`

## Choice Fields

### ChoiceField

Single selection from predefined options:

```dart
ChoiceField(
  choices: [
    ['small', 'Small (S)'],
    ['medium', 'Medium (M)'],
    ['large', 'Large (L)'],
    ['xlarge', 'Extra Large (XL)'],
  ],
  widget: Select(),            // or RadioSelect()
)
```

**Default Widget**: `Select`
**Validates**: Value exists in choices
**Returns**: Choice value (first element of choice tuple)

### MultipleChoiceField

Multiple selections from predefined options:

```dart
MultipleChoiceField(
  choices: [
    ['red', 'Red'],
    ['green', 'Green'],
    ['blue', 'Blue'],
    ['yellow', 'Yellow'],
  ],
  widget: CheckboxSelectMultiple(), // or SelectMultiple()
)
```

**Default Widget**: `SelectMultiple`
**Validates**: All selected values exist in choices
**Returns**: `List<String>` of selected values

### TypedChoiceField

Choice field with automatic type conversion:

```dart
TypedChoiceField<int>(
  choices: [
    [1, 'Priority 1 (Urgent)'],
    [2, 'Priority 2 (High)'],
    [3, 'Priority 3 (Normal)'],
    [4, 'Priority 4 (Low)'],
  ],
  coerce: (value) => int.parse(value.toString()),
)
```

**Default Widget**: `Select`
**Validates**: Value conversion and choice membership
**Returns**: Converted type (`int` in example)

### TypedMultipleChoiceField

Multiple choice field with type conversion:

```dart
TypedMultipleChoiceField<int>(
  choices: [
    [1, 'Feature A'],
    [2, 'Feature B'],
    [3, 'Feature C'],
  ],
  coerce: (value) => int.parse(value.toString()),
)
```

**Default Widget**: `SelectMultiple`
**Validates**: All values can be converted and exist in choices
**Returns**: `List<T>` of converted values

## Boolean Fields

### BooleanField

True/false field (checkbox):

```dart
BooleanField(
  required: false,             // Usually false for checkboxes
  label: 'I agree to the terms and conditions',
  widget: CheckboxInput(),
)
```

**Default Widget**: `CheckboxInput`
**Validates**: Boolean conversion
**Returns**: `bool`

### NullBooleanField

Three-state boolean (Yes/No/Unknown):

```dart
NullBooleanField(
  widget: NullBooleanSelect(),
)
```

**Default Widget**: `NullBooleanSelect`
**Validates**: Null, true, or false values
**Returns**: `bool?`

## File Fields

### FileField

Basic file upload field:

```dart
FileField(
  maxLength: 255,              // Max filename length
  allowEmptyFile: false,       // Allow zero-byte files
  widget: FileInput(attrs: {
    'accept': '.pdf,.doc,.docx,.txt',
  }),
)
```

**Default Widget**: `FileInput`
**Validates**: File presence, size constraints
**Returns**: File object (framework-specific)

### ImageField

Image file upload with image-specific validation:

```dart
ImageField(
  widget: ClearableFileInput(),
  helpText: 'Upload JPG, PNG, or GIF images only',
)
```

**Default Widget**: `ClearableFileInput`
**Validates**: File is a valid image format (via `class_view_image_field`)
**Returns**: Image file object (`ImageFormFile`)

> 💡 The `ImageField` implementation now ships as an optional add-on. Add the
> [`class_view_image_field`](https://pub.dev/packages/class_view_image_field)
> package to your pubspec and import
> `package:class_view_image_field/class_view_image_field.dart` to enable image
> decoding.

### FilePathField

Select from files in a specific directory:

```dart
FilePathField(
  path: '/uploads/documents',
  allowFiles: true,
  allowFolders: false,
  recursive: false,
  match: r'.*\.pdf$',          // Only PDF files
)
```

**Default Widget**: `Select`
**Validates**: Selected path exists and matches criteria
**Returns**: `String` (file path)

### MultipleFileField

Multiple file upload field:

```dart
MultipleFileField(
  widget: ClearableFileInput(attrs: {
    'multiple': true,
    'accept': '.jpg,.png,.gif',
  }),
)
```

**Default Widget**: `ClearableFileInput`
**Validates**: All uploaded files are valid
**Returns**: `List` of file objects

## Advanced Fields

### JSONField

Structured data field for JSON input:

```dart
JSONField(
  widget: Textarea(attrs: {
    'rows': 10,
    'cols': 80,
  }),
  helpText: 'Enter valid JSON data',
)
```

**Default Widget**: `Textarea`
**Validates**: Valid JSON format
**Returns**: `Map<String, dynamic>` or `List`

### GenericIPAddressField

IP address field supporting IPv4 and IPv6:

```dart
GenericIPAddressField(
  protocol: 'both',            // 'IPv4', 'IPv6', or 'both'
  unpackIpv4: false,           // Unpack IPv4-mapped IPv6 addresses
)
```

**Default Widget**: `TextInput`
**Validates**: IP address format for specified protocol
**Returns**: `String` (validated IP address)

### UUIDField

UUID field with format validation:

```dart
UUIDField(
  widget: TextInput(attrs: {
    'placeholder': 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
  }),
)
```

**Default Widget**: `TextInput`
**Validates**: UUID format
**Returns**: `String` (UUID)

### ComboField

Validates against multiple fields (value must pass all):

```dart
ComboField(
  fields: [
    CharField(maxLength: 20),
    EmailField(),
  ],
)
```

**Validates**: Input against all provided fields
**Returns**: Value from last field in list

### MultiValueField

Combines multiple fields into one (like SplitDateTimeField):

```dart
class NameField extends MultiValueField<String> {
  NameField() : super(
    fields: [
      CharField(label: 'First Name'),
      CharField(label: 'Last Name'),
    ],
    widget: MultiWidget(widgets: [
      TextInput(attrs: {'placeholder': 'First'}),
      TextInput(attrs: {'placeholder': 'Last'}),
    ]),
  );
  
  @override
  String compress(List<String?> values) {
    return '${values[0] ?? ''} ${values[1] ?? ''}'.trim();
  }
}
```

**Widget**: Custom MultiWidget required
**Validates**: All component fields
**Returns**: Result of `compress()` method

## Custom Field Validation

### Built-in Validators

The validation system uses a `Validator<T>` pattern with structured error handling:

```dart
// String length validators
MinLengthValidator(5)           // Minimum 5 characters
MaxLengthValidator(100)         // Maximum 100 characters
ProhibitNullCharactersValidator() // No null characters (\u0000)

// Numeric validators
MinValueValidator(0)            // Minimum value 0
MaxValueValidator(100)          // Maximum value 100
StepValueValidator(5, offset: 2) // Must be multiple of 5, offset by 2

// Format validators
EmailValidator()                // Valid email format (uses acanthis package)
URLValidator()                  // Valid URL format
SlugValidator()                 // ASCII slug (letters, numbers, hyphens, underscores)
UnicodeSlugValidator()          // Unicode slug (supports international characters)
RegexValidator(RegExp(r'^\d+$')) // Custom regex pattern

// Decimal precision validator
DecimalValidator(maxDigits: 10, decimalPlaces: 2) // Max 10 digits, 2 decimal places

// File validators
ImageValidator()                // Valid image file
```

### ValidationError Structure

Validation errors use a structured format with field names and error lists:

```dart
class ValidationError implements Exception {
  final Map<String, List<String>> errors;
  final String message;
  final String code;
  
  ValidationError(
    this.errors, [
    this.message = 'Validation failed',
    this.code = 'validation_failed',
  ]);
}

// Example ValidationError
throw ValidationError({
  'email': ['Enter a valid email address.'],
  'password': [
    'Ensure this value has at least 8 characters.',
    'Password must contain at least one number.',
  ],
});
```

### Adding Validators to Fields

```dart
// Single validator
EmailField(
  validators: [EmailValidator()],
)

// Multiple validators
CharField(
  validators: [
    MinLengthValidator(5),
    MaxLengthValidator(50),
    ProhibitNullCharactersValidator(),
  ],
)

// Custom validator with built-ins
CharField(
  validators: [
    MinLengthValidator(8),
    RegexValidator(RegExp(r'(?=.*[0-9])')), // Must contain number
    CustomPasswordValidator(),
  ],
)
```

### Creating Custom Validators

```dart
class CustomPasswordValidator extends Validator<String> {
  @override
  Future<void> validate(String? value) async {
    if (value == null || value.isEmpty) return;
    
    // Check for uppercase letter
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      throw ValidationError({
        'password_uppercase': ['Password must contain at least one uppercase letter.']
      });
    }
    
    // Check for number
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      throw ValidationError({
        'password_number': ['Password must contain at least one number.']
      });
    }
    
    // Check for special character
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      throw ValidationError({
        'password_special': ['Password must contain at least one special character.']
      });
    }
  }
}

// Usage
PasswordField(
  validators: [
    MinLengthValidator(8),
    CustomPasswordValidator(),
  ],
)
```

### Async Validators

Validators support async operations for database checks, API calls, etc.:

```dart
class UniqueEmailValidator extends Validator<String> {
  final UserRepository userRepository;
  
  UniqueEmailValidator(this.userRepository);
  
  @override
  Future<void> validate(String? value) async {
    if (value == null || value.isEmpty) return;
    
    // Async database check
    final existingUser = await userRepository.findByEmail(value);
    if (existingUser != null) {
      throw ValidationError({
        'unique_email': ['A user with this email already exists.']
      });
    }
  }
}

// Usage
EmailField(
  validators: [
    EmailValidator(),
    UniqueEmailValidator(userRepository),
  ],
)
```

### Conditional Validators

```dart
class ConditionalValidator extends Validator<String> {
  final String dependentField;
  final dynamic expectedValue;
  final Validator<String> conditionalValidator;
  
  ConditionalValidator({
    required this.dependentField,
    required this.expectedValue,
    required this.conditionalValidator,
  });
  
  @override
  Future<void> validate(String? value) async {
    // Note: This would need access to form context in real implementation
    final dependentValue = getFormFieldValue(dependentField);
    
    if (dependentValue == expectedValue) {
      await conditionalValidator.validate(value);
    }
  }
}

// Usage: Require phone number if contact method is 'phone'
CharField(
  validators: [
    ConditionalValidator(
      dependentField: 'contact_method',
      expectedValue: 'phone',
      conditionalValidator: MinLengthValidator(10),
    ),
  ],
)
```

### Field-Level Cleaning

Fields can override the `clean` method for complex validation logic:

```dart
class CustomEmailField extends EmailField {
  final List<String> allowedDomains;
  
  CustomEmailField({
    this.allowedDomains = const [],
    super.validators,
    super.widget,
  });
  
  @override
  Future<String?> clean(dynamic value) async {
    // Call parent validation first (including EmailValidator)
    final email = await super.clean(value);
    
    if (email != null && allowedDomains.isNotEmpty) {
      final domain = email.split('@').last;
      if (!allowedDomains.contains(domain)) {
        throw ValidationError({
          'invalid_domain': ['Email domain must be one of: ${allowedDomains.join(', ')}']
        });
      }
    }
    
    return email;
  }
}

// Usage
CustomEmailField(
  allowedDomains: ['company.com', 'partner.com'],
  validators: [EmailValidator()],
)
```

### Validator Composition

```dart
class CompositeValidator extends Validator<String> {
  final List<Validator<String>> validators;
  
  CompositeValidator(this.validators);
  
  @override
  Future<void> validate(String? value) async {
    final errors = <String, List<String>>{};
    
    for (final validator in validators) {
      try {
        await validator.validate(value);
      } catch (e) {
        if (e is ValidationError) {
          // Merge errors
          e.errors.forEach((key, messages) {
            errors[key] = [...(errors[key] ?? []), ...messages];
          });
        }
      }
    }
    
    if (errors.isNotEmpty) {
      throw ValidationError(errors);
    }
  }
}

// Usage
CharField(
  validators: [
    CompositeValidator([
      MinLengthValidator(8),
      RegexValidator(RegExp(r'[A-Z]')), // Uppercase
      RegexValidator(RegExp(r'[0-9]')), // Number
      RegexValidator(RegExp(r'[!@#$%^&*]')), // Special char
    ]),
  ],
)
```

## Field Inheritance Patterns

### Base Field Classes

```dart
// Base field for all address fields
abstract class AddressField extends CharField {
  AddressField({
    super.maxLength = 255,
    super.required = true,
    super.helpText,
    super.widget,
  });
  
  @override
  Future<String?> clean(dynamic value) async {
    final cleaned = await super.clean(value);
    if (cleaned != null) {
      // Common address validation
      return cleaned.trim().replaceAll(RegExp(r'\s+'), ' ');
    }
    return cleaned;
  }
}

// Specific address fields
class StreetAddressField extends AddressField {
  StreetAddressField() : super(
    helpText: 'Street address including house/building number',
  );
}

class CityField extends AddressField {
  CityField() : super(
    maxLength: 100,
    helpText: 'City name',
  );
}
```

### Field Mixins

```dart
mixin RequiredIfMixin on Field {
  String get requiredIfField;
  dynamic get requiredIfValue;
  
  @override
  Future<void> validate(value) async {
    // Get the form instance (would need to be passed in)
    final formValue = getFormValue(requiredIfField);
    
    if (formValue == requiredIfValue && 
        (value == null || value.toString().isEmpty)) {
      throw ValidationError('This field is required when $requiredIfField is $requiredIfValue');
    }
    
    await super.validate(value);
  }
}

// Usage
class ConditionalEmailField extends EmailField with RequiredIfMixin {
  @override
  String get requiredIfField => 'contact_method';
  
  @override
  String get requiredIfValue => 'email';
}
```

## Performance Considerations

### Lazy Validation

```dart
class OptimizedField extends CharField {
  static final Map<String, bool> _validationCache = {};
  
  @override
  Future<void> validate(value) async {
    if (value == null) return super.validate(value);
    
    final cacheKey = 'validation_${value.hashCode}';
    if (_validationCache[cacheKey] == true) {
      return; // Skip expensive validation
    }
    
    await super.validate(value);
    await expensiveValidation(value);
    
    _validationCache[cacheKey] = true;
  }
}
```

### Async Validation Batching

```dart
class BatchValidatedField extends EmailField {
  static final List<String> _batchQueue = [];
  static Timer? _batchTimer;
  
  @override
  Future<void> validate(value) async {
    await super.validate(value);
    
    if (value != null) {
      _batchQueue.add(value);
      
      _batchTimer?.cancel();
      _batchTimer = Timer(Duration(milliseconds: 500), _processBatch);
    }
  }
  
  static Future<void> _processBatch() async {
    if (_batchQueue.isNotEmpty) {
      await validateEmailsBatch(_batchQueue);
      _batchQueue.clear();
    }
  }
}
```

## Testing Fields

### Testing Built-in Validators

```dart
test('MinLengthValidator validates minimum length', () async {
  final validator = MinLengthValidator(5);
  
  // Valid value
  await validator.validate('hello world'); // No exception
  
  // Invalid value
  expect(
    () => validator.validate('hi'),
    throwsA(isA<ValidationError>().having(
      (e) => e.errors['min_length'],
      'error message',
      contains('Ensure this value has at least 5 characters.'),
    )),
  );
});

test('EmailValidator validates email format', () async {
  final validator = EmailValidator();
  
  // Valid email
  await validator.validate('test@example.com'); // No exception
  
  // Invalid email
  expect(
    () => validator.validate('invalid-email'),
    throwsA(isA<ValidationError>().having(
      (e) => e.errors['invalid_email'],
      'error message',
      contains('Enter a valid email address.'),
    )),
  );
});

test('ValidationError contains structured errors', () async {
  final validator = MinLengthValidator(10);
  
  try {
    await validator.validate('short');
    fail('Expected ValidationError to be thrown');
  } catch (e) {
    expect(e, isA<ValidationError>());
    final validationError = e as ValidationError;
    
    expect(validationError.errors, hasLength(1));
    expect(validationError.errors['min_length'], isNotNull);
    expect(validationError.errors['min_length']![0], 
           contains('Ensure this value has at least 10 characters.'));
  }
});
```

### Testing Custom Validators

```dart
test('CustomPasswordValidator validates password complexity', () async {
  final validator = CustomPasswordValidator();
  
  // Valid password
  await validator.validate('MyPassword123!'); // No exception
  
  // Missing uppercase
  expect(
    () => validator.validate('mypassword123!'),
    throwsA(isA<ValidationError>().having(
      (e) => e.errors['password_uppercase'],
      'error message',
      isNotEmpty,
    )),
  );
  
  // Missing number
  expect(
    () => validator.validate('MyPassword!'),
    throwsA(isA<ValidationError>().having(
      (e) => e.errors['password_number'],
      'error message',
      isNotEmpty,
    )),
  );
  
  // Missing special character
  expect(
    () => validator.validate('MyPassword123'),
    throwsA(isA<ValidationError>().having(
      (e) => e.errors['password_special'],
      'error message',
      isNotEmpty,
    )),
  );
});
```

### Testing Async Validators

```dart
test('UniqueEmailValidator checks database uniqueness', () async {
  final mockRepository = MockUserRepository();
  final validator = UniqueEmailValidator(mockRepository);
  
  // Setup mock - email exists
  when(mockRepository.findByEmail('existing@example.com'))
      .thenAnswer((_) async => User(email: 'existing@example.com'));
  
  // Setup mock - email doesn't exist
  when(mockRepository.findByEmail('new@example.com'))
      .thenAnswer((_) async => null);
  
  // Test unique email (should pass)
  await validator.validate('new@example.com'); // No exception
  
  // Test duplicate email (should fail)
  expect(
    () => validator.validate('existing@example.com'),
    throwsA(isA<ValidationError>().having(
      (e) => e.errors['unique_email'],
      'error message',
      contains('A user with this email already exists.'),
    )),
  );
});
```

### Testing Field Validation

```dart
test('EmailField validates email format', () async {
  final field = EmailField(validators: [EmailValidator()]);
  
  // Valid email
  final validEmail = await field.clean('test@example.com');
  expect(validEmail, equals('test@example.com'));
  
  // Invalid email
  expect(
    () => field.clean('invalid-email'),
    throwsA(isA<ValidationError>()),
  );
});

test('CharField with multiple validators', () async {
  final field = CharField(
    validators: [
      MinLengthValidator(5),
      MaxLengthValidator(20),
      ProhibitNullCharactersValidator(),
    ],
  );
  
  // Valid value
  final validValue = await field.clean('hello world');
  expect(validValue, equals('hello world'));
  
  // Too short
  expect(
    () => field.clean('hi'),
    throwsA(isA<ValidationError>()),
  );
  
  // Too long
  expect(
    () => field.clean('this is way too long for the field'),
    throwsA(isA<ValidationError>()),
  );
  
  // Null character
  expect(
    () => field.clean('hello\u0000world'),
    throwsA(isA<ValidationError>()),
  );
});
```

### Testing Custom Fields

```dart
test('CustomEmailField validates domain restrictions', () async {
  final field = CustomEmailField(
    allowedDomains: ['company.com', 'partner.com'],
    validators: [EmailValidator()],
  );
  
  // Valid domain
  final validEmail = await field.clean('user@company.com');
  expect(validEmail, equals('user@company.com'));
  
  // Invalid domain
  expect(
    () => field.clean('user@gmail.com'),
    throwsA(isA<ValidationError>().having(
      (e) => e.errors['invalid_domain'],
      'error message',
      contains('Email domain must be one of: company.com, partner.com'),
    )),
  );
  
  // Invalid email format (should fail EmailValidator first)
  expect(
    () => field.clean('invalid-email'),
    throwsA(isA<ValidationError>().having(
      (e) => e.errors['invalid_email'],
      'error message',
      isNotEmpty,
    )),
  );
});
```

### Testing ValidationError Handling

```dart
test('ValidationError aggregates multiple field errors', () {
  final error = ValidationError({
    'email': ['Enter a valid email address.'],
    'password': [
      'Ensure this value has at least 8 characters.',
      'Password must contain at least one number.',
    ],
  });
  
  expect(error.errors, hasLength(2));
  expect(error.errors['email'], hasLength(1));
  expect(error.errors['password'], hasLength(2));
  
  final errorMessages = error.errorMessages;
  expect(errorMessages, contains('email: Enter a valid email address.'));
  expect(errorMessages, contains('password: Ensure this value has at least 8 characters., Password must contain at least one number.'));
});

test('ValidationError toString provides readable output', () {
  final error = ValidationError({
    'username': ['This field is required.'],
  });
  
  final message = error.toString();
  expect(message, startsWith('Validation failed:'));
  expect(message, contains('username: This field is required.'));
});
```

## What's Next?

- **[Form Widgets](09-form-widgets.md)** - Complete widget reference and customization
- **[Advanced Forms](10-advanced-forms.md)** - Complex forms and validation patterns
- **[Testing Forms](12-testing.md)** - Testing strategies for forms and fields

---

← [Forms Overview](07-forms-overview.md) | **Next: [Form Widgets](09-form-widgets.md)** → 
