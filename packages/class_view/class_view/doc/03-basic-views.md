# Basic Views

Class View provides several fundamental view types that handle common web application patterns. Each view type focuses
on a specific purpose, making your code more organized and maintainable.

## View Base Class

The `View` class is the foundation for all other views. It handles HTTP method dispatching and provides
framework-agnostic access to request data.

```dart
class APIInfoView extends View {
  @override
  List<String> get allowedMethods => ['GET'];
  
  @override
  Future<void> get() async {
    sendJson({
      'name': 'My API',
      'version': '1.0.0',
      'endpoints': ['/posts', '/users', '/auth'],
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}
```

### Common Patterns with Base View

```dart
class HealthCheckView extends View {
  @override
  Future<void> get() async {
    final status = await checkSystemHealth();
    sendJson({
      'status': status.isHealthy ? 'healthy' : 'unhealthy',
      'checks': status.checks,
    }, statusCode: status.isHealthy ? 200 : 503);
  }
  
  @override
  Future<void> setup() async {
    // Skip authentication for health checks
  }
}
```

## TemplateView

`TemplateView` renders static or dynamic content using templates. Perfect for pages that display information without
complex data fetching.

```dart
class AboutView extends TemplateView {
  @override
  String get templateName => 'pages/about.html';
  
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'company_name': 'Acme Corp',
      'founded_year': 2020,
      'team_size': await getTeamSize(),
      'features': ['Fast', 'Reliable', 'Secure'],
    };
  }
}
```

### Dynamic Template Selection

```dart
class LandingPageView extends TemplateView {
  @override
  String get templateName {
    final isMobile = getHeader('user-agent')?.contains('Mobile') ?? false;
    return isMobile ? 'mobile/landing.html' : 'desktop/landing.html';
  }
  
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final location = getParam('location') ?? 'global';
    return {
      'offers': await getLocalOffers(location),
      'testimonials': await getTestimonials(limit: 3),
    };
  }
}
```

### Template with Form Integration

```dart
class ContactPageView extends TemplateView {
  @override
  String get templateName => 'contact.html';
  
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'contact_form': ContactForm(),
      'office_locations': await getOfficeLocations(),
      'support_hours': '9 AM - 5 PM EST',
    };
  }
}
```

## RedirectView

`RedirectView` handles URL redirects with flexible logic for determining the target URL.

```dart
class LoginRedirectView extends RedirectView {
  @override
  Future<String> getRedirectUrl() async {
    if (await isAuthenticated()) {
      final returnTo = getParam('return_to');
      return returnTo ?? '/dashboard';
    }
    return '/login';
  }
}
```

### Conditional Redirects

```dart
class FeatureToggleView extends RedirectView {
  @override
  Future<String> getRedirectUrl() async {
    final feature = getParam('feature');
    
    if (!await isFeatureEnabled(feature)) {
      return '/features/coming-soon';
    }
    
    if (!await hasPermission(feature)) {
      return '/upgrade';
    }
    
    return '/features/$feature';
  }
  
  @override
  int get statusCode => 302; // Temporary redirect
}
```

### Permanent Redirects for SEO

```dart
class OldUrlRedirectView extends RedirectView {
  static final Map<String, String> _redirectMap = {
    '/old-blog': '/blog',
    '/products/legacy': '/products/new',
    '/contact-us': '/contact',
  };
  
  @override
  Future<String> getRedirectUrl() async {
    final currentPath = getParam('path') ?? uri.path;
    return _redirectMap[currentPath] ?? '/';
  }
  
  @override
  int get statusCode => 301; // Permanent redirect
}
```

## Custom Views

When built-in views don't fit your needs, create custom views by extending the base `View` class:

```dart
class FileDownloadView extends View {
  @override
  List<String> get allowedMethods => ['GET'];
  
  @override
  Future<void> get() async {
    final fileId = getParam('file_id');
    final file = await fileRepository.findById(fileId);
    
    if (file == null) {
      throw HttpException.notFound('File not found');
    }
    
    if (!await canAccessFile(file)) {
      throw HttpException.forbidden('Access denied');
    }
    
    // Set download headers
    setHeader('Content-Type', file.mimeType);
    setHeader('Content-Disposition', 'attachment; filename="${file.name}"');
    setHeader('Content-Length', file.size.toString());
    
    // Stream file content
    await streamFile(file);
  }
}
```

### WebSocket Upgrade View

```dart
class ChatWebSocketView extends View {
  @override
  List<String> get allowedMethods => ['GET'];
  
  @override
  Future<void> get() async {
    if (!isWebSocketUpgrade()) {
      throw HttpException.badRequest('WebSocket upgrade required');
    }
    
    final roomId = getParam('room_id');
    final room = await chatService.getRoom(roomId);
    
    if (!await canJoinRoom(room)) {
      throw HttpException.forbidden('Cannot join room');
    }
    
    await upgradeToWebSocket(
      onConnect: () => room.addUser(currentUser),
      onMessage: (message) => room.broadcast(message),
      onDisconnect: () => room.removeUser(currentUser),
    );
  }
}
```

### API Versioning View

```dart
class VersionedAPIView extends View {
  @override
  Future<void> dispatch() async {
    final version = getHeader('API-Version') ?? getParam('version') ?? 'v1';
    
    if (!supportedVersions.contains(version)) {
      sendJson({
        'error': 'Unsupported API version',
        'supported_versions': supportedVersions,
      }, statusCode: 400);
      return;
    }
    
    // Set API version context
    setContext('api_version', version);
    
    // Continue with normal dispatch
    await super.dispatch();
  }
}
```

## Best Practices

1. **Use Built-in Views**: Prefer built-in views for common operations
2. **Keep Views Simple**: Focus on a single responsibility
3. **Handle Errors**: Use appropriate HTTP exceptions
4. **Async Support**: Make all methods properly asynchronous
5. **Framework Agnostic**: Avoid framework-specific code
6. **Documentation**: Document custom views clearly

## What's Next?

- Learn about [CRUD Views](04-crud-views.md) for database operations
- Explore [Mixins](05-mixins.md) for custom functionality
- See [Framework Integration](06-framework-integration.md) for connecting to web frameworks

---

← [Core Concepts](02-core-concepts.md) | **Next: [CRUD Views](04-crud-views.md)** → 