/// Routed adapter for class_view package
///
/// This library provides Routed framework integration for class_view,
/// enabling Django-style class-based views to work seamlessly with Routed.
library;

// Re-export class_view for convenience
export 'package:class_view/class_view.dart';

// Routed integration
export 'src/routed_adapter.dart';
export 'src/routed_handler.dart';
export 'src/routed_integration.dart';

// TODO: Export any libraries intended for clients of this package.
