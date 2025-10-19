# Advanced Forms

This guide covers advanced form patterns, dynamic form generation, complex validation scenarios, and integration with
views. Build sophisticated forms that handle complex business logic while maintaining clean, maintainable code.

## Dynamic Form Generation

### Runtime Field Addition

Create forms that adapt based on configuration or user choices:

```dart
class DynamicConfigForm extends Form {
  DynamicConfigForm({
    required Map<String, dynamic> config,
    super.data,
    super.files,
    super.renderer,
  }) : super(fields: _buildFieldsFromConfig(config));
  
  static Map<String, Field> _buildFieldsFromConfig(Map<String, dynamic> config) {
    final fields = <String, Field>{};
    
    for (final entry in config.entries) {
      final fieldConfig = entry.value as Map<String, dynamic>;
      final fieldType = fieldConfig['type'] as String;
      final fieldName = entry.key;
      
      switch (fieldType) {
        case 'text':
          fields[fieldName] = CharField(
            label: fieldConfig['label'],
            required: fieldConfig['required'] ?? false,
            maxLength: fieldConfig['max_length'],
            validators: _buildValidators(fieldConfig['validators']),
          );
          break;
        case 'email':
          fields[fieldName] = EmailField(
            label: fieldConfig['label'],
            required: fieldConfig['required'] ?? false,
            validators: [EmailValidator(), ..._buildValidators(fieldConfig['validators'])],
          );
          break;
        case 'choice':
          fields[fieldName] = ChoiceField(
            label: fieldConfig['label'],
            required: fieldConfig['required'] ?? false,
            choices: (fieldConfig['choices'] as List).cast<List<String>>(),
            widget: fieldConfig['widget'] == 'radio' ? RadioSelect() : Select(),
          );
          break;
        case 'number':
          fields[fieldName] = IntegerField(
            label: fieldConfig['label'],
            required: fieldConfig['required'] ?? false,
            minValue: fieldConfig['min_value'],
            maxValue: fieldConfig['max_value'],
          );
          break;
      }
    }
    
    return fields;
  }
  
  static List<Validator> _buildValidators(List<dynamic>? validatorConfigs) {
    if (validatorConfigs == null) return [];
    
    return validatorConfigs.map((config) {
      final type = config['type'] as String;
      switch (type) {
        case 'min_length':
          return MinLengthValidator(config['value']);
        case 'max_length':
          return MaxLengthValidator(config['value']);
        case 'regex':
          return RegexValidator(RegExp(config['pattern']));
        default:
          throw ArgumentError('Unknown validator type: $type');
      }
    }).toList();
  }
}

// Usage with configuration
final formConfig = {
  'company_name': {
    'type': 'text',
    'label': 'Company Name',
    'required': true,
    'max_length': 100,
  },
  'industry': {
    'type': 'choice',
    'label': 'Industry',
    'required': true,
    'choices': [
      ['tech', 'Technology'],
      ['finance', 'Finance'],
      ['healthcare', 'Healthcare'],
    ],
  },
  'employee_count': {
    'type': 'number',
    'label': 'Number of Employees',
    'min_value': 1,
    'max_value': 10000,
  },
};

final form = DynamicConfigForm(config: formConfig);
```

### Conditional Field Display

Forms that show/hide fields based on other field values:

```dart
class ConditionalForm extends Form {
  ConditionalForm({super.data, super.files, super.renderer}) : super(
    fields: {
      'user_type': ChoiceField(
        choices: [
          ['individual', 'Individual'],
          ['business', 'Business'],
          ['organization', 'Organization'],
        ],
        widget: RadioSelect(),
      ),
      'first_name': CharField(maxLength: 50),
      'last_name': CharField(maxLength: 50),
      'company_name': CharField(
        maxLength: 100,
        required: false, // Will be made required conditionally
      ),
      'tax_id': CharField(
        maxLength: 20,
        required: false,
        validators: [RegexValidator(RegExp(r'^\d{2}-\d{7}$'))],
      ),
      'organization_type': ChoiceField(
        choices: [
          ['nonprofit', 'Non-Profit'],
          ['government', 'Government'],
          ['educational', 'Educational'],
        ],
        required: false,
      ),
    },
  );
  
  @override
  Future<void> clean() async {
    await super.clean();
    
    final userType = cleanedData['user_type'];
    
    // Business users must provide company name and tax ID
    if (userType == 'business') {
      if (cleanedData['company_name'] == null || 
          cleanedData['company_name'].toString().trim().isEmpty) {
        addError('company_name', 'Company name is required for business accounts.');
      }
      
      if (cleanedData['tax_id'] == null || 
          cleanedData['tax_id'].toString().trim().isEmpty) {
        addError('tax_id', 'Tax ID is required for business accounts.');
      }
    }
    
    // Organizations must provide organization type
    if (userType == 'organization') {
      if (cleanedData['organization_type'] == null || 
          cleanedData['organization_type'].toString().trim().isEmpty) {
        addError('organization_type', 'Organization type is required.');
      }
    }
  }
  
  /// Get fields that should be visible based on current form state
  Map<String, Field> getVisibleFields() {
    final userType = data?['user_type'];
    final visibleFields = <String, Field>{
      'user_type': fields['user_type']!,
      'first_name': fields['first_name']!,
      'last_name': fields['last_name']!,
    };
    
    if (userType == 'business') {
      visibleFields.addAll({
        'company_name': fields['company_name']!,
        'tax_id': fields['tax_id']!,
      });
    } else if (userType == 'organization') {
      visibleFields.addAll({
        'company_name': fields['company_name']!,
        'organization_type': fields['organization_type']!,
      });
    }
    
    return visibleFields;
  }
  
  /// Custom rendering that only shows relevant fields
  Future<String> asConditionalDiv() async {
    final visibleFields = getVisibleFields();
    final buffer = StringBuffer();
    
    // Render non-field errors
    if (nonFieldErrors().isNotEmpty) {
      buffer.writeln('<div class="form-errors">');
      for (final error in nonFieldErrors()) {
        buffer.writeln('<div class="error">$error</div>');
      }
      buffer.writeln('</div>');
    }
    
    // Render visible fields
    for (final entry in visibleFields.entries) {
      final fieldName = entry.key;
      final field = entry.value;
      final boundField = this[fieldName];
      
      buffer.writeln('<div class="field-group">');
      buffer.writeln(boundField.renderLabel());
      buffer.writeln(await boundField.asWidget());
      
      if (boundField.errors.isNotEmpty) {
        buffer.writeln('<div class="field-errors">');
        for (final error in boundField.errors) {
          buffer.writeln('<span class="error">$error</span>');
        }
        buffer.writeln('</div>');
      }
      
      if (boundField.helpText.isNotEmpty) {
        buffer.writeln('<div class="help-text">${boundField.helpText}</div>');
      }
      
      buffer.writeln('</div>');
    }
    
    return buffer.toString();
  }
}
```

### Multi-Step Forms (Wizards)

Handle complex workflows with multiple form steps:

```dart
class FormWizard {
  final List<Form> steps;
  final Map<String, dynamic> data = {};
  int currentStep = 0;
  
  FormWizard(this.steps);
  
  Form get currentForm => steps[currentStep];
  bool get isFirstStep => currentStep == 0;
  bool get isLastStep => currentStep == steps.length - 1;
  
  /// Process current step and advance if valid
  Future<bool> processStep(Map<String, dynamic> stepData) async {
    final form = currentForm;
    
    // Bind data to current form
    form.data = stepData;
    
    if (await form.isValid()) {
      // Store cleaned data
      data.addAll(form.cleanedData);
      
      if (!isLastStep) {
        currentStep++;
        return true;
      } else {
        // Final step - process complete form
        return await processCompleteForm();
      }
    }
    
    return false;
  }
  
  /// Go back to previous step
  void previousStep() {
    if (!isFirstStep) {
      currentStep--;
    }
  }
  
  /// Process the complete multi-step form
  Future<bool> processCompleteForm() async {
    // All steps completed - implement your business logic
    print('Complete form data: $data');
    return true;
  }
  
  /// Get progress percentage
  double get progress => (currentStep + 1) / steps.length;
}

// Define wizard steps
class PersonalInfoForm extends Form {
  PersonalInfoForm({super.data}) : super(
    fields: {
      'first_name': CharField(maxLength: 50),
      'last_name': CharField(maxLength: 50),
      'email': EmailField(validators: [EmailValidator()]),
      'phone': CharField(
        maxLength: 15,
        validators: [RegexValidator(RegExp(r'^\+?[\d\s\-\(\)]+$'))],
      ),
    },
  );
}

class AddressInfoForm extends Form {
  AddressInfoForm({super.data}) : super(
    fields: {
      'street': CharField(maxLength: 200),
      'city': CharField(maxLength: 100),
      'state': CharField(maxLength: 50),
      'zip_code': CharField(
        maxLength: 10,
        validators: [RegexValidator(RegExp(r'^\d{5}(-\d{4})?$'))],
      ),
      'country': ChoiceField(
        choices: [
          ['US', 'United States'],
          ['CA', 'Canada'],
          ['MX', 'Mexico'],
        ],
      ),
    },
  );
}

class PaymentInfoForm extends Form {
  PaymentInfoForm({super.data}) : super(
    fields: {
      'card_number': CharField(
        maxLength: 19,
        validators: [RegexValidator(RegExp(r'^\d{4}\s\d{4}\s\d{4}\s\d{4}$'))],
        widget: TextInput(attrs: {'placeholder': '1234 5678 9012 3456'}),
      ),
      'expiry_date': CharField(
        maxLength: 5,
        validators: [RegexValidator(RegExp(r'^(0[1-9]|1[0-2])\/\d{2}$'))],
        widget: TextInput(attrs: {'placeholder': 'MM/YY'}),
      ),
      'cvv': CharField(
        maxLength: 4,
        validators: [RegexValidator(RegExp(r'^\d{3,4}$'))],
        widget: PasswordInput(),
      ),
    },
  );
}

// Usage
final wizard = FormWizard([
  PersonalInfoForm(),
  AddressInfoForm(),
  PaymentInfoForm(),
]);
```

## Advanced Validation Patterns

### Cross-Field Validation

Validate relationships between multiple fields:

```dart
class EventForm extends Form {
  EventForm({super.data, super.files}) : super(
    fields: {
      'title': CharField(maxLength: 200),
      'start_date': DateField(),
      'end_date': DateField(),
      'start_time': TimeField(),
      'end_time': TimeField(),
      'max_attendees': IntegerField(minValue: 1),
      'early_bird_deadline': DateField(required: false),
      'early_bird_price': DecimalField(
        maxDigits: 8,
        decimalPlaces: 2,
        required: false,
      ),
      'regular_price': DecimalField(
        maxDigits: 8,
        decimalPlaces: 2,
      ),
    },
  );
  
  @override
  Future<void> clean() async {
    await super.clean();
    
    // Validate date range
    final startDate = cleanedData['start_date'] as DateTime?;
    final endDate = cleanedData['end_date'] as DateTime?;
    
    if (startDate != null && endDate != null && endDate.isBefore(startDate)) {
      addError('end_date', 'End date must be after start date.');
    }
    
    // Validate time range (for same-day events)
    if (startDate != null && endDate != null && 
        startDate.day == endDate.day &&
        startDate.month == endDate.month &&
        startDate.year == endDate.year) {
      
      final startTime = cleanedData['start_time'] as TimeOfDay?;
      final endTime = cleanedData['end_time'] as TimeOfDay?;
      
      if (startTime != null && endTime != null) {
        final startMinutes = startTime.hour * 60 + startTime.minute;
        final endMinutes = endTime.hour * 60 + endTime.minute;
        
        if (endMinutes <= startMinutes) {
          addError('end_time', 'End time must be after start time for same-day events.');
        }
      }
    }
    
    // Validate early bird pricing
    final earlyBirdDeadline = cleanedData['early_bird_deadline'] as DateTime?;
    final earlyBirdPrice = cleanedData['early_bird_price'] as double?;
    final regularPrice = cleanedData['regular_price'] as double?;
    
    if (earlyBirdDeadline != null || earlyBirdPrice != null) {
      if (earlyBirdDeadline == null) {
        addError('early_bird_deadline', 'Early bird deadline is required when early bird price is set.');
      }
      if (earlyBirdPrice == null) {
        addError('early_bird_price', 'Early bird price is required when early bird deadline is set.');
      }
      
      if (startDate != null && earlyBirdDeadline != null && 
          earlyBirdDeadline.isAfter(startDate)) {
        addError('early_bird_deadline', 'Early bird deadline must be before event start date.');
      }
      
      if (earlyBirdPrice != null && regularPrice != null && 
          earlyBirdPrice >= regularPrice) {
        addError('early_bird_price', 'Early bird price must be less than regular price.');
      }
    }
  }
}
```

### Async Field Dependencies

Fields that depend on async data validation:

```dart
class ProjectForm extends Form {
  final ProjectRepository projectRepository;
  final UserRepository userRepository;
  
  ProjectForm({
    required this.projectRepository,
    required this.userRepository,
    super.data,
    super.files,
  }) : super(
    fields: {
      'name': CharField(maxLength: 100),
      'description': CharField(widget: Textarea()),
      'manager_email': EmailField(validators: [EmailValidator()]),
      'budget': DecimalField(maxDigits: 12, decimalPlaces: 2),
      'department': CharField(maxLength: 50),
    },
  );
  
  @override
  Future<void> clean() async {
    await super.clean();
    
    // Validate manager exists and has appropriate permissions
    final managerEmail = cleanedData['manager_email'] as String?;
    if (managerEmail != null) {
      final manager = await userRepository.findByEmail(managerEmail);
      if (manager == null) {
        addError('manager_email', 'No user found with this email address.');
      } else if (!manager.hasRole('project_manager')) {
        addError('manager_email', 'User must have project manager role.');
      }
    }
    
    // Validate unique project name within department
    final projectName = cleanedData['name'] as String?;
    final department = cleanedData['department'] as String?;
    
    if (projectName != null && department != null) {
      final existing = await projectRepository.findByNameAndDepartment(
        projectName, 
        department,
      );
      if (existing != null) {
        addError('name', 'A project with this name already exists in the department.');
      }
    }
    
    // Validate budget against department limits
    final budget = cleanedData['budget'] as double?;
    if (budget != null && department != null) {
      final departmentLimit = await projectRepository.getDepartmentBudgetLimit(department);
      if (budget > departmentLimit) {
        addError('budget', 'Budget exceeds department limit of \$${departmentLimit.toStringAsFixed(2)}.');
      }
    }
  }
}
```

### Validation Groups

Organize validation into logical groups:

```dart
class UserRegistrationForm extends Form {
  UserRegistrationForm({super.data, super.files}) : super(
    fields: {
      // Basic info
      'username': CharField(
        maxLength: 30,
        validators: [
          MinLengthValidator(3),
          RegexValidator(RegExp(r'^[a-zA-Z0-9_]+$')),
        ],
      ),
      'email': EmailField(validators: [EmailValidator()]),
      
      // Security
      'password': CharField(
        widget: PasswordInput(),
        validators: [MinLengthValidator(8)],
      ),
      'password_confirm': CharField(widget: PasswordInput()),
      
      // Profile
      'first_name': CharField(maxLength: 50),
      'last_name': CharField(maxLength: 50),
      'birth_date': DateField(required: false),
      
      // Preferences
      'newsletter': BooleanField(required: false),
      'timezone': ChoiceField(
        choices: [
          ['UTC', 'UTC'],
          ['America/New_York', 'Eastern Time'],
          ['America/Los_Angeles', 'Pacific Time'],
        ],
      ),
      
      // Terms
      'terms_accepted': BooleanField(),
      'privacy_accepted': BooleanField(),
    },
  );
  
  @override
  Future<void> clean() async {
    await super.clean();
    
    // Group 1: Password validation
    await _validatePasswordGroup();
    
    // Group 2: Profile validation
    await _validateProfileGroup();
    
    // Group 3: Legal validation
    await _validateLegalGroup();
  }
  
  Future<void> _validatePasswordGroup() async {
    final password = cleanedData['password'] as String?;
    final passwordConfirm = cleanedData['password_confirm'] as String?;
    
    if (password != passwordConfirm) {
      addError('password_confirm', 'Passwords do not match.');
    }
    
    if (password != null) {
      // Password complexity validation
      if (!RegExp(r'[A-Z]').hasMatch(password)) {
        addError('password', 'Password must contain at least one uppercase letter.');
      }
      if (!RegExp(r'[0-9]').hasMatch(password)) {
        addError('password', 'Password must contain at least one number.');
      }
      if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) {
        addError('password', 'Password must contain at least one special character.');
      }
    }
  }
  
  Future<void> _validateProfileGroup() async {
    final birthDate = cleanedData['birth_date'] as DateTime?;
    
    if (birthDate != null) {
      final now = DateTime.now();
      final age = now.year - birthDate.year;
      
      if (age < 13) {
        addError('birth_date', 'Users must be at least 13 years old.');
      }
      if (birthDate.isAfter(now)) {
        addError('birth_date', 'Birth date cannot be in the future.');
      }
    }
  }
  
  Future<void> _validateLegalGroup() async {
    final termsAccepted = cleanedData['terms_accepted'] as bool?;
    final privacyAccepted = cleanedData['privacy_accepted'] as bool?;
    
    if (termsAccepted != true) {
      addError('terms_accepted', 'You must accept the terms of service.');
    }
    if (privacyAccepted != true) {
      addError('privacy_accepted', 'You must accept the privacy policy.');
    }
  }
}
```

## Form Integration with Views

### CRUD Form Views

Seamless integration between forms and CRUD operations:

```dart
class ProductCreateView extends CreateView<Product> {
  @override
  Future<Form> getForm() async {
    return ProductForm(
      data: method == 'POST' ? await getFormData() : null,
      files: method == 'POST' ? await getFormFiles() : null,
      renderer: renderer,
    );
  }
  
  @override
  Future<Product> createObject(Map<String, dynamic> cleanedData) async {
    return Product.fromMap(cleanedData);
  }
  
  @override
  String get successUrl => '/products';
  
  @override
  Future<void> get() async {
    final form = await getForm();
    final context = await getContextData();
    context['form'] = form;
    
    sendHtml(await renderTemplate('products/create.html', context));
  }
  
  @override
  Future<void> post() async {
    final form = await getForm();
    
    if (await form.isValid()) {
      final product = await createObject(form.cleanedData);
      await productRepository.save(product);
      redirect(successUrl);
    } else {
      final context = await getContextData();
      context['form'] = form;
      
      sendHtml(await renderTemplate('products/create.html', context));
    }
  }
}

class ProductUpdateView extends UpdateView<Product> {
  @override
  Future<Form> getForm() async {
    final product = await getObjectOr404();
    final initialData = method == 'POST' ? await getFormData() : product.toMap();
    
    return ProductForm(
      data: initialData,
      files: method == 'POST' ? await getFormFiles() : null,
      renderer: renderer,
    );
  }
  
  @override
  Future<Product> updateObject(Product object, Map<String, dynamic> cleanedData) async {
    return object.copyWith(cleanedData);
  }
}
```

### Form Mixins for Views

Reusable form handling patterns:

```dart
mixin FormViewMixin on ViewMixin {
  /// Override this to provide the form class
  Form createForm({Map<String, dynamic>? data, Map<String, dynamic>? files});
  
  /// Get form data from request
  Future<Map<String, dynamic>> getFormData() async {
    if (method == 'POST') {
      final contentType = getHeader('Content-Type') ?? '';
      if (contentType.contains('application/json')) {
        return await getJsonBody();
      } else {
        return await getPostData();
      }
    }
    return {};
  }
  
  /// Get uploaded files from request
  Future<Map<String, dynamic>> getFormFiles() async {
    // Implementation depends on your framework
    return {};
  }
  
  /// Process form submission
  Future<bool> processForm(Form form) async {
    if (await form.isValid()) {
      await handleValidForm(form);
      return true;
    } else {
      await handleInvalidForm(form);
      return false;
    }
  }
  
  /// Handle valid form submission
  Future<void> handleValidForm(Form form);
  
  /// Handle invalid form submission
  Future<void> handleInvalidForm(Form form) async {
    final context = await getContextData();
    context['form'] = form;
    
    sendHtml(await renderTemplate(templateName, context));
  }
  
  /// Template name for rendering the form
  String get templateName;
  
  /// Get additional context data
  Future<Map<String, dynamic>> getContextData() async => {};
}

// Usage
class ContactView extends View with FormViewMixin {
  @override
  Form createForm({Map<String, dynamic>? data, Map<String, dynamic>? files}) {
    return ContactForm(data: data, files: files, renderer: renderer);
  }
  
  @override
  String get templateName => 'contact.html';
  
  @override
  Future<void> handleValidForm(Form form) async {
    final contactData = form.cleanedData;
    await sendEmail(contactData);
    redirect('/contact/success');
  }
  
  @override
  Future<void> get() async {
    final form = createForm();
    final context = await getContextData();
    context['form'] = form;
    
    sendHtml(await renderTemplate(templateName, context));
  }
  
  @override
  Future<void> post() async {
    final form = createForm(
      data: await getFormData(),
      files: await getFormFiles(),
    );
    
    await processForm(form);
  }
}
```

## Form Sets and Inline Forms

### FormSet for Multiple Related Objects

Handle multiple instances of the same form:

```dart
class BaseFormSet {
  final List<Form> forms;
  final Map<String, dynamic>? data;
  final int maxForms;
  final int minForms;
  
  BaseFormSet({
    required this.forms,
    this.data,
    this.maxForms = 1000,
    this.minForms = 0,
  });
  
  /// Check if all forms in the set are valid
  Future<bool> isValid() async {
    if (forms.length < minForms) return false;
    if (forms.length > maxForms) return false;
    
    for (final form in forms) {
      if (!await form.isValid()) return false;
    }
    return true;
  }
  
  /// Get cleaned data from all forms
  List<Map<String, dynamic>> get cleanedData {
    return forms.map((form) => form.cleanedData).toList();
  }
  
  /// Add a new form to the set
  void addForm(Form form) {
    if (forms.length < maxForms) {
      forms.add(form);
    }
  }
  
  /// Remove a form from the set
  void removeForm(int index) {
    if (forms.length > minForms && index < forms.length) {
      forms.removeAt(index);
    }
  }
  
  /// Render all forms
  Future<String> render() async {
    final buffer = StringBuffer();
    
    for (int i = 0; i < forms.length; i++) {
      buffer.writeln('<div class="formset-form" data-form-index="$i">');
      buffer.writeln(await forms[i].asDiv());
      if (forms.length > minForms) {
        buffer.writeln('<button type="button" class="remove-form" data-form-index="$i">Remove</button>');
      }
      buffer.writeln('</div>');
    }
    
    if (forms.length < maxForms) {
      buffer.writeln('<button type="button" class="add-form">Add Another</button>');
    }
    
    return buffer.toString();
  }
}

// Specific FormSet implementations
class ContactFormSet extends BaseFormSet {
  ContactFormSet({
    super.data,
    int initialForms = 1,
  }) : super(
    forms: List.generate(initialForms, (_) => ContactForm()),
    minForms: 1,
    maxForms: 5,
  );
}

// Usage in views
class MultiContactView extends View with FormViewMixin {
  @override
  Form createForm({Map<String, dynamic>? data, Map<String, dynamic>? files}) {
    // Not used for FormSets
    throw UnimplementedError();
  }
  
  ContactFormSet createFormSet({Map<String, dynamic>? data}) {
    return ContactFormSet(data: data);
  }
  
  @override
  String get templateName => 'multi_contact.html';
  
  @override
  Future<void> get() async {
    final formset = createFormSet();
    final context = await getContextData();
    context['formset'] = formset;
    
    sendHtml(await renderTemplate(templateName, context));
  }
  
  @override
  Future<void> post() async {
    final formset = createFormSet(data: await getFormData());
    
    if (await formset.isValid()) {
      for (final contactData in formset.cleanedData) {
        await saveContact(contactData);
      }
      redirect('/contacts/success');
    } else {
      final context = await getContextData();
      context['formset'] = formset;
      
      sendHtml(await renderTemplate(templateName, context));
    }
  }
  
  @override
  Future<void> handleValidForm(Form form) async {
    // Not used for FormSets
  }
}
```

## Performance and Optimization

### Form Caching

Cache expensive form operations:

```dart
class CachedFormMixin {
  static final Map<String, Form> _formCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 10);
  
  Form? getCachedForm(String key) {
    final timestamp = _cacheTimestamps[key];
    if (timestamp != null && 
        DateTime.now().difference(timestamp) < _cacheExpiry) {
      return _formCache[key];
    }
    return null;
  }
  
  void cacheForm(String key, Form form) {
    _formCache[key] = form;
    _cacheTimestamps[key] = DateTime.now();
  }
  
  void clearFormCache() {
    _formCache.clear();
    _cacheTimestamps.clear();
  }
}

class OptimizedDynamicForm extends Form with CachedFormMixin {
  OptimizedDynamicForm.fromConfig(Map<String, dynamic> config) 
      : super(fields: _getCachedFields(config));
  
  static Map<String, Field> _getCachedFields(Map<String, dynamic> config) {
    final configHash = config.toString().hashCode.toString();
    final cached = _fieldCache[configHash];
    
    if (cached != null) return cached;
    
    final fields = _buildFieldsFromConfig(config);
    _fieldCache[configHash] = fields;
    return fields;
  }
  
  static final Map<String, Map<String, Field>> _fieldCache = {};
  
  static Map<String, Field> _buildFieldsFromConfig(Map<String, dynamic> config) {
    // Expensive field building logic here
    return {};
  }
}
```

## What's Next?

Now you've mastered advanced form patterns. Continue with:

- **[Template Integration](11-templates.md)** - Advanced template usage and view rendering
- **[Testing](12-testing.md)** - Testing complex forms and validation scenarios
- **[Best Practices](13-best-practices.md)** - Production patterns for forms and views

---

← [Form Widgets](09-form-widgets.md) | **Next: [Template Integration](11-templates.md)** → 