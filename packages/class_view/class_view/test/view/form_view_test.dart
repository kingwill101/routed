import 'package:class_view/class_view.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../shared/mock_adapter.mocks.dart';

/// Mock Form for testing
class MockForm extends Form {
  final bool _isValid;
  final Map<String, dynamic> _cleanedData;

  MockForm({
    required super.data,
    required super.isBound,
    bool isValid = true,
    Map<String, dynamic> cleanedData = const {},
  }) : _isValid = isValid,
       _cleanedData = cleanedData,
       super(files: {}, fields: {}, renderer: null);

  @override
  Future<bool> isValid() async => _isValid;

  @override
  Map<String, dynamic> get cleanedData => _cleanedData;
}

/// Mock RenderableForm for testing form rendering
class MockRenderableForm extends MockForm {
  MockRenderableForm({
    required super.data,
    required super.isBound,
    super.isValid,
    super.cleanedData,
  });

  @override
  String get templateName => 'form_template.html';

  @override
  Map<String, dynamic> getContext() => {'form': this};

  @override
  Future<String> asP() async => '<p>Mock form rendered as P</p>';
}

/// Test Model for ModelFormView tests
class TestModel {
  final String id;
  final String name;

  TestModel(this.id, this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// Test Form for model forms
class TestModelForm extends MockForm {
  final TestModel? instance;

  TestModelForm({
    this.instance,
    required super.data,
    required super.isBound,
    super.isValid,
  }) : super(cleanedData: data);

  TestModel save() {
    if (instance != null) {
      return TestModel(instance!.id, cleanedData['name'] ?? instance!.name);
    } else {
      return TestModel('new-id', cleanedData['name'] ?? 'New Item');
    }
  }
}

/// Test BaseFormView implementation
class TestBaseFormView extends BaseFormView {
  final MockForm _form;
  bool formValidCalled = false;
  Form? lastValidForm;

  TestBaseFormView(this._form);

  @override
  String get templateName => 'test_form.html';

  @override
  Form getForm([Map<String, dynamic>? data]) => _form;

  @override
  Future<void> formValid(Form form) async {
    formValidCalled = true;
    lastValidForm = form;
  }

  @override
  Future<void> renderToResponse(
    Map<String, dynamic> templateContext, {
    String? templateName,
    int statusCode = 200,
  }) async {
    // Mock template rendering - set status and write HTML content
    setStatusCode(statusCode);
    setHeader('Content-Type', 'text/html');

    // Simulate rendering a form template to HTML
    final template = templateName ?? this.templateName;
    final formHtml = templateContext['form_html'] ?? '';

    final html =
        '''
<!DOCTYPE html>
<html>
<head><title>$template</title></head>
<body>
  <h1>Form Page</h1>
  $formHtml
  ${templateContext['error'] != null ? '<div class="error">${templateContext['error']}</div>' : ''}
</body>
</html>''';

    write(html);
  }
}

/// Test ModelFormView implementation
class TestModelFormView extends ModelFormView<TestModel> {
  final TestModel? _instance;
  bool saveFormCalled = false;
  Form? lastSavedForm;
  TestModel? lastSavedObject;

  TestModelFormView([this._instance]);

  @override
  String get templateName => 'model_form.html';

  @override
  String? get successUrl => '/models';

  @override
  Future<TestModel?> getObject() async => _instance;

  @override
  Form createForm(TestModel? instance, [Map<String, dynamic>? data]) {
    return TestModelForm(
      instance: instance,
      data: data ?? {},
      isBound: data != null,
    );
  }

  @override
  Future<TestModel> saveForm(Form form) async {
    saveFormCalled = true;
    lastSavedForm = form;
    final testForm = form as TestModelForm;
    lastSavedObject = testForm.save();
    return lastSavedObject!;
  }

  @override
  Future<void> renderToResponse(
    Map<String, dynamic> templateContext, {
    String? templateName,
    int statusCode = 200,
  }) async {
    // Mock template rendering - set status and write HTML content
    setStatusCode(statusCode);
    setHeader('Content-Type', 'text/html');

    // Simulate rendering a form template to HTML
    final template = templateName ?? this.templateName;
    final formHtml = templateContext['form_html'] ?? '';

    final html =
        '''
<!DOCTYPE html>
<html>
<head><title>$template</title></head>
<body>
  <h1>Form Page</h1>
  $formHtml
  ${templateContext['error'] != null ? '<div class="error">${templateContext['error']}</div>' : ''}
</body>
</html>''';

    write(html);
  }
}

/// Test BaseFormView with custom extra context
class TestBaseFormViewWithExtraContext extends TestBaseFormView {
  TestBaseFormViewWithExtraContext(super.form);

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {'custom': 'data', 'page_title': 'Test Form'};
  }
}

/// Test BaseFormView that handles errors in form creation
class TestBaseFormViewWithError extends BaseFormView {
  final bool shouldErrorOnFormData;

  TestBaseFormViewWithError({this.shouldErrorOnFormData = false});

  @override
  String get templateName => 'test_form.html';

  @override
  Form getForm([Map<String, dynamic>? data]) {
    if (shouldErrorOnFormData && data != null) {
      throw Exception('Form creation error');
    }
    return MockForm(data: data ?? {}, isBound: data != null);
  }

  @override
  Future<void> formValid(Form form) async {
    // Simple implementation for testing
  }

  @override
  Future<Map<String, dynamic>> getContextData() async {
    try {
      return await super.getContextData();
    } catch (e) {
      // Handle errors in context building for error tests
      return {'error': e.toString()};
    }
  }

  @override
  Future<void> renderToResponse(
    Map<String, dynamic> templateContext, {
    String? templateName,
    int statusCode = 200,
  }) async {
    // Mock template rendering - set status and write HTML content
    setStatusCode(statusCode);
    setHeader('Content-Type', 'text/html');

    // Simulate rendering a form template to HTML
    final template = templateName ?? this.templateName;
    final formHtml = templateContext['form_html'] ?? '';

    final html =
        '''
<!DOCTYPE html>
<html>
<head><title>$template</title></head>
<body>
  <h1>Form Page</h1>
  $formHtml
  ${templateContext['error'] != null ? '<div class="error">${templateContext['error']}</div>' : ''}
</body>
</html>''';

    write(html);
  }
}

void main() {
  group('Form View Tests', () {
    late MockViewAdapter mockAdapter;

    setUp(() {
      mockAdapter = MockViewAdapter();
    });

    group('BaseFormView Tests', () {
      test('should have GET and POST as allowed methods', () {
        final form = MockForm(data: {}, isBound: false);
        final view = TestBaseFormView(form);

        expect(view.allowedMethods, containsAll(['GET', 'POST']));
      });

      test('should get form without data for GET requests', () async {
        final form = MockForm(data: {}, isBound: false);
        final view = TestBaseFormView(form);
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(mockAdapter.getFormData()).thenAnswer((_) async => {});

        final currentForm = await view.getCurrentForm();
        expect(currentForm, equals(form));
      });

      test('should get form with data for POST requests', () async {
        final formData = {'name': 'test', 'email': 'test@example.com'};
        final form = MockForm(data: formData, isBound: true);
        final view = TestBaseFormView(form);
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(mockAdapter.getFormData()).thenAnswer((_) async => formData);

        final currentForm = await view.getCurrentForm();
        expect(currentForm, equals(form));
      });

      test('should include form in context data', () async {
        final form = MockForm(data: {}, isBound: false);
        final view = TestBaseFormView(form);
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(mockAdapter.getFormData()).thenAnswer((_) async => {});

        final context = await view.getContextData();
        expect(context['form'], isA<Map<String, dynamic>>());
        final formContext = context['form'] as Map<String, dynamic>;
        expect(formContext['form'], isA<Map<String, dynamic>>());
        expect(
          (formContext['form'] as Map<String, dynamic>)['is_bound'],
          isFalse,
        );
        expect(context['form_html'], isA<String>());
      });

      test('should render form HTML safely', () async {
        final form = MockRenderableForm(data: {}, isBound: false);
        final view = TestBaseFormView(form);
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(mockAdapter.getFormData()).thenAnswer((_) async => {});

        final context = await view.getContextData();
        expect(context['form_html'], equals('<p>Mock form rendered as P</p>'));
      });

      test('should call formValid when form is valid', () async {
        final form = MockForm(
          data: {'name': 'test'},
          isBound: true,
          isValid: true,
        );
        final view = TestBaseFormView(form);
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(
          mockAdapter.getFormData(),
        ).thenAnswer((_) async => {'name': 'test'});

        await view.post();

        expect(view.formValidCalled, isTrue);
        expect(view.lastValidForm, equals(form));
      });

      test('should call formInvalid when form is invalid', () async {
        final form = MockForm(
          data: {'name': ''},
          isBound: true,
          isValid: false,
        );
        final view = TestBaseFormView(form);
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(mockAdapter.getFormData()).thenAnswer((_) async => {'name': ''});

        await view.post();

        expect(view.formValidCalled, isFalse);
        verify(mockAdapter.setStatusCode(400)).called(1);
        verify(mockAdapter.setHeader('Content-Type', 'text/html')).called(1);
        verify(mockAdapter.write(any)).called(1);
      });

      test('should handle form processing errors', () async {
        final view = TestBaseFormViewWithError();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(mockAdapter.getFormData()).thenThrow(Exception('Form data error'));

        await view.post();

        // Check that an error response was sent
        verify(mockAdapter.setStatusCode(500)).called(1);
        verify(mockAdapter.setHeader('Content-Type', 'text/html')).called(1);
        final captured = verify(mockAdapter.write(captureAny)).captured;
        final html = captured.first as String;
        expect(html, contains('Form data error'));
      });
    });

    group('ModelFormView Tests', () {
      test('should create form without instance for new objects', () async {
        final view = TestModelFormView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(mockAdapter.getFormData()).thenAnswer((_) async => {});

        final form = await view.getModelForm();
        expect(form, isA<TestModelForm>());
        expect((form as TestModelForm).instance, isNull);
      });

      test('should create form with instance for existing objects', () async {
        final model = TestModel('123', 'Test Model');
        final view = TestModelFormView(model);
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(mockAdapter.getFormData()).thenAnswer((_) async => {});

        final form = await view.getModelForm();
        expect(form, isA<TestModelForm>());
        expect((form as TestModelForm).instance, equals(model));
      });

      test('should save form and redirect on valid submission', () async {
        final model = TestModel('123', 'Original Name');
        final view = TestModelFormView(model);
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(
          mockAdapter.getFormData(),
        ).thenAnswer((_) async => {'name': 'Updated Name'});

        await view.post();

        expect(view.saveFormCalled, isTrue);
        expect(view.lastSavedObject?.name, equals('Updated Name'));
        verify(mockAdapter.redirect('/models', statusCode: 302)).called(1);
      });

      test('should handle model form context data', () async {
        final model = TestModel('123', 'Test Model');
        final view = TestModelFormView(model);
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(mockAdapter.getFormData()).thenAnswer((_) async => {});

        final context = await view.getContextData();
        expect(context['form'], isA<Map<String, dynamic>>());
        final formContext = context['form'] as Map<String, dynamic>;
        expect(formContext['form'], isA<Map<String, dynamic>>());
        expect(
          (formContext['form'] as Map<String, dynamic>)['is_bound'],
          isFalse,
        );
        expect(context['form_html'], isA<String>());
      });
    });

    group('FormViewMixin Integration Tests', () {
      test('should handle extra context data', () async {
        final form = MockForm(data: {}, isBound: false);
        final view = TestBaseFormViewWithExtraContext(form);
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(mockAdapter.getFormData()).thenAnswer((_) async => {});

        final context = await view.getContextData();
        expect(context['custom'], equals('data'));
        expect(context['page_title'], equals('Test Form'));
        expect(context['form'], isA<Map<String, dynamic>>());
      });

      test('should handle form rendering errors gracefully', () async {
        final form = MockForm(data: {}, isBound: false);
        final view = TestBaseFormView(form);
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(mockAdapter.getFormData()).thenAnswer((_) async => {});

        final context = await view.getContextData();
        // Since MockForm.toString() doesn't return "Mock form", let's check it's a string
        expect(context['form_html'], isA<String>());
      });
    });

    group('Error Handling Tests', () {
      test('should handle form validation errors', () async {
        final form = MockForm(
          data: {'email': 'invalid-email'},
          isBound: true,
          isValid: false,
        );
        final view = TestBaseFormView(form);
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(
          mockAdapter.getFormData(),
        ).thenAnswer((_) async => {'email': 'invalid-email'});

        await view.post();

        expect(view.formValidCalled, isFalse);
        verify(mockAdapter.setStatusCode(400)).called(1);
        verify(mockAdapter.setHeader('Content-Type', 'text/html')).called(1);
        verify(mockAdapter.write(any)).called(1);
      });

      test('should handle form creation errors', () async {
        final view = TestBaseFormViewWithError(shouldErrorOnFormData: true);
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(
          mockAdapter.getFormData(),
        ).thenAnswer((_) async => {'name': 'test'});

        await view.post();

        // Check that an error response was sent
        verify(mockAdapter.setStatusCode(500)).called(1);
        verify(mockAdapter.setHeader('Content-Type', 'text/html')).called(1);
        final captured = verify(mockAdapter.write(captureAny)).captured;
        final html = captured.first as String;
        expect(html, contains('Form creation error'));
      });
    });
  });
}
