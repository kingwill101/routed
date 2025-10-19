# Forms Overview

Class View provides a comprehensive form system for HTML rendering and validation, inspired by Django's forms framework.
Forms handle data collection, validation, and HTML generation with a clean separation between fields, widgets, and
rendering logic.

## Forms Philosophy

The forms system is built around three core concepts:

- **Forms**: Containers that group fields and handle validation
- **Fields**: Handle data validation and cleaning
- **Widgets**: Handle HTML rendering and user interface

This separation allows you to mix and match validation logic with different HTML representations.

```dart
// A field defines validation, a widget defines HTML rendering
class ContactForm extends Form {
  ContactForm({super.data, super.files}) : super(
    fields: {
      'name': CharField(
        maxLength: 100,
        widget: TextInput(attrs: {'class': 'form-control'}),
      ),
      'email': EmailField(
        widget: EmailInput(attrs: {'class': 'form-control'}),
      ),
      'message': CharField(
        widget: Textarea(attrs: {'rows': 5, 'class': 'form-control'}),
      ),
    },
  );
}
```

## Basic Form Usage

### Creating a Form

```dart
class UserProfileForm extends Form {
  UserProfileForm({super.data, super.files}) : super(
    fields: {
      'username': CharField(
        maxLength: 30,
        helpText: 'Required. 30 characters or fewer.',
      ),
      'email': EmailField(),
      'bio': CharField(
        required: false,
        widget: Textarea(attrs: {'rows': 4}),
      ),
      'website': URLField(required: false),
      'birth_date': DateField(required: false),
    },
  );
}
```

### Using Forms in Views

```dart
class ProfileView extends View with ContextMixin {
  @override
  Future<void> get() async {
    final form = UserProfileForm();
    
    sendHtml('''
      <h1>Update Profile</h1>
      ${await form.asP()}
    ''');
  }
  
  @override
  Future<void> post() async {
    final data = await getJsonBody(); // or form data
    final form = UserProfileForm(data: data);
    
    if (await form.isValid()) {
      // Save the data
      await saveUserProfile(form.cleanedData);
      redirect('/profile/success');
    } else {
      // Re-render with errors
      sendHtml('''
        <h1>Update Profile</h1>
        ${await form.asP()}
      ''');
    }
  }
}
```

## Form Rendering

Forms provide multiple HTML rendering layouts:

### As Paragraphs (`asP()`)

```dart
final form = ContactForm();
final html = await form.asP();
// Generates:
// <p>
//   <label for="id_name">Name:</label>
//   <input type="text" name="name" id="id_name" maxlength="100">
// </p>
// <p>
//   <label for="id_email">Email:</label>
//   <input type="email" name="email" id="id_email">
// </p>
```

### As Table Rows (`asTable()`)

```dart
final html = await form.asTable();
// Generates table rows (wrap in <table> yourself):
// <tr>
//   <th><label for="id_name">Name:</label></th>
//   <td><input type="text" name="name" id="id_name"></td>
// </tr>
```

### As List Items (`asUl()`)

```dart
final html = await form.asUl();
// Generates list items (wrap in <ul> yourself):
// <li>
//   <label for="id_name">Name:</label>
//   <input type="text" name="name" id="id_name">
// </li>
```

### As Divs (`asDiv()`)

```dart
final html = await form.asDiv();
// Generates:
// <div>
//   <label for="id_name">Name:</label>
//   <input type="text" name="name" id="id_name">
// </div>
```

### Individual Field Rendering

```dart
final form = ContactForm();

// Render individual fields
final nameField = form['name'];
print(await nameField.asWidget()); // Just the input
print(nameField.renderLabel());     // Just the label
print(await nameField.renderErrors()); // Just error messages
print(nameField.renderHelpText());  // Just help text

// Complete field HTML
print(await nameField.toHtml()); // Label + input + help + errors
```

## Fields Reference

### Text Fields

```dart
// Basic text input
CharField(
  maxLength: 100,
  minLength: 5,
  widget: TextInput(attrs: {'placeholder': 'Enter text...'}),
)

// Email field with validation
EmailField(
  widget: EmailInput(attrs: {'class': 'email-input'}),
)

// URL field
URLField(
  widget: URLInput(attrs: {'placeholder': 'https://...'}),
)

// Slug field (URL-safe strings)
SlugField(
  maxLength: 50,
  helpText: 'Only letters, numbers, hyphens, and underscores.',
)

// Regular expression field
RegexField(
  regex: r'^[A-Z]{2}\d{4}$',
  errorMessage: 'Enter format: AB1234',
)
```

### Numeric Fields

```dart
// Integer field
IntegerField(
  minValue: 1,
  maxValue: 100,
  widget: NumberInput(attrs: {'step': '1'}),
)

// Float field
FloatField(
  minValue: 0.0,
  maxValue: 99.99,
  widget: NumberInput(attrs: {'step': '0.01'}),
)

// Decimal field for precise calculations
DecimalField(
  maxDigits: 10,
  decimalPlaces: 2,
  widget: NumberInput(attrs: {'step': '0.01'}),
)
```

### Date and Time Fields

```dart
// Date field
DateField(
  widget: DateInput(attrs: {'type': 'date'}),
)

// Time field
TimeField(
  widget: TimeInput(attrs: {'type': 'time'}),
)

// DateTime field
DateTimeField(
  widget: DateTimeInput(attrs: {'type': 'datetime-local'}),
)

// Duration field
DurationField(
  helpText: 'Enter in HH:MM:SS format',
)
```

### Choice Fields

```dart
// Select field
ChoiceField(
  choices: [
    ('', 'Select a category'),
    ('tech', 'Technology'),
    ('sports', 'Sports'),
    ('news', 'News'),
  ],
  widget: Select(attrs: {'class': 'form-select'}),
)

// Radio buttons
ChoiceField(
  choices: [
    ('yes', 'Yes'),
    ('no', 'No'),
  ],
  widget: RadioSelect(),
)

// Checkbox list
MultipleChoiceField(
  choices: [
    ('python', 'Python'),
    ('dart', 'Dart'),
    ('typescript', 'TypeScript'),
  ],
  widget: CheckboxSelectMultiple(),
)
```

### File Upload Fields

```dart
// Single file upload
FileField(
  maxSize: 5 * 1024 * 1024, // 5MB
  allowedTypes: ['image/jpeg', 'image/png'],
  widget: FileInput(attrs: {'accept': 'image/*'}),
)

// Multiple file upload
MultipleFileField(
  maxFiles: 5,
  maxSize: 10 * 1024 * 1024, // 10MB
  allowedTypes: ['application/pdf'],
  widget: FileInput(attrs: {'multiple': true}),
)
```

### Composite Fields

```dart
// Address field group
class AddressField extends CompositeField {
  AddressField() : super(
    fields: {
      'street': CharField(maxLength: 100),
      'city': CharField(maxLength: 50),
      'state': CharField(maxLength: 2),
      'zip': CharField(maxLength: 10),
    },
  );
}

// Usage
class UserForm extends Form {
  UserForm({super.data}) : super(
    fields: {
      'name': CharField(),
      'address': AddressField(),
    },
  );
}
```

## Form Validation

### Field-Level Validation

```dart
class CustomField extends Field {
  @override
  Future<String?> validate(String value) async {
    if (value.length < 5) {
      return 'Value must be at least 5 characters';
    }
    return null;
  }
}

// Usage
class MyForm extends Form {
  MyForm({super.data}) : super(
    fields: {
      'custom': CustomField(),
    },
  );
}
```

### Form-Level Validation

```dart
class PasswordChangeForm extends Form {
  PasswordChangeForm({super.data}) : super(
    fields: {
      'password': CharField(widget: PasswordInput()),
      'confirm_password': CharField(widget: PasswordInput()),
    },
  );
  
  @override
  Future<Map<String, String>> validate() async {
    final errors = await super.validate();
    
    if (cleanedData['password'] != cleanedData['confirm_password']) {
      errors['confirm_password'] = 'Passwords do not match';
    }
    
    return errors;
  }
}
```

### Cross-Field Validation

```dart
class DateRangeForm extends Form {
  DateRangeForm({super.data}) : super(
    fields: {
      'start_date': DateField(),
      'end_date': DateField(),
    },
  );
  
  @override
  Future<Map<String, String>> validate() async {
    final errors = await super.validate();
    
    final start = cleanedData['start_date'] as DateTime;
    final end = cleanedData['end_date'] as DateTime;
    
    if (end.isBefore(start)) {
      errors['end_date'] = 'End date must be after start date';
    }
    
    return errors;
  }
}
```

## Form Processing

### Handling Form Data

```dart
class ContactView extends View {
  @override
  Future<void> post() async {
    final form = ContactForm(data: await getJsonBody());
    
    if (await form.isValid()) {
      // Process valid data
      await sendEmail(
        to: form.cleanedData['email'],
        subject: 'Contact Form Submission',
        body: form.cleanedData['message'],
      );
      
      redirect('/thank-you');
    } else {
      // Re-render with errors
      sendHtml('''
        <h1>Contact Us</h1>
        ${await form.asP()}
      ''');
    }
  }
}
```

### File Upload Handling

```dart
class DocumentUploadView extends View {
  @override
  Future<void> post() async {
    final form = DocumentForm(files: await getFiles());
    
    if (await form.isValid()) {
      final file = form.cleanedFiles['document'];
      await file.save('/uploads/${file.name}');
      
      redirect('/upload-success');
    } else {
      sendHtml('''
        <h1>Upload Document</h1>
        ${await form.asP()}
      ''');
    }
  }
}
```

## Best Practices

1. **Use Built-in Fields**: Prefer built-in fields for common data types
2. **Custom Validation**: Create custom fields for complex validation
3. **Form Composition**: Use composite fields for related data
4. **Error Handling**: Always handle validation errors gracefully
5. **Security**: Validate and sanitize all user input
6. **Accessibility**: Use semantic HTML and ARIA attributes

## What's Next?

- Learn about [Templates](11-templates.md) for rendering views
- Explore [Testing](12-testing.md) for testing your forms
- See [Best Practices](13-best-practices.md) for more patterns

---

← [Framework Integration](06-framework-integration.md) | **Next: [Form Fields](08-form-fields.md)** → 
