# Class View Documentation

🏗️ **Django-inspired class-based views for Dart web frameworks**

Welcome to the complete guide for building web applications with clean, composable class-based views.

## 📚 Tutorial Sections

### Getting Started

- **[Getting Started](01-getting-started.md)** - Quick introduction and first working example
- **[Core Concepts](02-core-concepts.md)** - Framework-agnostic design and architecture

### Views

- **[Basic Views](03-basic-views.md)** - TemplateView, RedirectView, and custom views
- **[CRUD Views](04-crud-views.md)** - Complete Create, Read, Update, Delete operations
- **[Mixins & Composition](05-mixins.md)** - Building views with composable functionality
- **[Framework Integration](06-framework-integration.md)** - Shelf, Routed, and custom adapters

### Forms

- **[Forms Overview](07-forms-overview.md)** - Form system introduction and basic usage
- **[Form Fields](08-form-fields.md)** - Complete guide to all available field types
- **[Form Widgets](09-form-widgets.md)** - Customizing form rendering and input widgets
- **[Advanced Forms](10-advanced-forms.md)** - Dynamic forms, validation, and complex patterns

### Advanced Topics

- **[Template Integration](11-templates.md)** - Liquify templates and view rendering
- **[Testing](12-testing.md)** - Testing views, forms, and complete applications
- **[Best Practices](13-best-practices.md)** - Patterns for maintainable applications
- **[Advanced Topics](14-advanced-topics.md)** - Custom adapters, caching, and API development

## 🚀 Quick Start

```dart
// 1. Install the package
dependencies:
  class_view: ^0.1.0
  class_view_shelf: ^0.1.0  # For Shelf integration

// 2. Create a view
class PostListView extends ListView<Post> {
  @override
  Future<({List<Post> items, int total})> getObjectList({...}) async {
    return await PostRepository.findAll();
  }
}

// 3. Add to router
router.getView('/posts', () => PostListView());
```

## 🎯 Key Features

- **Clean Syntax**: `CreateView<Post>` instead of verbose generics
- **Framework Agnostic**: Same views work with Shelf, Routed, or custom frameworks
- **Django-Inspired**: Familiar patterns for web developers
- **Composable Mixins**: Mix and match functionality without inheritance hell
- **Type Safe**: Full Dart type safety with clean APIs

## 🧩 Architecture Overview

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│    Views    │◄──►│   Adapters   │◄──►│ Frameworks  │
│             │    │              │    │             │
│ ListView    │    │ ShelfAdapter │    │    Shelf    │
│ DetailView  │    │RoutedAdapter │    │   Routed    │
│ CreateView  │    │CustomAdapter │    │   Custom    │
└─────────────┘    └──────────────┘    └─────────────┘
```

Views remain completely framework-independent through the adapter pattern.

## 💡 Philosophy

Class View follows Django's philosophy of **"Don't Repeat Yourself"** and **"Convention over Configuration"**:

- **Sensible Defaults**: Most functionality works out of the box
- **Override When Needed**: Customize only what you need to change
- **Composition over Inheritance**: Use mixins to add functionality
- **Framework Independence**: Write once, run anywhere

## 📖 Examples

Each tutorial section includes practical examples. For complete applications, see:

- **[Blog Example](../examples/)** - Full CRUD blog with templates
- **[API Example](../examples/)** - RESTful API with authentication
- **[Forms Example](../examples/)** - Complex forms with validation

## 🤝 Contributing

Found an issue or want to improve the documentation?

1. Check existing issues and discussions
2. Follow the documentation style guide
3. Include working code examples
4. Test examples before submitting

---

**Next: [Getting Started](01-getting-started.md)** → 