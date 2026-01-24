import '../property_context.dart';

/// Base interface for all Inertia property types
abstract class InertiaProp {
  /// Resolve the property value based on the provided context
  dynamic resolve(String key, PropertyContext context);

  /// Check if this property should be included in the response
  bool shouldInclude(String key, PropertyContext context);
}
