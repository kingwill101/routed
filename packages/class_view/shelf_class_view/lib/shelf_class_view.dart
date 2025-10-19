/// Shelf adapter for class_view package
///
/// This library provides Shelf framework integration for class_view,
/// enabling Django-style class-based views to work seamlessly with Shelf.
library;

// Re-export class_view for convenience
export 'package:class_view/class_view.dart';

// Shelf integration
export 'src/shelf_adapter.dart';
export 'src/shelf_handler.dart';
export 'src/shelf_integration.dart';

// TODO: Export any libraries intended for clients of this package.
