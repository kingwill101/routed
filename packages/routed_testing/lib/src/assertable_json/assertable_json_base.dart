import 'package:routed_testing/src/assertable_json/assertable_json.dart';
import 'package:test/test.dart';

import 'interaction.dart';

typedef AssertableJsonCallback = Function(AssertableJson);

/// An abstract base class for assertable JSON data.
///
/// This class provides a set of utility methods for working with JSON data,
/// including type-safe access to values, lists, and maps. It also includes
/// a mixin for handling interactions, which can be used for testing or
/// other purposes.
abstract class AssertableJsonBase with InteractionMixin {
  // Get value at path with type safety
  /// Gets the value at the specified [path] and casts it to the specified type [T].
  ///
  /// If the value at the specified path is `null`, this method will return `null`.
  /// If the value at the specified path is not of the expected type [T], this
  /// method will return `null`.
  ///
  /// Example usage:
  ///
  /// final value = json.get<int>('some.nested.path');
  ///
  T? get<T>(String path) {
    var current = json;
    final keys = path.split('.');

    for (var key in keys) {
      if (current == null) return null;
      current = current[key];
    }

    return current as T?;
  }

  // Get required value or throw
  /// Gets the value at the specified [path] and casts it to the specified type [T].
  ///
  /// If the value at the specified [path] is `null`, this method will throw an exception.
  /// If the value at the specified [path] is not of the expected type [T], this method
  /// will also throw an exception.
  ///
  /// Example usage:
  ///
  /// final value = json.getRequired<int>('some.nested.path');
  T getRequired<T>(String path) {
    final value = get(path);

    if (value == null) {
      fail('Required value at path [$path] was null');
    }

    // General type checking
    if (value is! T) {
      fail('Property [$path] must be of type $T, got ${value.runtimeType}');
    }

    return value;
  }

  // Get list of items with type safety
  /// Gets a list of items at the specified [path] and casts them to the specified type [T].
  ///
  /// If the value at the specified [path] is `null` or not a [List], this method will return an empty list.
  /// Otherwise, it will return the list with the items cast to the specified type [T].
  List<T> getList<T>(String path) {
    final list = get<List>(path);
    return list?.cast<T>() ?? [];
  }

  // Get map with type safety
  Map<String, T> getMap<T>(String path) {
    final map = get<Map>(path);
    return map?.cast<String, T>() ?? {};
  }

  // Check if path exists
  /// Checks if the specified [path] exists within the JSON data.
  ///
  /// This method traverses the JSON data along the specified [path] and returns `true`
  /// if all the keys in the path exist, and `false` otherwise.
  ///
  /// If the JSON data at any point in the path is not a [Map], this method will return
  /// `false`.
  bool exists(String path) {
    var current = json;
    final keys = path.split('.');

    for (var key in keys) {
      if (current == null || current is! Map) return false;
      if (!current.containsKey(key)) return false;
      current = current[key];
    }
    return true;
  }

  // Get length of array or object
  /// Gets the length of the JSON data at the specified [path].
  ///
  /// If the JSON data at the specified [path] is a [List], this method will return the length of the list.
  /// If the JSON data at the specified [path] is a [Map], this method will return the number of key-value pairs in the map.
  /// If the JSON data at the specified [path] is neither a [List] nor a [Map], this method will return 0.
  ///
  /// If [path] is not provided, the length of the root JSON data will be returned.
  int length([String? path]) {
    final target = path != null ? get(path) : json;
    return target is List
        ? target.length
        : target is Map
            ? target.length
            : 0;
  }

  // Get all keys at path
  /// Gets a list of all keys at the specified [path] in the JSON data.
  ///
  /// If the JSON data at the specified [path] is a [Map], this method will return a list
  /// of all the keys in the map. If the JSON data is not a map, an empty list will be
  /// returned.
  ///
  /// If [path] is `null` or not provided, the keys of the root JSON data will be returned.
  List<String> keys([String? path]) {
    final target = path != null ? get(path) : json;
    return target is Map ? target.keys.cast<String>().toList() : [];
  }

  // Get all values at path
  /// Gets a list of all the values at the specified [path] within the JSON data.
  ///
  /// If the JSON data at the specified [path] is a [Map], this method will return a list
  /// of all the values in the map, cast to the specified type [T].
  ///
  /// If the JSON data at the specified [path] is not a [Map], or if the [path] does not
  /// exist, an empty list will be returned.
  ///
  /// This method is useful for extracting a list of values from a JSON object, with
  /// type safety.
  List<T> values<T>([String? path]) {
    final target = path != null ? get(path) : json;
    return target is Map ? target.values.cast<T>().toList() : [];
  }

  /// Scopes the current [AssertableJson] instance to the specified [key] and calls the provided
  ///  [callback] function with the scoped instance.
  ///
  /// This method is useful for navigating and asserting on nested JSON data. It creates a new
  ///  [AssertableJson] instance with the value at the specified [key] and passes it to the
  /// [callback] function.
  ///  The current [AssertableJson] instance is then returned to allow for method chaining.
  ///
  /// After the [callback] function is executed, the [verifyInteracted] method
  ///  is called on the scoped [AssertableJson] instance to ensure that all
  /// assertions within the callback were executed.
  ///
  /// The [interactsWith] method is also called with the [key] to track which keys
  /// have been interacted with during the assertion process.
  AssertableJson scope(String key, Function(AssertableJson) callback) {
    final props = json[key];

    if (props == null) {
      fail('Required value at path [$key] was null');
    }
    final scope = AssertableJson(props);
    callback(scope);
    scope.verifyInteracted();
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Scopes the current [AssertableJson] instance to the first element of the JSON data.
  ///
  /// If the JSON data is a list, this method will return a new [AssertableJson] instance
  /// that represents the first element of the list. If the list is empty, an exception
  /// will be thrown.
  ///
  /// If the JSON data is an object, this method will return a new [AssertableJson] instance
  /// that represents the first key-value pair of the object. If the object is empty, an
  /// exception will be thrown.
  ///
  /// The [callback] function is called with the scoped [AssertableJson] instance, allowing
  /// further assertions or interactions to be performed on the scoped data.
  ///
  /// Returns the current [AssertableJson] instance to allow method chaining.
  AssertableJson first(Function(AssertableJson) callback) {
    if (json is List) {
      expect(json.isNotEmpty, isTrue,
          reason: 'Cannot scope onto the first element because array is empty');
      return AssertableJson(json[0]).tap(callback);
    }

    expect(json.isNotEmpty, isTrue,
        reason: 'Cannot scope onto the first element because object is empty');
    final key = json.keys.first;
    interactsWith(key);
    return scope(key, callback);
  }

  /// Iterates over the JSON data, either an array or an object, and calls the provided [callback] function for each element.
  ///
  /// If the JSON data is an array, the [callback] function is called for each item in the array. If the JSON data is an object, the [callback] function is called for each key-value pair in the object.
  ///
  /// Returns the current [AssertableJson] instance to allow for method chaining.
  AssertableJson each(Function(AssertableJson) callback) {
    if (json is List) {
      expect(json.isNotEmpty, isTrue,
          reason: 'Cannot iterate over empty array');
      for (var item in json) {
        AssertableJson(item).tap(callback);
      }
      return this as AssertableJson;
    }

    expect(json.isNotEmpty, isTrue, reason: 'Cannot iterate over empty object');
    for (final key in json.keys) {
      interactsWith(key);
      scope(key, callback);
    }
    return this as AssertableJson;
  }
}
