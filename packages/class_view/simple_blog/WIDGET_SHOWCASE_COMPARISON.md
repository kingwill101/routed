# Widget Showcase: Web vs API Comparison

SimpleBlog now provides **two complete implementations** of the widget showcase, demonstrating how class_view seamlessly
supports both web and API development.

## Quick Comparison

| Feature                 | Web Version (`/widgets`)             | API Version (`/api/widgets`) |
|-------------------------|--------------------------------------|------------------------------|
| **Route**               | GET/POST `/widgets`                  | GET/POST `/api/widgets`      |
| **View Class**          | `WebWidgetShowcaseView`              | `WidgetShowcaseView`         |
| **Base Class**          | `BaseFormView`                       | `View`                       |
| **Response Type**       | HTML templates                       | JSON                         |
| **UI**                  | Beautiful, interactive web interface | Structured data              |
| **Use Case**            | Human interaction                    | API integration, testing     |
| **Validation Feedback** | Visual form errors                   | JSON error objects           |
| **Success Response**    | Redirect with message                | JSON with status             |

## Implementation Comparison

### Web Version

```dart
class WebWidgetShowcaseView extends BaseFormView {
  @override
  Form getForm([Map<String, dynamic>? data]) {
    return Form(
      isBound: data != null,
      data: data ?? {},
      files: {},
      renderer: null,
      fields: {
        'email': EmailField(label: 'Email', ...),
        // ... more fields
      },
    );
  }
  
  @override
  Future<void> formValid(Form form) async {
    redirect('/widgets?success=true');
  }
}
```

**Key Points:**

- Extends `BaseFormView` - automatic form handling
- Returns HTML via Liquid templates
- Uses `redirect()` for success
- FormViewMixin handles validation automatically
- Perfect for user-facing interfaces

### API Version

```dart
class WidgetShowcaseView extends View {
  @override
  Future<void> get() async {
    final fields = _createShowcaseForm().fields;
    
    final showcase = <String, dynamic>{};
    for (final entry in fields.entries) {
      showcase[entry.key] = {
        'type': entry.value.runtimeType.toString(),
        'label': entry.value.label,
        'required': entry.value.required,
        'help_text': entry.value.helpText,
      };
    }
    
    sendJson({'fields': showcase});
  }
  
  @override
  Future<void> post() async {
    final data = await getJsonBody();
    final form = Form(
      isBound: true,
      data: data,
      files: {},
      fields: _createShowcaseForm().fields,
    );
    
    if (form.isValid()) {
      sendJson({'success': true, 'data': form.cleanedData});
    } else {
      sendJson({'success': false, 'errors': form.errors}, statusCode: 400);
    }
  }
}
```

**Key Points:**

- Extends `View` - full manual control
- Returns JSON via `sendJson()`
- Manual form validation
- Explicit error handling
- Perfect for API clients

## When to Use Each

### Use Web Version When:

- Building user interfaces
- Need visual form rendering
- Want automatic error display
- Targeting human users
- Building admin panels

### Use API Version When:

- Building REST APIs
- Need machine-readable responses
- Integrating with mobile apps
- Building microservices
- Automated testing

## Template vs JSON Response

### Web Response (HTML)

```html
<form method="post">
  <p>
    <label for="email">Email Address</label>
    <input type="email" name="email" id="email">
    <span>Enter a valid email address</span>
  </p>
  <!-- ... more fields -->
  <button type="submit">Test Form Validation</button>
</form>
```

### API Response (JSON)

```json
{
  "fields": {
    "email": {
      "type": "EmailField",
      "label": "Email Address",
      "required": false,
      "help_text": "Enter a valid email address",
      "example_value": "user@example.com"
    }
  },
  "endpoint": "/api/widgets",
  "method": "POST"
}
```

## Validation Comparison

### Web Validation Flow

1. User submits form
2. `BaseFormView` automatically validates
3. On error: Re-renders form with error messages
4. On success: Calls `formValid()` → redirects

### API Validation Flow

1. Client POSTs JSON
2. Manual form creation and validation
3. On error: Returns JSON with errors
4. On success: Returns JSON with cleaned data

## Code Reuse

Both implementations share:

- **Same field definitions** - DRY principle
- **Same validation logic** - consistent behavior
- **Same form structure** - unified approach
- **Different presentation** - template vs JSON

## Migration Path

Easy to convert between formats:

```dart
// Shared field definitions
Map<String, Field> get sharedFields => {
  'email': EmailField(label: 'Email', ...),
  // ... more fields
};

// Web version uses them
class WebView extends BaseFormView {
  @override
  Form getForm([Map<String, dynamic>? data]) {
    return Form(fields: sharedFields, ...);
  }
}

// API version uses them too
class ApiView extends View {
  Form _createForm(Map<String, dynamic> data) {
    return Form(fields: sharedFields, ...);
  }
}
```

## Performance Characteristics

### Web Version

- **Server-side rendering** - HTML generated per request
- **Heavier responses** - Full HTML + CSS
- **Browser caching** - Templates can be cached
- **Best for:** Low-frequency human interaction

### API Version

- **Lightweight responses** - Just JSON data
- **Faster** - Minimal serialization
- **Client rendering** - Frontend handles display
- **Best for:** High-frequency automated requests

## Testing Both

### Test Web Version

```bash
# Visit in browser
open http://localhost:8080/widgets

# Fill form and submit
# See visual feedback
```

### Test API Version

```bash
# Get field catalog
curl http://localhost:8080/api/widgets

# Test validation
curl -X POST http://localhost:8080/api/widgets \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com"}'
```

## Best Practices

### For Web Development

1. Extend `BaseFormView` for automatic handling
2. Use templates for presentation
3. Override `formValid()` for success handling
4. Let the framework handle errors
5. Use `redirect()` for post-submit navigation

### For API Development

1. Extend `View` for full control
2. Use `sendJson()` for responses
3. Manual validation with `form.isValid()`
4. Return appropriate HTTP status codes
5. Document your API with examples

## Conclusion

class_view's flexibility shines through these dual implementations. The same form logic powers both a beautiful web
interface and a robust JSON API, demonstrating:

- **Framework-agnostic design** - Works anywhere
- **Separation of concerns** - Logic vs presentation
- **Developer choice** - Pick the right tool
- **Code reuse** - Write once, use everywhere

Whether you're building a web app, REST API, or both, class_view has you covered!

---

**Try both versions and see the difference!**

- Web: http://localhost:8080/widgets
- API: http://localhost:8080/api/widgets
