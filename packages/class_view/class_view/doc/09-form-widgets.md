# Form Widgets Reference

Widgets control how form fields are rendered as HTML. They handle the presentation layer, converting field values into
HTML input elements and extracting user input back into Dart values.

## Widget Rendering Architecture

### Three-Tier Rendering System

Widgets use a sophisticated three-tier rendering fallback system that ensures graceful degradation:

1. **Tier 1: Template Rendering via Renderer**
    - Widgets first attempt to render using a configured `Renderer`
    - The `Renderer` uses a `ViewEngine` to process templates
    - Templates can be in any format supported by the ViewEngine (Liquid, Jinja, Mustache, etc.)

2. **Tier 2: Renderer's DefaultView (if supported)**
    - If template rendering fails and the `Renderer` implements `DefaultView`
    - The renderer's own fallback rendering is used

3. **Tier 3: Widget's DefaultView Fallback**
    - If all else fails, widgets use their built-in `DefaultView` mixin
    - Provides guaranteed HTML output using pure Dart string building

```dart
// Example of the fallback system in action
class MyWidget extends Widget with DefaultView {
  @override
  Future<String> render(String name, dynamic value, {Renderer? renderer}) async {
    final context = getContext(name, value);
    
    // Tier 1: Try template rendering
    if (renderer != null && templateName != null) {
      try {
        return await renderer.renderAsync(templateName!, context);
      } catch (e) {
        // Template failed, continue to tier 2/3
      }
    }
    
    // Tier 3: Use DefaultView fallback (tier 2 handled internally)
    return await renderDefault(context);
  }
  
  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    // Guaranteed HTML output
    return '<input type="text" name="${context['widget']['name']}" value="${context['widget']['value'] ?? ''}">';
  }
}
```

### Renderer and ViewEngine Integration

The rendering system integrates with the broader Class View architecture:

```dart
// Setting up rendering in a view
class MyFormView extends View with ContextMixin {
  @override
  Future<void> get() async {
    // Configure rendering system with any ViewEngine
    final viewEngine = LiquifyViewEngine.memoryOnly(
      templates: customTemplates,
      cacheTemplates: true,
    );
    final renderer = TemplateRenderer(viewEngine: viewEngine);
    
    // Create form with renderer
    final form = ContactForm(renderer: renderer);
    
    // Form and widgets will use the rendering system
    final html = await form.asP(); // Uses templates if available, DefaultView as fallback
    
    sendHtml(html);
  }
}
```

### DefaultView Mixin

All widgets include the `DefaultView` mixin, which provides failsafe HTML rendering:

```dart
mixin DefaultView {
  /// Renders the widget using pure Dart without templates
  /// 
  /// This method is called when:
  /// - No renderer is configured
  /// - Template rendering fails
  /// - Template files are missing
  Future<String> renderDefault(Map<String, dynamic> context);
}
```

**Benefits of DefaultView:**

- **Zero Configuration**: Widgets work immediately without setup
- **Guaranteed Rendering**: Always produces valid HTML
- **Development Friendly**: Quick prototyping without template files
- **Graceful Degradation**: Production apps continue working if templates fail

### Template Integration

When templates are available, widgets use whatever templating format the ViewEngine supports:

**Liquid Templates** (using LiquifyViewEngine):

```liquid
<!-- widgets/text.html -->
<input type="text" 
       name="{{ widget.name }}" 
       value="{{ widget.value | default: '' }}"
       {% for attr in widget.attrs %}{{ attr[0] }}="{{ attr[1] }}"{% endfor %}>
```

**Jinja-style Templates** (using custom Jinja ViewEngine):

```jinja2
<!-- widgets/text.html -->
<input type="text" 
       name="{{ widget.name }}" 
       value="{{ widget.value or '' }}"
       {% for key, value in widget.attrs.items() %}{{ key }}="{{ value }}"{% endfor %}>
```

**Mustache Templates** (using custom Mustache ViewEngine):

```mustache
<!-- widgets/text.html -->
<input type="text" 
       name="{{widget.name}}" 
       value="{{widget.value}}"
       {{#widget.attrs}}{{key}}="{{value}}" {{/widget.attrs}}>
```

Templates receive the same context data structure regardless of format, ensuring consistency between different
ViewEngines and DefaultView rendering.

## Widget Architecture

### Widget Lifecycle

Every widget follows this rendering process:

```dart
// 1. Get context data
final context = widget.getContext(name, value, attrs);

// 2. Format the value for display
final formattedValue = widget.formatValue(value);

// 3. Build HTML attributes
final finalAttrs = widget.buildAttrs(baseAttrs, extraAttrs);

// 4. Render the HTML (three-tier system)
final html = await widget.render(name, value, attrs: attrs);
```

### Widget Base Properties

All widgets inherit these properties:

```dart
Widget({
  Map<String, dynamic>? attrs,     // HTML attributes
  String? templateName,            // Template for rendering
}) {
  this.attrs = attrs ?? {};
  this.templateName = templateName;
}
```

## Text Input Widgets

### TextInput

Basic single-line text input:

```dart
TextInput(attrs: {
  'class': 'form-control',
  'placeholder': 'Enter text...',
  'maxlength': '100',
  'autocomplete': 'on',
})
```

**Renders as**: `<input type="text" ...>`
**Template**: `widgets/text.html`

### PasswordInput

Password input with hidden text:

```dart
PasswordInput(attrs: {
  'class': 'form-control',
  'autocomplete': 'current-password',
  'minlength': '8',
})
```

**Renders as**: `<input type="password" ...>`
**Template**: `widgets/password.html`

### HiddenInput

Hidden input for storing values:

```dart
HiddenInput()
```

**Renders as**: `<input type="hidden" ...>`
**Template**: `widgets/hidden.html`

### EmailInput

HTML5 email input with browser validation:

```dart
EmailInput(attrs: {
  'class': 'form-control',
  'placeholder': 'user@example.com',
})
```

**Renders as**: `<input type="email" ...>`
**Template**: `widgets/email.html`

### URLInput

HTML5 URL input:

```dart
URLInput(attrs: {
  'class': 'form-control',
  'placeholder': 'https://example.com',
})
```

**Renders as**: `<input type="url" ...>`
**Template**: `widgets/url.html`

### TelInput

Telephone number input:

```dart
TelInput(attrs: {
  'class': 'form-control',
  'placeholder': '+1-555-123-4567',
})
```

**Renders as**: `<input type="tel" ...>`
**Template**: `widgets/tel.html`

### SearchInput

Search input with browser-specific styling:

```dart
SearchInput(attrs: {
  'class': 'form-control',
  'placeholder': 'Search...',
  'results': '10',
})
```

**Renders as**: `<input type="search" ...>`
**Template**: `widgets/search.html`

### Textarea

Multi-line text input:

```dart
Textarea(attrs: {
  'rows': '5',
  'cols': '40',
  'class': 'form-control',
  'placeholder': 'Enter your message...',
})
```

**Renders as**: `<textarea ...></textarea>`
**Template**: `widgets/textarea.html`

## Numeric Input Widgets

### NumberInput

HTML5 number input with step controls:

```dart
NumberInput(attrs: {
  'min': '0',
  'max': '100',
  'step': '1',
  'class': 'form-control',
})
```

**Renders as**: `<input type="number" ...>`
**Template**: `widgets/number.html`

## Date and Time Widgets

### DateInput

HTML5 date picker:

```dart
DateInput(attrs: {
  'type': 'date',
  'class': 'form-control',
})
```

**Renders as**: `<input type="date" ...>`
**Template**: `widgets/date.html`

### TimeInput

HTML5 time picker:

```dart
TimeInput(attrs: {
  'type': 'time',
  'class': 'form-control',
  'step': '1',
})
```

**Renders as**: `<input type="time" ...>`
**Template**: `widgets/time.html`

### DateTimeInput

HTML5 datetime-local input:

```dart
DateTimeInput(attrs: {
  'type': 'datetime-local',
  'class': 'form-control',
})
```

**Renders as**: `<input type="datetime-local" ...>`
**Template**: `widgets/datetime.html`

### SplitDateTimeWidget

Separate date and time inputs:

```dart
SplitDateTimeWidget(
  dateWidget: DateInput(attrs: {'type': 'date'}),
  timeWidget: TimeInput(attrs: {'type': 'time'}),
  attrs: {'class': 'split-datetime'},
)
```

**Renders as**: Two separate inputs in a container
**Template**: `widgets/split_datetime.html`

## Choice Widgets

### Select

Dropdown select menu:

```dart
Select(
  choices: [
    ['small', 'Small'],
    ['medium', 'Medium'],
    ['large', 'Large'],
  ],
  attrs: {'class': 'form-control'},
)
```

**Renders as**: `<select>` with `<option>` elements
**Template**: `widgets/select.html`

### SelectMultiple

Multiple selection dropdown (Ctrl+click):

```dart
SelectMultiple(
  choices: choices,
  attrs: {
    'class': 'form-control',
    'size': '5',
    'multiple': true,
  },
)
```

**Renders as**: `<select multiple>` with `<option>` elements
**Template**: `widgets/select_multiple.html`

### RadioSelect

Radio button group:

```dart
RadioSelect(
  choices: [
    ['yes', 'Yes'],
    ['no', 'No'],
    ['maybe', 'Maybe'],
  ],
)
```

**Renders as**: Multiple `<input type="radio">` elements
**Template**: `widgets/radio.html`

### CheckboxSelectMultiple

Checkbox group for multiple selections:

```dart
CheckboxSelectMultiple(
  choices: [
    ['feature1', 'Feature 1'],
    ['feature2', 'Feature 2'],
    ['feature3', 'Feature 3'],
  ],
)
```

**Renders as**: Multiple `<input type="checkbox">` elements
**Template**: `widgets/checkbox_select.html`

### NullBooleanSelect

Three-state boolean selector:

```dart
NullBooleanSelect()
```

**Renders as**: `<select>` with Unknown/Yes/No options
**Template**: `widgets/null_boolean_select.html`

## Boolean Widgets

### CheckboxInput

Single checkbox:

```dart
CheckboxInput(attrs: {
  'class': 'form-check-input',
})
```

**Renders as**: `<input type="checkbox" ...>`
**Template**: `widgets/checkbox.html`

## File Widgets

### FileInput

Basic file upload:

```dart
FileInput(attrs: {
  'accept': '.pdf,.doc,.docx',
  'class': 'form-control',
})
```

**Renders as**: `<input type="file" ...>`
**Template**: `widgets/file.html`

### ClearableFileInput

File input with option to clear existing file:

```dart
ClearableFileInput(attrs: {
  'accept': 'image/*',
})
```

**Renders as**: File input with "Clear" checkbox for existing files
**Template**: `widgets/clearable_file_input.html`

### MultipleHiddenInput

Multiple hidden inputs for lists:

```dart
MultipleHiddenInput()
```

**Renders as**: Multiple `<input type="hidden">` elements
**Template**: `widgets/multiple_hidden.html`

## Color and Media Widgets

### ColorInput

HTML5 color picker:

```dart
ColorInput(attrs: {
  'class': 'form-control',
})
```

**Renders as**: `<input type="color" ...>`
**Template**: `widgets/color.html`

## Multi-Value Widgets

### MultiWidget

Combines multiple widgets into one:

```dart
class AddressWidget extends MultiWidget {
  AddressWidget() : super(
    widgets: [
      TextInput(attrs: {'placeholder': 'Street'}),
      TextInput(attrs: {'placeholder': 'City'}),
      TextInput(attrs: {'placeholder': 'State'}),
      TextInput(attrs: {'placeholder': 'ZIP'}),
    ],
  );
  
  @override
  List<String> decompress(dynamic value) {
    if (value is Address) {
      return [value.street, value.city, value.state, value.zip];
    }
    return ['', '', '', ''];
  }
}
```

**Renders as**: Multiple widgets in sequence
**Template**: Custom or `widgets/multi_widget.html`

## Custom Widgets

### Creating Custom Widgets

```dart
class RatingWidget extends Widget with DefaultView {
  final int maxRating;
  
  RatingWidget({
    this.maxRating = 5,
    super.attrs,
  });
  
  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    final name = context['widget']['name'];
    final value = int.tryParse(context['widget']['value']?.toString() ?? '0') ?? 0;
    final attrs = context['widget']['attrs'] as Map<String, dynamic>;
    
    final buffer = StringBuffer();
    buffer.write('<div class="rating-widget"');
    
    // Add container attributes
    attrs.forEach((key, val) {
      if (key != 'id' && key != 'name') {
        buffer.write(' $key="$val"');
      }
    });
    buffer.write('>');
    
    // Generate star inputs
    for (int i = 1; i <= maxRating; i++) {
      final checked = i <= value ? ' checked' : '';
      final id = '${name}_$i';
      
      buffer.write('''
        <input type="radio" name="$name" value="$i" id="$id"$checked class="star-input">
        <label for="$id" class="star-label">⭐</label>
      ''');
    }
    
    buffer.write('</div>');
    return buffer.toString();
  }
  
  @override
  dynamic formatValue(dynamic value) {
    if (value == null || value == '') return 0;
    return int.tryParse(value.toString()) ?? 0;
  }
  
  @override
  Map<String, dynamic> getContext(String name, dynamic value, [Map<String, dynamic>? extraAttrs]) {
    final context = super.getContext(name, value, extraAttrs);
    context['widget']['max_rating'] = maxRating;
    return context;
  }
}
```

### Advanced Widget with Template

```dart
class TagInputWidget extends Widget with DefaultView {
  TagInputWidget({super.attrs}) : super(
    templateName: 'widgets/tag_input.html',
  );
  
  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    final name = context['widget']['name'];
    final value = context['widget']['value'];
    final tags = value is List ? value : (value?.toString().split(',') ?? []);
    
    return '''
      <div class="tag-input-container">
        <div class="tag-display">
          ${tags.map((tag) => '<span class="tag">$tag <button type="button" class="tag-remove">×</button></span>').join('')}
        </div>
        <input type="text" 
               name="$name" 
               value="${tags.join(',')}"
               class="tag-input"
               placeholder="Add tags..."
               data-tags='${jsonEncode(tags)}'>
        <script>
          // JavaScript for tag functionality
          document.querySelector('[name="$name"]').addEventListener('keydown', function(e) {
            if (e.key === 'Enter' || e.key === ',') {
              e.preventDefault();
              // Add tag logic
            }
          });
        </script>
      </div>
    ''';
  }
  
  @override
  List<String> formatValue(dynamic value) {
    if (value is List) return value.cast<String>();
    if (value is String) return value.split(',').where((s) => s.trim().isNotEmpty).toList();
    return [];
  }
}
```

### Template-First Widget Design

For production applications, design widgets with templates first and DefaultView as backup:

```dart
class ProductCardWidget extends Widget with DefaultView {
  ProductCardWidget() : super(templateName: 'widgets/product_card.html');
  
  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    // Simplified fallback rendering
    final product = context['product'];
    return '''
      <div class="product-card-fallback">
        <h3>${product['name']}</h3>
        <p>Price: \$${product['price']}</p>
        <p>DefaultView rendering - add templates for full styling</p>
      </div>
    ''';
  }
}
```

Template file (`widgets/product_card.html`):

```liquid
<div class="product-card {{ widget.attrs.class }}">
  <img src="{{ product.image_url }}" alt="{{ product.name }}" class="product-image">
  <div class="product-info">
    <h3 class="product-title">{{ product.name }}</h3>
    <p class="product-price">${{ product.price | money }}</p>
    <p class="product-description">{{ product.description | truncate: 100 }}</p>
    <button class="btn btn-primary" data-product-id="{{ product.id }}">
      Add to Cart
    </button>
  </div>
</div>
```

## Widget Customization

### Styling Widgets

```dart
// Add CSS classes
TextInput(attrs: {
  'class': 'form-control custom-input',
})

// Add data attributes
TextInput(attrs: {
  'data-validation': 'required',
  'data-min-length': '5',
})

// Add event handlers
TextInput(attrs: {
  'onchange': 'validateField(this)',
  'onfocus': 'highlightField(this)',
})
```

### Conditional Attributes

```dart
class ConditionalWidget extends TextInput {
  final bool isRequired;
  
  ConditionalWidget({
    this.isRequired = false,
    super.attrs,
  });
  
  @override
  Map<String, dynamic> getContext(String name, dynamic value, [Map<String, dynamic>? extraAttrs]) {
    final context = super.getContext(name, value, extraAttrs);
    final widgetAttrs = context['widget']['attrs'] as Map<String, dynamic>;
    
    if (isRequired) {
      widgetAttrs['required'] = 'required';
      widgetAttrs['aria-required'] = 'true';
    }
    
    return context;
  }
}
```

### Widget Inheritance

```dart
// Base styled widget
abstract class StyledWidget extends Widget with DefaultView {
  StyledWidget({super.attrs, super.templateName}) {
    // Add default styling
    this.attrs['class'] = '${this.attrs['class'] ?? ''} styled-widget'.trim();
  }
}

// Specific styled widgets
class StyledTextInput extends StyledWidget {
  StyledTextInput({super.attrs}) : super(templateName: 'widgets/styled_text.html');
  
  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    return '''
      <div class="input-group">
        <input type="text" ${_renderAttrs(context['widget']['attrs'])} value="${context['widget']['value'] ?? ''}">
        <div class="input-group-append">
          <span class="input-icon">📝</span>
        </div>
      </div>
    ''';
  }
  
  String _renderAttrs(Map<String, dynamic> attrs) {
    return attrs.entries
        .map((e) => '${e.key}="${e.value}"')
        .join(' ');
  }
}
```

## Widget Configuration

### Global Widget Defaults

```dart
class FormWidgetConfig {
  static final Map<String, Map<String, dynamic>> defaultAttrs = {
    'TextInput': {
      'class': 'form-control',
      'autocomplete': 'on',
    },
    'EmailInput': {
      'class': 'form-control',
      'autocomplete': 'email',
    },
    'PasswordInput': {
      'class': 'form-control',
      'autocomplete': 'current-password',
    },
  };
  
  static Widget configureWidget(Widget widget) {
    final widgetType = widget.runtimeType.toString();
    final defaults = defaultAttrs[widgetType];
    
    if (defaults != null) {
      for (final entry in defaults.entries) {
        widget.attrs.putIfAbsent(entry.key, () => entry.value);
      }
    }
    
    return widget;
  }
}

// Usage
final widget = FormWidgetConfig.configureWidget(TextInput());
```

### Theme-Based Widgets

```dart
enum FormTheme { bootstrap, bulma, tailwind, material }

class ThemedWidgetFactory {
  static Widget createTextInput(FormTheme theme, {Map<String, dynamic>? attrs}) {
    final baseAttrs = Map<String, dynamic>.from(attrs ?? {});
    
    switch (theme) {
      case FormTheme.bootstrap:
        baseAttrs['class'] = '${baseAttrs['class'] ?? ''} form-control'.trim();
        break;
      case FormTheme.bulma:
        baseAttrs['class'] = '${baseAttrs['class'] ?? ''} input'.trim();
        break;
      case FormTheme.tailwind:
        baseAttrs['class'] = '${baseAttrs['class'] ?? ''} block w-full rounded-md border-gray-300'.trim();
        break;
      case FormTheme.material:
        baseAttrs['class'] = '${baseAttrs['class'] ?? ''} mdc-text-field__input'.trim();
        break;
    }
    
    return TextInput(attrs: baseAttrs);
  }
}
```

## Renderer and ViewEngine Setup

### Basic Setup with TemplateRenderer

```dart
// Configure ViewEngine with templates (Liquid example)
final viewEngine = LiquifyViewEngine.memoryOnly(
  templates: {
    'widgets/text.html': '<input type="text" name="{{ widget.name }}" value="{{ widget.value }}">',
    'widgets/textarea.html': '<textarea name="{{ widget.name }}">{{ widget.value }}</textarea>',
    // ... more templates
  },
  cacheTemplates: true,
);

// Create renderer
final renderer = TemplateRenderer(viewEngine: viewEngine);

// Use with forms
final form = ContactForm(renderer: renderer);
```

### Production Setup with File Templates

```dart
// Setup with file-based templates (any ViewEngine)
final viewEngine = LiquifyViewEngine(
  templateDirectory: 'templates',
  cacheTemplates: true,
);

final renderer = TemplateRenderer(
  viewEngine: viewEngine,
  formTemplateName: 'forms/custom_form.html',
  fieldTemplateName: 'forms/custom_field.html',
);

// Configure globally for views
class MyView extends View {
  @override
  Future<void> get() async {
    setRenderer(renderer);
    
    final form = ContactForm(renderer: this.renderer);
    final html = await form.asDiv();
    sendHtml(html);
  }
}
```

### Custom ViewEngine Integration

Anyone can implement their own ViewEngine for any templating format:

```dart
// Implement Jinja2-style ViewEngine
class JinjaViewEngine implements ViewEngine {
  final Map<String, String> templates;
  
  JinjaViewEngine({required this.templates});
  
  @override
  Future<String> render(String name, [Map<String, dynamic>? data]) async {
    final template = templates[name];
    if (template == null) throw TemplateNotFoundException(name);
    
    // Process Jinja2 syntax: {{ variable }}, {% for %}, etc.
    return processJinjaTemplate(template, data ?? {});
  }
  
  @override
  List<String> get extensions => ['.html', '.jinja2', '.j2'];
  
  @override
  Future<String> renderFile(String filePath, [Map<String, dynamic>? data]) async {
    return render(filePath, data);
  }
}

// Implement Mustache ViewEngine
class MustacheViewEngine implements ViewEngine {
  final Map<String, String> templates;
  
  MustacheViewEngine({required this.templates});
  
  @override
  Future<String> render(String name, [Map<String, dynamic>? data]) async {
    final template = templates[name];
    if (template == null) throw TemplateNotFoundException(name);
    
    // Process Mustache syntax: {{variable}}, {{#section}}, etc.
    return processMustacheTemplate(template, data ?? {});
  }
  
  @override
  List<String> get extensions => ['.html', '.mustache', '.handlebars'];
  
  @override
  Future<String> renderFile(String filePath, [Map<String, dynamic>? data]) async {
    return render(filePath, data);
  }
}

// Use any ViewEngine with TemplateRenderer
final jinjaRenderer = TemplateRenderer(viewEngine: JinjaViewEngine(templates: jinjaTemplates));
final mustacheRenderer = TemplateRenderer(viewEngine: MustacheViewEngine(templates: mustacheTemplates));
final liquidRenderer = TemplateRenderer(viewEngine: LiquifyViewEngine.memoryOnly(templates: liquidTemplates));
```

### ViewEngine Flexibility Examples

```dart
// Example: Switching between template engines
class FlexibleFormView extends View {
  final String templateEngine;
  
  FlexibleFormView(this.templateEngine);
  
  @override
  Future<void> get() async {
    late ViewEngine viewEngine;
    
    switch (templateEngine) {
      case 'liquid':
        viewEngine = LiquifyViewEngine.memoryOnly(templates: liquidTemplates);
        break;
      case 'jinja':
        viewEngine = JinjaViewEngine(templates: jinjaTemplates);
        break;
      case 'mustache':
        viewEngine = MustacheViewEngine(templates: mustacheTemplates);
        break;
      default:
        // No ViewEngine - will use DefaultView fallbacks
        final form = ContactForm();
        final html = await form.asDiv();
        sendHtml(html);
        return;
    }
    
    final renderer = TemplateRenderer(viewEngine: viewEngine);
    final form = ContactForm(renderer: renderer);
    final html = await form.asDiv();
    sendHtml(html);
  }
}
```

## Widget Testing

### Testing Widget Rendering

```dart
test('RatingWidget renders correctly', () async {
  final widget = RatingWidget(maxRating: 5);
  final html = await widget.render('rating', 3);
  
  expect(html, contains('rating-widget'));
  expect(html, contains('name="rating"'));
  expect(html, contains('value="1"'));
  expect(html, contains('value="5"'));
  expect(html, contains('checked')); // For value 3
});

test('Widget uses template when available', () async {
  final viewEngine = LiquifyViewEngine.memoryOnly(
    templates: {
      'widgets/text.html': '<input type="text" name="{{ widget.name }}" class="templated">',
    },
  );
  final renderer = TemplateRenderer(viewEngine: viewEngine);
  
  final widget = TextInput();
  final html = await widget.render('test', 'value', renderer: renderer);
  
  expect(html, contains('class="templated"'));
});

test('Widget falls back to DefaultView when template missing', () async {
  final viewEngine = LiquifyViewEngine.memoryOnly(templates: {});
  final renderer = TemplateRenderer(viewEngine: viewEngine);
  
  final widget = TextInput();
  final html = await widget.render('test', 'value', renderer: renderer);
  
  expect(html, contains('type="text"'));
  expect(html, contains('name="test"'));
  expect(html, contains('value="value"'));
});
```

### Testing Widget Context

```dart
test('widget context includes all required data', () {
  final widget = TextInput(attrs: {'class': 'test'});
  final context = widget.getContext('test_name', 'test_value');
  
  expect(context['widget']['name'], equals('test_name'));
  expect(context['widget']['value'], equals('test_value'));
  expect(context['widget']['attrs']['class'], equals('test'));
  expect(context['widget']['is_hidden'], isFalse);
});

test('custom widget context includes custom data', () {
  final widget = RatingWidget(maxRating: 5);
  final context = widget.getContext('rating', 3);
  
  expect(context['widget']['max_rating'], equals(5));
  expect(context['widget']['value'], equals(3));
});
```

## Performance Optimization

### Widget Caching

```dart
class CachedWidget extends Widget with DefaultView {
  static final Map<String, String> _renderCache = {};
  
  @override
  Future<String> render(String name, dynamic value, {Map<String, dynamic>? attrs, Renderer? renderer, String? templateName}) async {
    final cacheKey = _generateCacheKey(name, value, attrs);
    
    if (_renderCache.containsKey(cacheKey)) {
      return _renderCache[cacheKey]!;
    }
    
    final html = await super.render(name, value, attrs: attrs, renderer: renderer, templateName: templateName);
    _renderCache[cacheKey] = html;
    
    return html;
  }
  
  String _generateCacheKey(String name, dynamic value, Map<String, dynamic>? attrs) {
    return '$name:$value:${attrs?.toString() ?? ''}';
  }
}
```

### Lazy Rendering

```dart
class LazyWidget extends Widget with DefaultView {
  @override
  Future<String> render(String name, dynamic value, {Map<String, dynamic>? attrs, Renderer? renderer, String? templateName}) async {
    // Only render if value is not null and not empty
    if (value == null || value.toString().isEmpty) {
      return '<span class="empty-widget"></span>';
    }
    
    return super.render(name, value, attrs: attrs, renderer: renderer, templateName: templateName);
  }
}
```

## Best Practices

1. **Embrace the Three-Tier System**: Design widgets with templates first, DefaultView as reliable fallback
2. **Template Consistency**: Use the same context data structure for both templates and DefaultView
3. **Graceful Degradation**: Ensure DefaultView provides meaningful output, not just error messages
4. **Renderer Configuration**: Set up renderers at the view level for consistent form/widget rendering
5. **Performance**: Use template caching and consider widget-level caching for expensive operations
6. **Testing**: Test both template and DefaultView rendering paths
7. **Documentation**: Document custom widgets' context data and template requirements

## What's Next?

- **[Advanced Forms](10-advanced-forms.md)** - Complex form patterns and validation
- **[Testing Forms](12-testing.md)** - Testing strategies for widgets and forms
- **[Best Practices](13-best-practices.md)** - Production-ready form patterns

---

← [Form Fields](08-form-fields.md) | **Next: [Advanced Forms](10-advanced-forms.md)** → 