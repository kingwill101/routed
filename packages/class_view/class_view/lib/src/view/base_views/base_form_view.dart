import 'dart:async';
import 'dart:io' show HttpStatus;

import '../../../class_view.dart';

/// Mixin for handling Form() instances in template views
/// Centers around actual Form objects instead of raw data
mixin FormViewMixin on TemplateView {
  @override
  List<String> get allowedMethods => ['GET', 'POST'];

  /// Get the Form instance for this view
  /// This is the core method that subclasses implement
  Form getForm([Map<String, dynamic>? data]);

  /// Get the current form instance with appropriate data
  Future<Form> getCurrentForm() async {
    final data = await getMethod() == 'POST' ? await getFormData() : null;
    return getForm(data);
  }

  @override
  Future<Map<String, dynamic>> getContextData() async {
    final form = await getCurrentForm();
    final formContext = await form.getContext();
    return {
      'form': formContext,
      'form_html': await _safeRenderForm(form),
      ...await getExtraContext(),
    };
  }

  /// Safely render form with fallback
  Future<String> _safeRenderForm(Form form) async {
    try {
      return await (form as RenderableFormMixin).asP();
    } catch (e) {
      return '<p>Form rendering error: $e</p>';
    }
  }

  /// Get any extra context data for the template
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {};
  }

  /// Handle valid form submission - gets the validated Form instance
  Future<void> formValid(Form form) {
    // This method should be implemented by subclasses to handle valid form data
    throw UnimplementedError('formValid() must be implemented by subclasses');
  }

  /// Handle invalid form submission
  Future<void> formInvalid(Form form) async {
    final contextData = await getExtraContext();
    // Re-render the form with validation errors
    final formContext = await form.getContext();
    contextData['form'] = formContext;
    contextData['form_html'] = await _safeRenderForm(form);
    await renderToResponse(contextData, statusCode: HttpStatus.badRequest);
  }

  @override
  Future<void> post() async {
    try {
      final form = await getCurrentForm();

      if (await form.isValid()) {
        await formValid(form);
      } else {
        await formInvalid(form);
      }
    } catch (e) {
      final contextData = await getContextData();
      contextData['error'] = e.toString();
      await renderToResponse(
        contextData,
        statusCode: HttpStatus.internalServerError,
      );
    }
  }
}

/// A base view for processing forms using Form() instances
abstract class BaseFormView extends TemplateView with FormViewMixin {}

/// Model form view that works with model-backed forms
abstract class ModelFormView<T> extends TemplateView
    with FormViewMixin, SuccessFailureUrlMixin {
  /// Get the model instance (for edit forms)
  Future<T?> getObject() async => null;

  /// Create the model form with optional instance
  Form createForm(T? instance, [Map<String, dynamic>? data]);

  @override
  Form getForm([Map<String, dynamic>? data]) {
    // For model forms, we need to get the instance first
    // This is a sync wrapper - subclasses should override for async model loading
    return createForm(null, data);
  }

  /// Override for async model loading
  Future<Form> getModelForm([Map<String, dynamic>? data]) async {
    final instance = await getObject();
    return createForm(instance, data);
  }

  @override
  Future<Form> getCurrentForm() async {
    final data = await getMethod() == 'POST' ? await getFormData() : null;
    return await getModelForm(data);
  }

  @override
  Future<void> formValid(Form form) async {
    final savedObject = await saveForm(form);
    await onSaveSuccess(savedObject);
  }

  /// Save the form and return the saved object
  Future<T> saveForm(Form form);

  /// Handle successful save
  Future<void> onSaveSuccess(T object) async {
    if (successUrl != null) {
      redirect(successUrl!);
    }
  }
}

/// Base class for all forms.
/// Provides form validation, data cleaning, and rendering functionality.
class Form with RenderableMixin, DefaultView, RenderableFormMixin {
  /// Indicates whether the form is bound to data.
  final bool isBound;

  /// Data submitted with the form.
  final Map<String, dynamic> data;

  /// Files submitted with the form.
  final Map<String, dynamic> files;

  /// Prefix for field names.
  final String? prefix;

  /// Initial data for the form.
  final Map<String, dynamic> initial;

  /// Error messages for the form.
  final Map<String, dynamic> errors = {};

  /// Cleaned data after validation.
  final Map<String, dynamic> cleanedData = {};

  /// Fields in the form.
  final Map<String, Field<dynamic>> fields;

  /// Indicates whether the form is empty-permitted.
  final bool emptyPermitted;

  /// The key used for non-field errors
  static const String nonFieldErrorsKey = '__all__';

  /// Default template names for different rendering formats
  @override
  String get templateName => renderer?.formTemplateName ?? "";

  @override
  final Renderer? renderer;

  String autoI;

  Form({
    required this.isBound,
    required this.data,
    required this.files,
    this.prefix,
    this.autoI = 'id_%s',
    this.initial = const {},
    this.emptyPermitted = false,
    bool? useRequiredAttribute,
    required this.fields,
    this.renderer,
  }) : useRequiredAttribute = useRequiredAttribute ?? false;

  /// Return a list of errors that aren't associated with a particular field.
  /// These are errors from Form.clean(). Returns an empty list if there are none.
  List<String> nonFieldErrors() {
    final nonFieldErrors = errors[nonFieldErrorsKey];
    if (nonFieldErrors == null) return [];
    return nonFieldErrors is List
        ? List<String>.from(nonFieldErrors)
        : [nonFieldErrors.toString()];
  }

  /// Yield (name, boundField) pairs for all fields in the form.
  Iterable<(String, BoundField<dynamic>)> boundItems() sync* {
    for (final name in fields.keys) {
      yield (name, this[name]);
    }
  }

  /// Get the context data for rendering.
  @override
  FutureOr<Map<String, dynamic>> getContext() async {
    final fieldsData = <Map<String, dynamic>>[];
    final hiddenFieldsData = <Map<String, dynamic>>[];
    final topErrors = List<String>.from(nonFieldErrors());

    for (final entry in boundItems()) {
      final name = entry.$1;
      final bf = entry.$2;

      final bfMap = await _boundFieldToMap(bf);

      if (bf.field.widget.isHidden) {
        if (bf.errors.isNotEmpty) {
          topErrors.addAll(bf.errors.map((e) => '(Hidden field $name) $e'));
        }
        hiddenFieldsData.add(bfMap);
      } else {
        // Store field data with errors for template access
        fieldsData.add({'field': bfMap, 'errors': bf.errors});
      }
    }

    return {
      'form': await _formToMap(),
      'fields': fieldsData,
      'hidden_fields': hiddenFieldsData,
      'errors': topErrors,
    };
  }

  /// Converts a BoundField instance to a map of its resolved properties.
  Future<Map<String, dynamic>> _boundFieldToMap(BoundField<dynamic> bf) async {
    return {
      'name': bf.name,
      'html_name': bf.htmlName,
      'auto_id': bf.autoId,
      'label': bf.label,
      'help_text': bf.helpText,
      'value': bf.value,
      'errors': bf.errors,
      'has_errors': bf.hasErrors,
      'label_html': bf.renderLabel(),
      'help_text_html': bf.renderHelpText(),
      'errors_html': await bf.renderErrors(),
      'is_hidden': bf.isHidden,
      'html': await bf.toHtml(),
      'widget_html': await bf.asWidget(),
      'template_name': bf.templateName,
      'initial': getInitialForField(bf.field, bf.name),
      'aria_describedby': bf.ariaDescribedby,
      'widget_attrs': bf.buildWidgetAttrs(
        bf.field.widget.attrs,
        bf.field.widget,
      ),
      'field': await toFieldMap(bf.field),
    };
  }

  /// Converts the Form instance to a map of its properties.
  Future<Map<String, dynamic>> _formToMap() async {
    return {
      'is_bound': isBound,
      'data': data,
      'files': files,
      'prefix': prefix,
      'initial': initial,
      'errors': errors,
      'cleaned_data': cleanedData,
      'empty_permitted': emptyPermitted,
      'non_field_errors': nonFieldErrors(),
      'has_changed': hasChanged(),
      'changed_data': changedData,
      'use_required_attribute': useRequiredAttribute,
      'is_multipart': isMultipart(),
    };
  }

  /// Operator overloading to access fields as BoundField`<dynamic>`s
  BoundField<dynamic> operator [](String name) {
    if (!fields.containsKey(name)) {
      throw ArgumentError('Field $name not found in form');
    }
    return BoundField<dynamic>(this, fields[name]!, name);
  }

  /// Validates the form and populates errors and cleanedData.
  Future<void> fullClean() async {
    errors.clear();
    cleanedData.clear();

    if (!isBound) return;

    // If the form is empty and empty is permitted, skip validation
    if (emptyPermitted && data.isEmpty) {
      return;
    }

    for (final entry in fields.entries) {
      final fieldName = entry.key;
      final field = entry.value;

      try {
        final value = await field.clean(data[fieldName]);
        cleanedData[fieldName] = value;
      } catch (e) {
        if (e is ValidationError) {
          errors[fieldName] = e.message;
        } else {
          // Handle other errors
          errors[fieldName] = 'Invalid value';
        }
      }
    }

    clean();
  }

  /// Hook for additional form-wide cleaning.
  void clean() {}

  /// Checks if the form is valid.
  Future<bool> isValid() async {
    await fullClean();
    return errors.isEmpty;
  }

  /// Returns the field name with a prefix appended, if this form has a prefix set.
  String addPrefix(String fieldName) {
    return prefix != null ? '$prefix-$fieldName' : fieldName;
  }

  /// Returns true if the form has changed from its initial data.
  bool hasChanged() {
    return fields.entries.any((entry) {
      final fieldName = entry.key;
      final field = entry.value;
      final initialValue = initial[fieldName];
      final currentValue = data[fieldName];
      return field.hasChanged(initialValue, currentValue);
    });
  }

  /// Returns a list of field names that have changed.
  List<String> get changedData {
    return fields.entries
        .where((entry) {
          final fieldName = entry.key;
          final field = entry.value;
          final initialValue = initial[fieldName];
          final currentValue = data[fieldName];
          return field.hasChanged(initialValue, currentValue);
        })
        .map((entry) => entry.key)
        .toList();
  }

  bool useRequiredAttribute = true;

  /// Returns a list of hidden fields.
  List<Field<dynamic>> hiddenFields() {
    return fields.values.where((field) => field.widget.isHidden).toList();
  }

  /// Returns a list of visible fields.
  List<Field<dynamic>> visibleFields() {
    return fields.values.where((field) => !field.widget.isHidden).toList();
  }

  /// Adds an error to a specific field or as a non-field error.
  void addError(String? field, String error) {
    if (field == null) {
      errors[Form.nonFieldErrorsKey] = error;
    } else {
      errors[field] = error;
    }
  }

  /// Checks if a specific field has an error.
  bool hasError(String field) {
    return errors.containsKey(field);
  }

  /// Returns the initial value for a field.
  dynamic getInitialForField(Field<dynamic> field, String fieldName) {
    final value = initial[fieldName] ?? field.initial;
    return value is Function ? value() : value;
  }

  /// Returns true if the form requires multipart encoding.
  bool isMultipart() {
    return fields.values.any((field) => field.widget.needsMultipartForm);
  }

  dynamic initialForField<T>(Field<T> field, String name) {
    var value = initial[name] ?? field.initial;
    if (value is Function) {
      value = value();
    }
    if ((value is DateTime) && !field.widget.supportsMicroseconds) {
      value = value.copyWith(microsecond: 0);
    }
    return value as T?;
  }
}
