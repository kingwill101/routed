/// A Django-inspired class-based view system for Dart web frameworks.
///
/// This library provides a powerful and flexible way to build web applications
/// using class-based views, similar to Django's class-based views.
library;

// Adapter interface
export 'src/adapter/view_adapter.dart';

// Request and Response objects
export 'src/request/request.dart';
export 'src/response/response.dart';

// Views and mixins
export 'src/view/base_views/base_views.dart';

// HTTP exceptions
export 'src/view/exceptions/http.dart';

// Form system exports
export 'src/view/form/form.dart';

// Template system
export 'src/view/form/template_renderer.dart';
export 'src/view/mixins/mixins.dart';
export 'src/view/template_manager.dart';

// Core view exports
export 'src/view/view.dart';

// Template engine interface
export 'src/view/view_engine.dart';
