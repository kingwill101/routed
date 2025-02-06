# Routed Jinja Template Example

This example demonstrates how to use Jinja templates with the routed package.

## Features Demonstrated

### Template Features
- Variable rendering
- Conditional statements
- Loops
- Template inheritance
- Template blocks
- Custom data passing

## Running the Example

1. Start the server:
```bash
dart run bin/server.dart
```

2. Visit the following URLs in your browser:
- http://localhost:3000/hello
- http://localhost:3000/extended
- http://localhost:3000/data

## Template Examples

### Basic Template (hello.html)
```html
<!DOCTYPE html>
<html>
  <body>
    <h1>Hello {{ name }}!</h1>
    {% if showList %}
      <ul>
      {% for item in items %}
        <li>{{ item }}</li>
      {% endfor %}
      </ul>
    {% endif %}
    {% block content %}{% endblock %}
  </body>
</html>
```

### Extended Template (extended.html)
```html
{% extends "hello.html" %}
{% block content %}
  <p>Extended content here</p>
{% endblock %}
```

## Code Structure

- `bin/server.dart`: Server implementation with template examples
- `templates/`: Directory containing Jinja templates
- `pubspec.yaml`: Project dependencies