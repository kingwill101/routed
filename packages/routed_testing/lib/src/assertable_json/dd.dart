import 'package:routed_testing/src/assertable_json/assertable_json_base.dart';

/// A mixin that provides debugging utilities for JSON data.
///
/// This mixin extends the functionality of `AssertableJsonBase` by adding
/// methods to print JSON data in a human-readable format and to stop execution
/// for debugging purposes.
mixin DebugMixin on AssertableJsonBase {
  /// Prints the JSON data in a human-readable format and stops execution.
  ///
  /// This method is similar to Laravel's `dd()` function. It prints the JSON
  /// data using the `printR` method and then throws an exception to stop
  /// execution.
  void dd() {
    printR();
    throw Exception('Execution stopped by dd()');
  }

  /// Prints the JSON data in a human-readable format.
  ///
  /// This method is similar to PHP's `print_r()` function. It prints the JSON
  /// data with a specified indentation level.
  ///
  /// [indent] specifies the number of spaces to use for each indentation level.
  /// The default value is 2.
  void printR({int indent = 2}) {
    _printJson(json, indent: indent);
  }

  /// Recursively prints JSON data with indentation.
  ///
  /// This method is used internally by `printR` to print JSON data. It handles
  /// different types of JSON structures, including maps and lists, and prints
  /// them with the specified indentation.
  ///
  /// [data] is the JSON data to print.
  /// [indent] specifies the number of spaces to use for each indentation level.
  /// [level] specifies the current level of indentation. The default value is 0.
  void _printJson(dynamic data, {int indent = 2, int level = 0}) {
    final indentation = ' ' * indent * level;

    if (data is Map) {
      print('$indentation{');
      data.forEach((key, value) {
        print('$indentation  $key:');
        _printJson(value, indent: indent, level: level + 1);
      });
      print('$indentation}');
    } else if (data is List) {
      print('$indentation[');
      for (var item in data) {
        _printJson(item, indent: indent, level: level + 1);
      }
      print('$indentation]');
    } else {
      print('$indentation$data');
    }
  }
}
