# Templates

Class View provides a flexible templating system that integrates with various template engines. This guide covers
template
usage, inheritance patterns, and best practices for rendering views.

## Template Engines

Class View supports multiple template engines through the `ViewEngine` interface:

```dart
abstract class ViewEngine {
  /// File extensions this engine handles
  List<String> get extensions;
  
  /// Render a template with data
  Future<String> render(String name, [Map<String, dynamic>? data]);
  
  /// Render a template file directly
  Future<String> renderFile(String filePath, [Map<String, dynamic>? data]);
}
```

### Built-in Engines

Class View comes with built-in support for Liquid templates:

```dart
// Basic setup
final liquidEngine = LiquifyViewEngine(
  templateDirectory: 'templates',
  cacheTemplates: true,
);

// Custom setup
final liquidEngine = LiquifyViewEngine(
  templateDirectory: 'templates',
  cacheTemplates: true,
  defaultContext: {
    'site_name': 'My App',
    'version': '1.0.0',
  },
);
```

### Custom Engine Example

```dart
class MustacheViewEngine implements ViewEngine {
  final Map<String, String> templates;
  final Map<String, Function> helpers;
  
  MustacheViewEngine({
    required this.templates,
    this.helpers = const {},
  });
  
  @override
  List<String> get extensions => ['.mustache', '.handlebars', '.hbs'];
  
  @override
  Future<String> render(String name, [Map<String, dynamic>? data]) async {
    final template = templates[name];
    if (template == null) throw TemplateNotFoundException(name);
    
    return processMustacheTemplate(template, data ?? {}, helpers: helpers);
  }
  
  @override
  Future<String> renderFile(String filePath, [Map<String, dynamic>? data]) async {
    final content = await File(filePath).readAsString();
    return processMustacheTemplate(content, data ?? {}, helpers: helpers);
  }
}
```

## Template Manager

Configure the global template system:

```dart
// Basic setup
TemplateManager.configure(
  templateDirectory: 'templates',
  cacheTemplates: true,
);

// Custom engine setup
TemplateManager.initialize(MustacheViewEngine(
  templates: loadTemplates(),
  helpers: {
    'formatDate': (date) => DateFormat('MMM d, y').format(date),
    'pluralize': (count, singular, plural) => 
      count == 1 ? singular : plural,
  },
));

// Memory-only setup (testing)
TemplateManager.configureMemoryOnly(
  extraTemplates: {
    'layout.html': '''
      <!DOCTYPE html>
      <html>
        <head><title>{{ title }}</title></head>
        <body>{{ content }}</body>
      </html>
    ''',
  },
);
```

## Liquid Templates

Class View uses Liquid templating by default, providing Django-like syntax:

### Basic Syntax

```liquid
<!-- templates/base.html -->
<!DOCTYPE html>
<html lang="{{ language | default: 'en' }}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{% block title %}{{ site_title | default: 'My App' }}{% endblock %}</title>
  
  {% for css_file in css_files %}
    <link rel="stylesheet" href="{{ css_file }}">
  {% endfor %}
  
  {% block extra_head %}{% endblock %}
</head>
<body>
  <header>
    <nav>
      <a href="/" class="brand">{{ site_title }}</a>
      
      <ul class="nav-links">
        {% for item in navigation %}
          <li class="nav-item {{ item.class }}">
            <a href="{{ item.url }}" 
               {% if item.active %}class="active"{% endif %}>
              {{ item.title }}
            </a>
          </li>
        {% endfor %}
      </ul>
    </nav>
  </header>
  
  <main>
    {% if messages %}
      <div class="messages">
        {% for message in messages %}
          <div class="alert alert-{{ message.level }}">
            {{ message.text }}
          </div>
        {% endfor %}
      </div>
    {% endif %}
    
    {% block content %}{% endblock %}
  </main>
  
  <footer>
    <p>&copy; {{ 'now' | date: '%Y' }} {{ site_title }}</p>
  </footer>
</body>
</html>
```

### Template Inheritance

```liquid
<!-- templates/layouts/app.html -->
{% extends "base.html" %}

{% block title %}{{ page_title }} - {{ block.super }}{% endblock %}

{% block extra_head %}
  <link rel="stylesheet" href="/css/app.css">
{% endblock %}

{% block content %}
  <div class="page-header">
    <h1>{{ page_title }}</h1>
    {% if page_subtitle %}
      <p class="subtitle">{{ page_subtitle }}</p>
    {% endif %}
  </div>
  
  <div class="page-content">
    {% block page_content %}{% endblock %}
  </div>
{% endblock %}
```

```liquid
<!-- templates/posts/list.html -->
{% extends "layouts/app.html" %}

{% assign page_title = "Blog Posts" %}
{% assign page_subtitle = "Latest articles and updates" %}

{% block page_content %}
  <div class="posts-grid">
    {% for post in posts %}
      <article class="post-card">
        <h2><a href="/posts/{{ post.slug }}">{{ post.title }}</a></h2>
        <p class="meta">
          By {{ post.author.name }} on {{ post.published_at | date: '%B %d, %Y' }}
        </p>
        <p class="excerpt">{{ post.excerpt }}</p>
      </article>
    {% endfor %}
  </div>
  
  {% if pagination %}
    <div class="pagination">
      {% if pagination.previous %}
        <a href="?page={{ pagination.previous }}" class="prev">Previous</a>
      {% endif %}
      
      <span class="current">
        Page {{ pagination.current }} of {{ pagination.total }}
      </span>
      
      {% if pagination.next %}
        <a href="?page={{ pagination.next }}" class="next">Next</a>
      {% endif %}
    </div>
  {% endif %}
{% endblock %}
```

## Using Templates in Views

### Basic Template View

```dart
class PostListView extends TemplateView {
  @override
  String get templateName => 'posts/list.html';
  
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final page = getCurrentPage();
    final posts = await postRepository.findAll(page: page);
    
    return {
      'posts': posts.items,
      'pagination': {
        'current': page,
        'total': (posts.total / pageSize).ceil(),
        'previous': page > 1 ? page - 1 : null,
        'next': page < (posts.total / pageSize).ceil() ? page + 1 : null,
      },
    };
  }
}
```

### Form Template View

```dart
class PostCreateView extends TemplateView {
  @override
  String get templateName => 'posts/create.html';
  
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'form': PostForm(),
      'categories': await categoryRepository.findAll(),
    };
  }
  
  @override
  Future<void> post() async {
    final form = PostForm(data: await getJsonBody());
    
    if (await form.isValid()) {
      await postRepository.create(form.cleanedData);
      redirect('/posts');
    } else {
      // Re-render with errors
      setContext('form', form);
      await super.get();
    }
  }
}
```

## Template Filters

### Built-in Filters

```liquid
{{ value | default: 'fallback' }}
{{ date | date: '%Y-%m-%d' }}
{{ text | truncate: 100 }}
{{ list | join: ', ' }}
{{ number | format: '0.00' }}
{{ text | escape }}
{{ html | safe }}
```

### Custom Filters

```dart
class CustomFilters {
  static String formatCurrency(dynamic value) {
    return '\$${value.toStringAsFixed(2)}';
  }
  
  static String slugify(String text) {
    return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}

// Register filters
TemplateManager.registerFilters({
  'currency': CustomFilters.formatCurrency,
  'slugify': CustomFilters.slugify,
});

// Usage in templates
{{ price | currency }}
{{ title | slugify }}
```

## Best Practices

1. **Template Organization**: Keep templates in a logical directory structure
2. **Template Inheritance**: Use base templates and blocks for consistent layouts
3. **Reusable Components**: Create partial templates for repeated elements
4. **Context Data**: Keep view logic separate from template logic
5. **Error Handling**: Always handle missing or invalid data gracefully
6. **Performance**: Use template caching in production

## What's Next?

- Learn about [Testing](12-testing.md) for testing your views
- Explore [Best Practices](13-best-practices.md) for more patterns
- See [Framework Integration](06-framework-integration.md) for connecting to web frameworks 