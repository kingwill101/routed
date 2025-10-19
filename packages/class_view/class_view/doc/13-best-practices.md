# Best Practices

Production-ready patterns, optimization techniques, and maintainability guidelines for Class View applications. Build
robust, scalable applications that are easy to maintain and extend.

## Project Structure

### Recommended Directory Layout

```
lib/
├── src/
│   ├── models/
│   │   ├── user.dart
│   │   ├── post.dart
│   │   └── models.dart
│   ├── repositories/
│   │   ├── base_repository.dart
│   │   ├── user_repository.dart
│   │   └── post_repository.dart
│   ├── services/
│   │   ├── auth_service.dart
│   │   ├── email_service.dart
│   │   └── cache_service.dart
│   ├── views/
│   │   ├── auth/
│   │   │   ├── login_view.dart
│   │   │   └── register_view.dart
│   │   ├── posts/
│   │   │   ├── post_list_view.dart
│   │   │   ├── post_detail_view.dart
│   │   │   └── post_create_view.dart
│   │   └── api/
│   │       ├── api_base_view.dart
│   │       └── post_api_view.dart
│   ├── forms/
│   │   ├── auth/
│   │   │   ├── login_form.dart
│   │   │   └── register_form.dart
│   │   ├── posts/
│   │   │   ├── post_form.dart
│   │   │   └── comment_form.dart
│   │   └── fields/
│   │       ├── custom_fields.dart
│   │       └── validators.dart
│   ├── mixins/
│   │   ├── auth_mixin.dart
│   │   ├── cache_mixin.dart
│   │   └── logging_mixin.dart
│   └── config/
│       ├── database.dart
│       ├── cache.dart
│       └── app_config.dart
├── templates/
│   ├── base.html
│   ├── layouts/
│   ├── auth/
│   ├── posts/
│   └── partials/
└── web/
    ├── css/
    ├── js/
    └── images/
```

## View Design Patterns

### Base View Classes

Create consistent base classes for common patterns:

```dart
// Base view with common functionality
abstract class BaseView extends View with AuthMixin, LoggingMixin {
  @override
  Future<void> dispatch() async {
    try {
      await logRequest();
      await super.dispatch();
    } catch (e) {
      await handleError(e);
    }
  }
  
  Future<void> handleError(Object error) async {
    logger.error('View error: $error');
    
    if (error is ValidationError) {
      setStatusCode(400);
      sendJson({'errors': error.errors});
    } else if (error is UnauthorizedException) {
      setStatusCode(401);
      sendJson({'error': 'Unauthorized'});
    } else {
      setStatusCode(500);
      sendJson({'error': 'Internal server error'});
    }
  }
}

// API base view
abstract class ApiView extends BaseView with JsonResponseMixin {
  @override
  List<String> get allowedMethods => ['GET', 'POST', 'PUT', 'DELETE'];
  
  @override
  Future<void> options() async {
    setHeader('Access-Control-Allow-Methods', allowedMethods.join(', '));
    setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    setStatusCode(200);
  }
}

// Template-based view
abstract class PageView extends BaseView with TemplateResponseMixin, GlobalContextMixin {
  @override
  Future<void> get() async {
    final context = await getContextData();
    await renderToResponse(context);
  }
}
```

### View Composition

Use mixins for cross-cutting concerns:

```dart
mixin AuthMixin on ViewMixin {
  User? _currentUser;
  
  User? get currentUser => _currentUser;
  bool get isAuthenticated => currentUser != null;
  
  @override
  Future<void> dispatch() async {
    await _loadUser();
    
    if (requiresAuth && !isAuthenticated) {
      throw UnauthorizedException();
    }
    
    await super.dispatch();
  }
  
  Future<void> _loadUser() async {
    final token = getHeader('Authorization');
    if (token != null) {
      _currentUser = await authService.validateToken(token);
    }
  }
  
  bool get requiresAuth => false;
}

mixin CacheMixin on ViewMixin {
  Duration get cacheTimeout => Duration(minutes: 5);
  String get cacheKey => '${runtimeType}_${uri.path}_${method}';
  
  @override
  Future<void> dispatch() async {
    if (method == 'GET' && shouldCache) {
      final cached = await cacheService.get(cacheKey);
      if (cached != null) {
        write(cached);
        return;
      }
    }
    
    await super.dispatch();
    
    if (method == 'GET' && shouldCache) {
      await cacheService.set(cacheKey, response, cacheTimeout);
    }
  }
  
  bool get shouldCache => true;
}

mixin RateLimitMixin on ViewMixin {
  int get maxRequests => 100;
  Duration get timeWindow => Duration(hours: 1);
  
  @override
  Future<void> dispatch() async {
    final clientId = getClientIdentifier();
    final isAllowed = await rateLimitService.checkLimit(
      clientId, 
      maxRequests, 
      timeWindow,
    );
    
    if (!isAllowed) {
      setStatusCode(429);
      setHeader('Retry-After', timeWindow.inSeconds.toString());
      sendJson({'error': 'Rate limit exceeded'});
      return;
    }
    
    await super.dispatch();
  }
  
  String getClientIdentifier() {
    return getHeader('X-Forwarded-For') ?? 
           getHeader('X-Real-IP') ?? 
           'unknown';
  }
}
```

## Form Best Practices

### Validation Strategy

Implement comprehensive validation:

```dart
class UserForm extends Form {
  final UserRepository userRepository;
  
  UserForm({
    required this.userRepository,
    super.data,
    super.files,
  }) : super(
    fields: {
      'username': CharField(
        maxLength: 30,
        validators: [
          MinLengthValidator(3),
          RegexValidator(RegExp(r'^[a-zA-Z0-9_]+$')),
          // Custom async validator
          UniqueUsernameValidator(userRepository),
        ],
      ),
      'email': EmailField(
        validators: [
          EmailValidator(),
          UniqueEmailValidator(userRepository),
        ],
      ),
      'password': CharField(
        widget: PasswordInput(),
        validators: [
          MinLengthValidator(8),
          PasswordStrengthValidator(),
        ],
      ),
      'password_confirm': CharField(widget: PasswordInput()),
    },
  );
  
  @override
  Future<void> clean() async {
    await super.clean();
    
    // Cross-field validation
    final password = cleanedData['password'];
    final passwordConfirm = cleanedData['password_confirm'];
    
    if (password != passwordConfirm) {
      addError('password_confirm', 'Passwords do not match.');
    }
    
    // Business logic validation
    final username = cleanedData['username'];
    final email = cleanedData['email'];
    
    if (username != null && email != null) {
      if (await userRepository.hasConflictingData(username, email)) {
        throw ValidationError({
          '__all__': ['Username and email combination already exists.']
        });
      }
    }
  }
}

class PasswordStrengthValidator extends Validator<String> {
  @override
  Future<void> validate(String? value) async {
    if (value == null || value.isEmpty) return;
    
    final errors = <String>[];
    
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      errors.add('Must contain uppercase letter');
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      errors.add('Must contain lowercase letter');
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      errors.add('Must contain number');
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      errors.add('Must contain special character');
    }
    
    if (errors.isNotEmpty) {
      throw ValidationError({
        'password_strength': errors,
      });
    }
  }
}
```

### Form Security

Implement CSRF protection and input sanitization:

```dart
mixin CsrfMixin on ViewMixin {
  @override
  Future<void> dispatch() async {
    if (method == 'POST' || method == 'PUT' || method == 'DELETE') {
      await validateCsrfToken();
    }
    
    await super.dispatch();
  }
  
  Future<void> validateCsrfToken() async {
    final token = getParam('csrf_token') ?? getHeader('X-CSRF-Token');
    final sessionToken = await getSessionValue('csrf_token');
    
    if (token == null || sessionToken == null || token != sessionToken) {
      throw ForbiddenException('CSRF token validation failed');
    }
  }
  
  Future<String> generateCsrfToken() async {
    final token = generateSecureToken();
    await setSessionValue('csrf_token', token);
    return token;
  }
}

class SecureForm extends Form {
  @override
  Future<Map<String, dynamic>> getContextData() async {
    final context = await super.getContextData();
    context['csrf_token'] = await generateCsrfToken();
    return context;
  }
  
  @override
  Future<void> clean() async {
    // Sanitize input data
    for (final entry in cleanedData.entries) {
      if (entry.value is String) {
        cleanedData[entry.key] = sanitizeHtml(entry.value);
      }
    }
    
    await super.clean();
  }
  
  String sanitizeHtml(String input) {
    // Remove dangerous HTML tags and attributes
    return input
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'javascript:', caseSensitive: false), '')
        .replaceAll(RegExp(r'on\w+\s*=', caseSensitive: false), '');
  }
}
```

## Error Handling

### Centralized Error Management

```dart
class ErrorHandler {
  static Future<void> handleError(Object error, StackTrace stackTrace) async {
    await _logError(error, stackTrace);
    await _notifyAdmins(error);
    await _trackMetrics(error);
  }
  
  static Future<void> _logError(Object error, StackTrace stackTrace) async {
    final severity = _getErrorSeverity(error);
    
    logger.log(severity, 'Application error: $error', error, stackTrace);
    
    // Send to external logging service
    if (isProduction) {
      await sentry.captureException(error, stackTrace: stackTrace);
    }
  }
  
  static Future<void> _notifyAdmins(Object error) async {
    if (_isCriticalError(error)) {
      await emailService.sendAlert(
        to: adminEmails,
        subject: 'Critical Application Error',
        body: 'Error: $error\nTime: ${DateTime.now()}',
      );
    }
  }
  
  static LogLevel _getErrorSeverity(Object error) {
    if (error is ValidationError) return LogLevel.info;
    if (error is UnauthorizedException) return LogLevel.warning;
    if (error is DatabaseException) return LogLevel.critical;
    return LogLevel.error;
  }
  
  static bool _isCriticalError(Object error) {
    return error is DatabaseException || 
           error is OutOfMemoryError ||
           error is SecurityException;
  }
}

// Global error boundary for views
mixin ErrorBoundaryMixin on ViewMixin {
  @override
  Future<void> dispatch() async {
    try {
      await super.dispatch();
    } catch (error, stackTrace) {
      await ErrorHandler.handleError(error, stackTrace);
      await _sendErrorResponse(error);
    }
  }
  
  Future<void> _sendErrorResponse(Object error) async {
    if (error is ValidationError) {
      setStatusCode(400);
      sendJson({
        'error': 'Validation failed',
        'details': error.errors,
      });
    } else if (error is UnauthorizedException) {
      setStatusCode(401);
      sendJson({'error': 'Unauthorized'});
    } else if (error is NotFoundException) {
      setStatusCode(404);
      sendJson({'error': 'Not found'});
    } else {
      setStatusCode(500);
      sendJson({
        'error': 'Internal server error',
        'id': generateErrorId(), // For tracking
      });
    }
  }
}
```

## Performance Optimization

### Caching Strategies

```dart
class CacheStrategy {
  static const Duration shortTerm = Duration(minutes: 5);
  static const Duration mediumTerm = Duration(hours: 1);
  static const Duration longTerm = Duration(days: 1);
  
  // View-level caching
  static String viewCacheKey(View view) {
    final params = view.getParams();
    final user = view.getCurrentUser();
    
    return 'view:${view.runtimeType}:${params.hashCode}:${user?.id ?? 'anonymous'}';
  }
  
  // Data caching
  static String dataCacheKey(String type, String id) {
    return 'data:$type:$id';
  }
  
  // Template caching
  static String templateCacheKey(String template, Map<String, dynamic> context) {
    final contextHash = context.toString().hashCode;
    return 'template:$template:$contextHash';
  }
}

mixin SmartCacheMixin on ViewMixin {
  @override
  Future<void> dispatch() async {
    if (shouldUseCache) {
      final cached = await _getCachedResponse();
      if (cached != null) {
        _sendCachedResponse(cached);
        return;
      }
    }
    
    final responseCapture = ResponseCapture();
    setResponseCapture(responseCapture);
    
    await super.dispatch();
    
    if (shouldUseCache && responseCapture.statusCode == 200) {
      await _cacheResponse(responseCapture);
    }
  }
  
  bool get shouldUseCache => method == 'GET' && !isAuthenticated;
  Duration get cacheDuration => CacheStrategy.mediumTerm;
  
  Future<CachedResponse?> _getCachedResponse() async {
    final key = CacheStrategy.viewCacheKey(this);
    return await cacheService.get<CachedResponse>(key);
  }
  
  Future<void> _cacheResponse(ResponseCapture capture) async {
    final key = CacheStrategy.viewCacheKey(this);
    final cached = CachedResponse(
      body: capture.body,
      headers: capture.headers,
      statusCode: capture.statusCode,
    );
    
    await cacheService.set(key, cached, cacheDuration);
  }
}
```

### Database Optimization

```dart
class Repository {
  final Database database;
  final CacheService cache;
  
  Repository(this.database, this.cache);
  
  // Efficient pagination
  Future<({List<T> items, int total})> findPaginated<T>({
    required String table,
    required T Function(Map<String, dynamic>) fromMap,
    int page = 1,
    int pageSize = 20,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
  }) async {
    // Use cursor-based pagination for large datasets
    if (pageSize > 100) {
      return _findCursorPaginated(/* ... */);
    }
    
    // Cache count queries
    final countKey = 'count:$table:${where?.hashCode ?? 0}';
    int? total = await cache.get<int>(countKey);
    
    if (total == null) {
      total = await database.count(table, where: where, whereArgs: whereArgs);
      await cache.set(countKey, total, Duration(minutes: 5));
    }
    
    final offset = (page - 1) * pageSize;
    final results = await database.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: pageSize,
      offset: offset,
    );
    
    return (
      items: results.map(fromMap).toList(),
      total: total,
    );
  }
  
  // Batch operations
  Future<void> batchInsert<T>(
    String table,
    List<T> items,
    Map<String, dynamic> Function(T) toMap, {
    int batchSize = 100,
  }) async {
    for (int i = 0; i < items.length; i += batchSize) {
      final batch = items.skip(i).take(batchSize);
      final maps = batch.map(toMap).toList();
      
      await database.transaction((txn) async {
        for (final map in maps) {
          await txn.insert(table, map);
        }
      });
    }
  }
}
```

## Security Best Practices

### Input Validation

```dart
class SecurityValidator {
  static final _sqlInjectionPattern = RegExp(
    r'(\b(ALTER|CREATE|DELETE|DROP|EXEC(UTE)?|INSERT|SELECT|UNION|UPDATE)\b)',
    caseSensitive: false,
  );
  
  static final _xssPattern = RegExp(
    r'<script[^>]*>.*?</script>|javascript:|on\w+\s*=',
    caseSensitive: false,
  );
  
  static void validateSqlInjection(String input) {
    if (_sqlInjectionPattern.hasMatch(input)) {
      throw SecurityException('Potential SQL injection detected');
    }
  }
  
  static void validateXss(String input) {
    if (_xssPattern.hasMatch(input)) {
      throw SecurityException('Potential XSS attack detected');
    }
  }
  
  static String sanitizeInput(String input) {
    return input
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;')
        .replaceAll('&', '&amp;');
  }
}

class SecureField extends CharField {
  @override
  Future<String?> clean(dynamic value) async {
    final cleaned = await super.clean(value);
    
    if (cleaned != null) {
      SecurityValidator.validateSqlInjection(cleaned);
      SecurityValidator.validateXss(cleaned);
      return SecurityValidator.sanitizeInput(cleaned);
    }
    
    return cleaned;
  }
}
```

### Authentication & Authorization

```dart
mixin PermissionMixin on AuthMixin {
  List<String> get requiredPermissions => [];
  
  @override
  Future<void> dispatch() async {
    await super.dispatch();
    
    if (requiredPermissions.isNotEmpty) {
      await checkPermissions();
    }
  }
  
  Future<void> checkPermissions() async {
    if (!isAuthenticated) {
      throw UnauthorizedException();
    }
    
    final userPermissions = await getUserPermissions(currentUser!);
    
    for (final required in requiredPermissions) {
      if (!userPermissions.contains(required)) {
        throw ForbiddenException('Missing permission: $required');
      }
    }
  }
  
  Future<List<String>> getUserPermissions(User user) async {
    // Cache permissions
    final cacheKey = 'permissions:${user.id}';
    List<String>? cached = await cache.get<List<String>>(cacheKey);
    
    if (cached == null) {
      cached = await permissionService.getUserPermissions(user.id);
      await cache.set(cacheKey, cached, Duration(minutes: 10));
    }
    
    return cached;
  }
}

class AdminView extends BaseView with PermissionMixin {
  @override
  List<String> get requiredPermissions => ['admin.read'];
}

class UserManagementView extends BaseView with PermissionMixin {
  @override
  List<String> get requiredPermissions => ['users.manage', 'admin.read'];
}
```

## Monitoring and Observability

### Metrics Collection

```dart
class Metrics {
  static final _requestCounter = Counter('http_requests_total');
  static final _requestDuration = Histogram('http_request_duration_seconds');
  static final _errorCounter = Counter('http_errors_total');
  
  static void recordRequest(String method, String path, int statusCode) {
    _requestCounter.inc(labels: {
      'method': method,
      'path': path,
      'status': statusCode.toString(),
    });
  }
  
  static void recordRequestDuration(Duration duration, String endpoint) {
    _requestDuration.observe(
      duration.inMilliseconds / 1000.0,
      labels: {'endpoint': endpoint},
    );
  }
  
  static void recordError(String type, String endpoint) {
    _errorCounter.inc(labels: {
      'type': type,
      'endpoint': endpoint,
    });
  }
}

mixin MetricsMixin on ViewMixin {
  late Stopwatch _stopwatch;
  
  @override
  Future<void> dispatch() async {
    _stopwatch = Stopwatch()..start();
    
    try {
      await super.dispatch();
      
      Metrics.recordRequest(method, uri.path, getStatusCode());
    } catch (error) {
      Metrics.recordError(error.runtimeType.toString(), uri.path);
      rethrow;
    } finally {
      _stopwatch.stop();
      Metrics.recordRequestDuration(_stopwatch.elapsed, uri.path);
    }
  }
}
```

## Testing Strategy

### Test Pyramid

```dart
// Unit tests - Fast, isolated
group('UserRepository Unit Tests', () {
  test('findById returns user when exists', () async {
    final repo = UserRepository(mockDatabase);
    when(mockDatabase.query(any)).thenAnswer((_) async => [userMap]);
    
    final user = await repo.findById('123');
    
    expect(user, isNotNull);
    expect(user!.id, equals('123'));
  });
});

// Integration tests - Medium speed, realistic
group('UserView Integration Tests', () {
  test('POST /users creates user and returns 201', () async {
    final view = UserCreateView(realRepository);
    final adapter = TestAdapter(method: 'POST', body: validUserData);
    
    await view.setAdapter(adapter).dispatch();
    
    expect(adapter.statusCode, equals(201));
    
    final created = await realRepository.findByEmail(validUserData['email']);
    expect(created, isNotNull);
  });
});

// E2E tests - Slow, full system
group('User Registration E2E Tests', () {
  test('complete user registration flow', () async {
    final server = await TestServer.start();
    
    final registerResponse = await server.post('/register', userData);
    expect(registerResponse.statusCode, equals(302));
    
    final loginResponse = await server.post('/login', loginData);
    expect(loginResponse.statusCode, equals(200));
    
    await server.stop();
  });
});
```

## What's Next?

You've learned production-ready patterns for Class View applications. Continue with:

- **[Advanced Topics](14-advanced-topics.md)** - Custom adapters, caching, and API development

---

← [Testing](12-testing.md) | **Next: [Advanced Topics](14-advanced-topics.md)** → 