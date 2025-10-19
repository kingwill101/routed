# View Engine Example

This example demonstrates how to use the view engine system in Routed to render templates.

## Features

- Template rendering with Mustache
- Layout system with template inheritance
- View caching
- Dynamic data binding
- Multiple template files

## Project Structure

```
views/
  ├── layout.mustache    # Base layout template
  └── home.mustache      # Home page template
main.dart               # Example application
```

## Running the Example

1. Make sure you have all dependencies installed:
   ```bash
   dart pub get
   ```

2. Run the server:
   ```bash
   dart run main.dart
   ```

3. Visit the following URLs:
    - http://localhost:3000/ - Home page (not logged in)
    - http://localhost:3000/profile - Profile page (simulated logged-in state)

## Implementation Details

The example shows:

1. How to configure the view engine system
2. How to register a template engine (Mustache)
3. How to use layouts and partials
4. How to pass data to templates
5. How to handle different view states (logged in/out)

## Template Features

- Conditional rendering (`{{#user}}` blocks)
- Loops (`{{#updates}}` blocks)
- HTML escaping (`{{value}}`) and raw output (`{{{value}}}`)
- Layout system with content blocks 