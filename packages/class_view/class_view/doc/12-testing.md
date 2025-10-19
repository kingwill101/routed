# Testing

Comprehensive testing strategies for Class View applications. Learn to test views, forms, templates, and complete
application workflows with confidence.

## Testing Setup

### Basic Test Structure

```dart
import 'package:test/test.dart';
import 'package:class_view/class_view.dart';

void main() {
  group('View Tests', () {
    late TestViewAdapter adapter;
    
    setUp(() {
      adapter = TestViewAdapter();
    });
    
    test('basic view test', () async {
      final view = TestView();
      view.setAdapter(adapter);
      
      await view.dispatch();
      
      expect(adapter.statusCode, equals(200));
      expect(adapter.response, contains('test content'));
    });
  });
}

class TestViewAdapter implements ViewAdapter {
  int statusCode = 200;
  String response = '';
  Map<String, String> headers = {};
  Map<String, String> params = {};
  
  @override
  String get method => 'GET';
  
  @override
  Uri get uri => Uri.parse('/test');
  
  @override
  String? getParam(String name) => params[name];
  
  @override
  void setStatusCode(int code) => statusCode = code;
  
  @override
  void write(String body) => response = body;
  
  @override
  void setHeader(String name, String value) => headers[name] = value;
  
  // ... implement other ViewAdapter methods
}
```

## Testing Views

### Basic View Testing

```dart
test('TemplateView renders correctly', () async {
  final view = TestTemplateView();
  final adapter = TestViewAdapter();
  view.setAdapter(adapter);
  
  await view.get();
  
  expect(adapter.statusCode, equals(200));
  expect(adapter.headers['Content-Type'], contains('text/html'));
});

test('RedirectView redirects correctly', () async {
  final view = TestRedirectView();
  final adapter = TestViewAdapter();
  view.setAdapter(adapter);
  
  await view.get();
  
  expect(adapter.statusCode, equals(302));
  expect(adapter.headers['Location'], equals('/success'));
});
```

### Testing CRUD Views

```dart
group('CRUD View Tests', () {
  late PostRepository mockRepository;
  
  setUp(() {
    mockRepository = MockPostRepository();
  });
  
  test('CreateView handles POST correctly', () async {
    final view = PostCreateView(mockRepository);
    final adapter = TestViewAdapter(
      method: 'POST',
      body: {'title': 'Test Post', 'content': 'Test content'},
    );
    view.setAdapter(adapter);
    
    when(mockRepository.save(any)).thenAnswer((_) async => testPost);
    
    await view.post();
    
    expect(adapter.statusCode, equals(302));
    verify(mockRepository.save(any)).called(1);
  });
  
  test('ListView returns paginated results', () async {
    final view = PostListView(mockRepository);
    final adapter = TestViewAdapter();
    view.setAdapter(adapter);
    
    when(mockRepository.findAll(page: 1, pageSize: 10))
        .thenAnswer((_) async => (items: testPosts, total: 25));
    
    await view.get();
    
    expect(adapter.statusCode, equals(200));
    final context = view.getContextData();
    expect(context['posts'], hasLength(10));
    expect(context['pagination']['total'], equals(25));
  });
  
  test('DetailView returns 404 for missing object', () async {
    final view = PostDetailView(mockRepository);
    final adapter = TestViewAdapter(params: {'id': '999'});
    view.setAdapter(adapter);
    
    when(mockRepository.findById('999')).thenAnswer((_) async => null);
    
    expect(() => view.get(), throwsA(isA<HttpException>()));
  });
});
```

### Testing View Mixins

```dart
test('ContextMixin provides correct context', () async {
  final view = TestContextView();
  final adapter = TestViewAdapter();
  view.setAdapter(adapter);
  
  final context = await view.getContextData();
  
  expect(context['view'], equals(view));
  expect(context, containsKey('extra_data'));
});

test('SingleObjectMixin retrieves object correctly', () async {
  final view = TestSingleObjectView();
  final adapter = TestViewAdapter(params: {'id': '123'});
  view.setAdapter(adapter);
  
  final object = await view.getObjectOr404();
  
  expect(object.id, equals('123'));
});
```

## Testing Forms

### Form Validation Testing

```dart
group('Form Validation Tests', () {
  test('valid form passes validation', () async {
    final form = ContactForm(data: {
      'name': 'John Doe',
      'email': 'john@example.com',
      'message': 'Hello world',
    });
    
    expect(await form.isValid(), isTrue);
    expect(form.errors, isEmpty);
  });
  
  test('invalid form fails validation', () async {
    final form = ContactForm(data: {
      'name': '',
      'email': 'invalid-email',
      'message': 'Hi',
    });
    
    expect(await form.isValid(), isFalse);
    expect(form.errors['name'], contains('This field is required.'));
    expect(form.errors['email'], contains('Enter a valid email address.'));
    expect(form.errors['message'], contains('Ensure this value has at least 10 characters.'));
  });
  
  test('cross-field validation works', () async {
    final form = PasswordForm(data: {
      'password': 'secret123',
      'password_confirm': 'different123',
    });
    
    expect(await form.isValid(), isFalse);
    expect(form.errors['password_confirm'], contains('Passwords do not match.'));
  });
});
```

### Field Testing

```dart
group('Field Tests', () {
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
  
  test('CharField respects length limits', () async {
    final field = CharField(
      validators: [
        MinLengthValidator(5),
        MaxLengthValidator(20),
      ],
    );
    
    expect(await field.clean('hello'), equals('hello'));
    expect(() => field.clean('hi'), throwsA(isA<ValidationError>()));
    expect(() => field.clean('this is way too long'), throwsA(isA<ValidationError>()));
  });
});
```

### Widget Testing

```dart
test('TextInput renders correctly', () async {
  final widget = TextInput(attrs: {
    'class': 'form-control',
    'placeholder': 'Enter text',
  });
  
  final html = await widget.render('username', 'john_doe');
  
  expect(html, contains('type="text"'));
  expect(html, contains('name="username"'));
  expect(html, contains('value="john_doe"'));
  expect(html, contains('class="form-control"'));
  expect(html, contains('placeholder="Enter text"'));
});

test('Widget uses DefaultView fallback', () async {
  final widget = TextInput();
  final renderer = MockRenderer();
  
  when(renderer.renderAsync(any, any)).thenThrow(TemplateNotFoundException('test'));
  
  final html = await widget.render('test', 'value', renderer: renderer);
  
  expect(html, contains('type="text"'));
  expect(html, contains('name="test"'));
});
```

## Testing Templates

### Template Rendering Tests

```dart
group('Template Tests', () {
  setUp(() {
    TemplateManager.configureMemoryOnly(
      extraTemplates: {
        'test.html': '<h1>{{ title }}</h1><p>{{ content }}</p>',
        'list.html': '''
          <ul>
            {% for item in items %}
              <li>{{ item }}</li>
            {% endfor %}
          </ul>
        ''',
      },
    );
  });
  
  test('template renders with context', () async {
    final html = await TemplateManager.render('test.html', {
      'title': 'Test Page',
      'content': 'Hello world',
    });
    
    expect(html, contains('<h1>Test Page</h1>'));
    expect(html, contains('<p>Hello world</p>'));
  });
  
  test('template loops work correctly', () async {
    final html = await TemplateManager.render('list.html', {
      'items': ['Apple', 'Banana', 'Cherry'],
    });
    
    expect(html, contains('<li>Apple</li>'));
    expect(html, contains('<li>Banana</li>'));
    expect(html, contains('<li>Cherry</li>'));
  });
});
```

### Custom ViewEngine Testing

```dart
test('custom ViewEngine works', () async {
  final engine = MockViewEngine();
  TemplateManager.initialize(engine);
  
  when(engine.render('test.html', any))
      .thenAnswer((_) async => '<div>Mock content</div>');
  
  final html = await TemplateManager.render('test.html', {'data': 'test'});
  
  expect(html, equals('<div>Mock content</div>'));
  verify(engine.render('test.html', {'data': 'test'})).called(1);
});
```

## Integration Testing

### End-to-End View Testing

```dart
group('Integration Tests', () {
  late TestServer server;
  
  setUp(() async {
    server = await TestServer.start();
  });
  
  tearDown(() async {
    await server.stop();
  });
  
  test('complete user registration flow', () async {
    // GET registration form
    final getResponse = await server.get('/register');
    expect(getResponse.statusCode, equals(200));
    expect(getResponse.body, contains('<form'));
    
    // POST registration data
    final postResponse = await server.post('/register', {
      'username': 'testuser',
      'email': 'test@example.com',
      'password': 'secure123',
      'password_confirm': 'secure123',
    });
    expect(postResponse.statusCode, equals(302));
    expect(postResponse.headers['location'], contains('/welcome'));
    
    // Verify user was created
    final user = await userRepository.findByEmail('test@example.com');
    expect(user, isNotNull);
    expect(user!.username, equals('testuser'));
  });
  
  test('form validation errors display correctly', () async {
    final response = await server.post('/register', {
      'username': '',
      'email': 'invalid-email',
      'password': '123',
    });
    
    expect(response.statusCode, equals(200));
    expect(response.body, contains('This field is required'));
    expect(response.body, contains('Enter a valid email'));
    expect(response.body, contains('Password too short'));
  });
});
```

### API Testing

```dart
test('API endpoints return correct JSON', () async {
  final response = await server.get('/api/posts');
  
  expect(response.statusCode, equals(200));
  expect(response.headers['content-type'], contains('application/json'));
  
  final data = jsonDecode(response.body);
  expect(data['posts'], isList);
  expect(data['pagination'], isMap);
});

test('API handles pagination correctly', () async {
  final response = await server.get('/api/posts?page=2&page_size=5');
  
  final data = jsonDecode(response.body);
  expect(data['posts'], hasLength(5));
  expect(data['pagination']['current_page'], equals(2));
  expect(data['pagination']['page_size'], equals(5));
});
```

## Test Utilities

### Mock Factories

```dart
class MockFactory {
  static Post createPost({
    String? id,
    String? title,
    String? content,
    DateTime? createdAt,
  }) {
    return Post(
      id: id ?? 'post_${Random().nextInt(1000)}',
      title: title ?? 'Test Post',
      content: content ?? 'Test content for post',
      createdAt: createdAt ?? DateTime.now(),
    );
  }
  
  static User createUser({
    String? id,
    String? username,
    String? email,
  }) {
    return User(
      id: id ?? 'user_${Random().nextInt(1000)}',
      username: username ?? 'testuser',
      email: email ?? 'test@example.com',
    );
  }
  
  static List<Post> createPosts(int count) {
    return List.generate(count, (i) => createPost(
      title: 'Post ${i + 1}',
      content: 'Content for post ${i + 1}',
    ));
  }
}
```

### Test Helpers

```dart
class TestHelpers {
  static ViewAdapter createAdapter({
    String method = 'GET',
    String path = '/test',
    Map<String, String>? params,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) {
    return TestViewAdapter(
      method: method,
      uri: Uri.parse(path),
      params: params ?? {},
      body: body,
      headers: headers ?? {},
    );
  }
  
  static Future<void> assertRedirect(
    View view,
    String expectedUrl, {
    int expectedStatus = 302,
  }) async {
    final adapter = view.adapter as TestViewAdapter;
    expect(adapter.statusCode, equals(expectedStatus));
    expect(adapter.headers['Location'], equals(expectedUrl));
  }
  
  static Future<void> assertJsonResponse(
    View view,
    Map<String, dynamic> expectedData,
  ) async {
    final adapter = view.adapter as TestViewAdapter;
    expect(adapter.statusCode, equals(200));
    expect(adapter.headers['Content-Type'], contains('application/json'));
    
    final actualData = jsonDecode(adapter.response);
    expect(actualData, equals(expectedData));
  }
}
```

## Performance Testing

### Load Testing

```dart
test('view handles concurrent requests', () async {
  final view = PostListView();
  final futures = <Future<void>>[];
  
  for (int i = 0; i < 100; i++) {
    final adapter = TestHelpers.createAdapter();
    view.setAdapter(adapter);
    futures.add(view.get());
  }
  
  final stopwatch = Stopwatch()..start();
  await Future.wait(futures);
  stopwatch.stop();
  
  expect(stopwatch.elapsedMilliseconds, lessThan(5000));
});

test('template rendering performance', () async {
  final context = {
    'posts': MockFactory.createPosts(1000),
    'user': MockFactory.createUser(),
  };
  
  final stopwatch = Stopwatch()..start();
  final html = await TemplateManager.render('posts/list.html', context);
  stopwatch.stop();
  
  expect(html, isNotEmpty);
  expect(stopwatch.elapsedMilliseconds, lessThan(1000));
});
```

### Memory Testing

```dart
test('form processing does not leak memory', () async {
  final initialMemory = ProcessInfo.currentRss;
  
  for (int i = 0; i < 1000; i++) {
    final form = ContactForm(data: {
      'name': 'Test User $i',
      'email': 'test$i@example.com',
      'message': 'Test message $i',
    });
    
    await form.isValid();
  }
  
  // Force garbage collection
  for (int i = 0; i < 5; i++) {
    await Future.delayed(Duration(milliseconds: 100));
  }
  
  final finalMemory = ProcessInfo.currentRss;
  final memoryIncrease = finalMemory - initialMemory;
  
  expect(memoryIncrease, lessThan(50 * 1024 * 1024)); // Less than 50MB
});
```

## Testing Best Practices

### Test Organization

```dart
// tests/views/post_views_test.dart
void main() {
  group('Post Views', () {
    setUpAll(() {
      // Global setup
    });
    
    group('PostListView', () {
      // Specific view tests
    });
    
    group('PostDetailView', () {
      // Specific view tests
    });
  });
}

// tests/forms/post_forms_test.dart
void main() {
  group('Post Forms', () {
    // Form tests
  });
}
```

### Test Data Management

```dart
class TestDatabase {
  static Future<void> setUp() async {
    await database.migrate();
    await seedTestData();
  }
  
  static Future<void> tearDown() async {
    await database.clear();
  }
  
  static Future<void> seedTestData() async {
    final users = MockFactory.createUsers(10);
    final posts = MockFactory.createPosts(50);
    
    await database.insertUsers(users);
    await database.insertPosts(posts);
  }
}
```

## What's Next?

Now you have comprehensive testing strategies. Continue with:

- **[Best Practices](13-best-practices.md)** - Production patterns and optimization
- **[Advanced Topics](14-advanced-topics.md)** - Custom adapters, caching, and API development

---

← [Template Integration](11-templates.md) | **Next: [Best Practices](13-best-practices.md)** → 