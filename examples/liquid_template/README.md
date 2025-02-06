# Routed Liquid Template Example

This example demonstrates how to use Liquid templates with the routed package.

## Features Demonstrated

### Template Features
- Template includes using {% render %}
- Variable assignment using {% assign %}
- Filters (e.g., upcase, capitalize, date)
- Conditionals using {% if %}
- Loops using {% for %}
- Partials for layout composition

### Routes Demonstrated
- Static pages (/, /about)
- Dynamic content (/data/{name})
- Form handling (/contact, /submit-contact)
- Template inheritance examples (/extended)
- Success pages (/contact-success)

## Project Structure

```
templates/
├── partials/
│   ├── header.liquid    # Common header with styling
│   └── footer.liquid    # Common footer
├── about.liquid         # About page template
├── contact.liquid       # Contact form template
├── contact_success.liquid # Form submission success
├── dynamic.liquid       # Dynamic content example
├── extended.liquid      # Template features showcase
├── hello.liquid        # Simple example
└── home.liquid         # Homepage template
```

## Running the Example

1. Start the server:
```bash
dart run bin/server.dart
```

2. Visit the following URLs in your browser:
- http://localhost:3000/ (Home page)
- http://localhost:3000/hello (Basic example)
- http://localhost:3000/extended (Features showcase)
- http://localhost:3000/about (About page)
- http://localhost:3000/contact (Contact form)
- http://localhost:3000/data/YourName (Dynamic content)

## Template Examples

### Using Partials
```liquid
{% render "partials/header.liquid" %}
<h1>{{ page_title }}</h1>
<div class="content">
    <!-- Your content here -->
</div>
{% render "partials/footer.liquid" %}
```

### Variable Assignment
```liquid
{% assign page_title = 'Home Page' %}
{% assign footer_text = 'Welcome!' %}
```

### Loops and Conditionals
```liquid
{% if show_list %}
    <ul>
    {% for item in items %}
        <li>{{ item | upcase }}</li>
    {% endfor %}
    </ul>
{% endif %}
```

### Form Handling
```liquid
<form action="/submit-contact" method="post">
    <input type="text" name="name" required>
    <input type="email" name="email" required>
    <textarea name="message" required></textarea>
    <button type="submit">Send</button>
</form>
```

## Code Structure

- `bin/server.dart`: Server implementation with routes
- `templates/`: Directory containing Liquid templates
  - `partials/`: Reusable template components
- `pubspec.yaml`: Project dependencies

## Styling

The example includes a responsive design with:
- Clean, modern typography
- Card-based layout
- Hover effects
- Mobile-friendly design
- Consistent spacing
- Semantic HTML structure