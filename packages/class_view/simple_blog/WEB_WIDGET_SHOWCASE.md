# Web Widget Showcase

Interactive web interface demonstrating all available form fields in class_view.

## Overview

The Widget Showcase provides a beautiful, interactive web interface where developers can:

- **See all field types** in action with live rendering
- **Test validation** by submitting the form
- **Learn field configurations** with inline documentation
- **Copy examples** for their own projects

## Routes

### Web Interface

- **GET `/widgets`** - Interactive form demonstration
- **POST `/widgets`** - Test form validation

### API Interface

- **GET `/api/widgets`** - JSON catalog of all fields
- **POST `/api/widgets`** - JSON validation testing

## Features

### Interactive Form

- 18+ field types demonstrated
- Live validation feedback
- Field categorization sidebar
- Success/error messaging
- Responsive design

### Field Categories

#### Text Fields

- `text_basic` - Simple text input
- `text_required` - Required validation
- `text_maxlength` - Character limit (50)
- `text_minlength` - Minimum length (10)
- `email` - Email validation
- `website` - URL validation

#### Boolean Fields

- `checkbox` - Required checkbox
- `newsletter` - Optional checkbox

#### Choice Fields

- `choice_single` - Dropdown select
- `choice_multiple` - Multiple selection

#### Numeric Fields

- `integer_basic` - Any whole number
- `integer_range` - Range validation (0-100)
- `decimal` - Decimal numbers

#### Date & Time Fields

- `date` - Date picker
- `time` - Time input
- `datetime` - Combined date/time

#### Special Fields

- `slug` - URL-friendly identifiers
- `uuid` - UUID validation
- `json_data` - JSON validation

## Usage Examples

### View the Showcase

```bash
# Start the server
dart run bin/simple_blog.dart

# Visit in browser
open http://localhost:8080/widgets
```

### Test Form Validation

Fill out the form and click "Test Form Validation" to see:

- ✅ Which fields passed validation
- ❌ Which fields have errors
- Success message on valid submission

### Navigate to Field Reference

Click any field in the sidebar to:

- Scroll to that field in the form
- Auto-focus the input
- See inline documentation

## Implementation

### View Class

`lib/src/views/web/widget_showcase_view.dart`

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
        'text_basic': CharField(...),
        'email': EmailField(...),
        // ... all other fields
      },
    );
  }
  
  @override
  Future<void> formValid(Form form) async {
    redirect('/widgets?success=true');
  }
}
```

### Templates

- `templates/forms/widget_showcase.liquid` - Main form view
- `templates/forms/widget_showcase_success.liquid` - Success page

### Styling

- TailwindCSS-inspired utilities
- Responsive grid layout
- Field type indicators (emoji icons)
- Interactive hover states
- Focus ring effects

## Design Highlights

### Visual Feedback

- ✉️ Email fields marked with envelope icon
- 🔗 URL fields marked with link icon
- 🔢 Number fields marked with numbers icon
- 📅 Date fields marked with calendar icon
- ⏰ Time fields marked with clock icon

### UX Features

- Sticky sidebar on desktop
- Mobile-responsive layout
- Smooth scrolling to fields
- Auto-focus on field click
- Success banner with dismiss button

### Accessibility

- Proper label associations
- Help text for all fields
- Clear error messages
- Keyboard navigation
- Focus management

## Integration

### Link from Home Page

The home page includes a prominent button:

```html
<a href="/widgets" class="bg-purple-600 text-white px-6 py-3...">
  🎨 Widget Showcase
</a>
```

### API Cross-Reference

Switch between web and API views:

```html
<a href="/api/widgets">View JSON API</a>
```

## Perfect For

- **Learning** - See all available fields
- **Testing** - Validate your understanding
- **Reference** - Quick lookup while coding
- **Demos** - Show off class_view capabilities

## Next Steps

- Try filling out the form
- Test different validation scenarios
- Compare web vs API implementations
- Use as template for your own forms

---

**Live Demo:** Visit `/widgets` after starting the server!
