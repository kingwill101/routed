part of 'engine.dart';

/// Extension utilities for working with the parameter map returned by
/// `EngineRoute.extractParameters()` or available through
/// `EngineContext.params`.
///
/// Example usage:
///
/// ```dart
/// final id = ctx.params.require<int>('id');
/// final slug = ctx.params.require<String>('slug');
/// final page = ctx.params['page'] as int?; // optional
/// ```
extension ParamMapX on Map<String, dynamic> {
  /// Returns the value for [key] if present and of type [T], otherwise
  /// throws an [ArgumentError].
  ///
  /// The optional [message] lets you override the default error text.
  T require<T>(String key, {String? message}) {
    if (!containsKey(key) || this[key] == null) {
      throw StateError(
        message ??
            'Missing required route parameter "$key" '
                '(expected type ${_typeName<T>()})',
      );
    }

    final value = this[key];

    if (value is! T) {
      throw StateError(
        message ??
            'Route parameter "$key" has unexpected type '
                '(expected ${_typeName<T>()}, actual ${value.runtimeType})',
      );
    }

    return value;
  }

  /// Same as [require] but returns a non-null `Object` when the concrete
  /// type is not important.
  Object requireAny(String key, {String? message}) =>
      require<Object>(key, message: message);

  /// Human-readable type name helper.
  String _typeName<T>() {
    final t = T.toString();
    return t == 'dynamic' ? 'Object' : t;
  }
}
