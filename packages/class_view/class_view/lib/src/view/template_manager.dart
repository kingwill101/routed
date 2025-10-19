import 'engines/liquify_view_engine.dart';
import 'form/template_renderer.dart';
import 'view_engine.dart';

/// Default templates for common UI patterns
class DefaultTemplates {
  static Map<String, String> createTemplateMap() => {
    // Base layouts
    'views/base.html': '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ title | default: 'Class View App' }}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 2rem; }
        .container { max-width: 800px; margin: 0 auto; }
        .form-errors { color: red; margin-bottom: 1rem; }
        .field-errors { color: red; font-size: 0.9em; }
        .help-text { color: #666; font-size: 0.9em; }
        .pagination { margin: 2rem 0; }
        .pagination a { margin: 0 0.5rem; padding: 0.5rem; }
        .btn { padding: 0.5rem 1rem; margin: 0.5rem; }
        .btn-primary { background: #007bff; color: white; }
        .btn-danger { background: #dc3545; color: white; }
    </style>
</head>
<body>
    <div class="container">
        {{ content }}
    </div>
</body>
</html>
''',

    // Form layouts
    'form/form_div.html': '''
{% if errors %}
<div class="form-errors">
    {% for error in errors %}
        <div>{{ error }}</div>
    {% endfor %}
</div>
{% endif %}
<form method="post">
    {% for field_data in fields %}
        {% assign field = field_data[0] %}
        {% assign field_errors = field_data[1] %}
        <div class="form-field">
            {{ field.label_html }}
            {{ field.widget_html }}
            {% if field_errors %}
                <div class="field-errors">
                    {% for error in field_errors %}
                        <div>{{ error }}</div>
                    {% endfor %}
                </div>
            {% endif %}
            {% if field.help_text %}
                <div class="help-text">{{ field.help_text }}</div>
            {% endif %}
        </div>
    {% endfor %}
    <button type="submit" class="btn btn-primary">Submit</button>
</form>
''',

    'form/form_table.html': '''
{% if errors %}
<div class="form-errors">
    {% for error in errors %}
        <div>{{ error }}</div>
    {% endfor %}
</div>
{% endif %}
<form method="post">
    <table>
        {% for field_data in fields %}
            {% assign field = field_data[0] %}
            {% assign field_errors = field_data[1] %}
            <tr>
                <td>{{ field.label_html }}</td>
                <td>
                    {{ field.widget_html }}
                    {% if field_errors %}
                        <div class="field-errors">
                            {% for error in field_errors %}
                                <div>{{ error }}</div>
                            {% endfor %}
                        </div>
                    {% endif %}
                    {% if field.help_text %}
                        <div class="help-text">{{ field.help_text }}</div>
                    {% endif %}
                </td>
            </tr>
        {% endfor %}
        <tr>
            <td></td>
            <td><button type="submit" class="btn btn-primary">Submit</button></td>
        </tr>
    </table>
</form>
''',

    'forms/field.html': '''
<div class="form-field">
    {{ field.label_html }}
    {{ field.widget_html }}
    {% if field.help_text_html %}
        {{ field.help_text_html }}
    {% endif %}
    {% if field.errors_html %}
        {{ field.errors_html }}
    {% endif %}
</div>
''',

    'form/form_p.html': '''
{% if errors %}
<div class="form-errors">
    {% for error in errors %}
        <p>{{ error }}</p>
    {% endfor %}
</div>
{% endif %}
<form method="post">
    {% for field_data in fields %}
        {% assign field = field_data[0] %}
        {% assign field_errors = field_data[1] %}
        <p>
            {{ field.label_html }}<br>
            {{ field.widget_html }}
            {% if field_errors %}
                <br><span class="field-errors">
                    {% for error in field_errors %}
                        {{ error }}{% unless forloop.last %}, {% endunless %}
                    {% endfor %}
                </span>
            {% endif %}
            {% if field.help_text %}
                <br><span class="help-text">{{ field.help_text }}</span>
            {% endif %}
        </p>
    {% endfor %}
    <p><button type="submit" class="btn btn-primary">Submit</button></p>
</form>
''',

    // Widget templates
    'widgets/text.html':
        '''<input type="text" name="{{ widget.name }}" value="{{ widget.value | default: '' }}"{% for attr in widget.attrs %} {{ attr[0] }}="{{ attr[1] }}"{% endfor %}>''',

    'widgets/email.html':
        '''<input type="email" name="{{ widget.name }}" value="{{ widget.value | default: '' }}"{% for attr in widget.attrs %} {{ attr[0] }}="{{ attr[1] }}"{% endfor %}>''',

    'widgets/password.html':
        '''<input type="password" name="{{ widget.name }}" value="{{ widget.value | default: '' }}"{% for attr in widget.attrs %} {{ attr[0] }}="{{ attr[1] }}"{% endfor %}>''',

    'widgets/textarea.html':
        '''<textarea name="{{ widget.name }}"{% for attr in widget.attrs %} {{ attr[0] }}="{{ attr[1] }}"{% endfor %}>{{ widget.value | default: '' }}</textarea>''',

    'widgets/checkbox.html':
        '''<input type="checkbox" name="{{ widget.name }}" value="{{ widget.value | default: 'on' }}"{% if widget.checked %} checked{% endif %}{% for attr in widget.attrs %} {{ attr[0] }}="{{ attr[1] }}"{% endfor %}>''',

    'widgets/select.html': '''
<select name="{{ widget.name }}"{% for attr in widget.attrs %} {{ attr[0] }}="{{ attr[1] }}"{% endfor %}>
    {% for option in widget.options %}
        <option value="{{ option.value }}"{% if option.selected %} selected{% endif %}>{{ option.label }}</option>
    {% endfor %}
</select>''',

    // View templates
    'views/list.html': '''
<h1>{{ title | default: 'List View' }}</h1>
{% if objects %}
    <div class="object-list">
        {% for object in objects %}
            <div class="object-item">
                {% if object.title %}
                    <h3>{{ object.title }}</h3>
                {% endif %}
                {% if object.excerpt %}
                    <p>{{ object.excerpt }}</p>
                {% endif %}
                {{ object }}
            </div>
        {% endfor %}
    </div>
    
    {% if pagination %}
        <div class="pagination">
            {% if pagination.page > 1 %}
                <a href="?page={{ pagination.page | minus: 1 }}">&laquo; Previous</a>
            {% endif %}
            <span>Page {{ pagination.page }} of {{ pagination.pages }}</span>
            {% if pagination.page < pagination.pages %}
                <a href="?page={{ pagination.page | plus: 1 }}">Next &raquo;</a>
            {% endif %}
            <span>({{ pagination.total }} total)</span>
        </div>
    {% endif %}
{% else %}
    <p>No items found.</p>
{% endif %}
''',

    'views/detail.html': '''
<h1>{{ object.title | default: 'Detail View' }}</h1>
{% if object.content %}
    <div class="content">{{ object.content }}</div>
{% endif %}
<div class="object-details">
    {{ object }}
</div>
''',
  };
}

/// Template management system with default templates and helper methods
class TemplateManager {
  static TemplateManager? _instance;

  // Make ViewEngine nullable and injectable
  final ViewEngine? _engine;
  late final TemplateRenderer _renderer;
  final Map<String, String> _registeredTemplates = {};

  // Initialize TemplateRenderer with the provided ViewEngine
  TemplateManager._(this._engine)
    : _renderer = TemplateRenderer(viewEngine: _engine);

  /// Get the global template manager instance
  static TemplateManager get instance {
    // Initialize with a null ViewEngine by default if not explicitly set
    return _instance ??= TemplateManager._(null);
  }

  /// Initialize with a custom ViewEngine
  static void initialize(ViewEngine engine) {
    _instance = TemplateManager._(engine);
  }

  /// Configure with custom options
  static void configure({
    String templateDirectory = 'templates',
    Map<String, String>? extraTemplates,
    bool cacheTemplates = true,
  }) {
    final allTemplates = <String, String>{
      ...DefaultTemplates.createTemplateMap(),
      ...?extraTemplates,
    };

    _instance = TemplateManager._(
      LiquifyViewEngine.combined(
        templateDirectory: templateDirectory,
        memoryTemplates: allTemplates,
        cacheTemplates: cacheTemplates,
      ),
    );
  }

  /// Configure with memory-only templates (for testing)
  static void configureMemoryOnly({Map<String, String>? extraTemplates}) {
    final templates = <String, String>{
      ...DefaultTemplates.createTemplateMap(),
      ...?extraTemplates,
    };

    _instance = TemplateManager._(
      LiquifyViewEngine.memoryOnly(templates: templates),
    );
  }

  /// Register a template at runtime
  static void registerTemplate(String name, String content) {
    instance._registeredTemplates[name] = content;
  }

  /// Get all registered templates
  static Map<String, String> get registeredTemplates =>
      Map.from(instance._registeredTemplates);

  /// Render a template with data
  static Future<String> render(
    String templateName, [
    Map<String, dynamic>? data,
  ]) async {
    // Ensure renderer is initialized if instance exists
    if (_instance?._renderer == null) {
      throw StateError(
        "TemplateManager is not initialized or renderer is not configured. Call TemplateManager.initialize() or TemplateManager.configure().",
      );
    }

    // Use the default engine if available, otherwise throw
    if (_instance!._engine == null) {
      throw StateError(
        "No ViewEngine is configured. Please initialize TemplateManager with a ViewEngine.",
      );
    }

    return _instance!._engine!.render(templateName, data ?? {});
  }

  /// Render a template from file path
  static Future<String> renderFile(
    String filePath, [
    Map<String, dynamic>? data,
  ]) async {
    if (_instance?._engine == null) {
      throw StateError(
        "No ViewEngine is configured. Please initialize TemplateManager with a ViewEngine.",
      );
    }
    return _instance!._engine!.renderFile(filePath, data);
  }

  /// Get the underlying engine
  static ViewEngine? get engine => _instance?._engine;

  /// Get the default renderer
  static TemplateRenderer? get renderer => _instance?._renderer;

  /// Reset (clear instance)
  static void reset() {
    _instance = null;
  }
}

/// Extension for easy template rendering
extension TemplateExtension on Object {
  /// Render this object with a template
  Future<String> renderWith(
    String templateName, [
    Map<String, dynamic>? extraData,
  ]) async {
    // Ensure TemplateManager is initialized and has an engine
    if (TemplateManager.engine == null) {
      throw StateError(
        "TemplateManager is not initialized with a ViewEngine. Call TemplateManager.initialize() or TemplateManager.configure() first.",
      );
    }

    final data = <String, dynamic>{'object': this, ...?extraData};
    // Pass the default engine from TemplateManager to the rendering call
    return TemplateManager.engine!.render(templateName, data);
  }
}
